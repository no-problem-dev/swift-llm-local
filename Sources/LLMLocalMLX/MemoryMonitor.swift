import Foundation

/// メモリ情報を提供するプロトコル
///
/// 準拠する型はデバイスの総メモリと利用可能メモリの値を提供します。
/// テスト容易性のための依存性注入を可能にし、テストでシステム照会の代わりに
/// モックプロバイダーを使用できます。
public protocol MemoryProvider: Sendable {
    /// デバイスの物理メモリ総量をバイト単位で返します。
    func totalMemoryBytes() -> UInt64

    /// 現在利用可能なメモリをバイト単位で返します。
    func availableMemoryBytes() -> UInt64
}

/// `ProcessInfo` とプラットフォーム固有APIを使用するシステム実装
///
/// iOS/tvOS/watchOS では `os_proc_available_memory()` を、
/// macOS では Mach API 経由の `vm_statistics64` をフォールバックとして使用します。
struct SystemMemoryProvider: MemoryProvider, Sendable {
    func totalMemoryBytes() -> UInt64 {
        UInt64(ProcessInfo.processInfo.physicalMemory)
    }

    func availableMemoryBytes() -> UInt64 {
        #if os(iOS) || os(tvOS) || os(watchOS)
        return UInt64(os_proc_available_memory())
        #else
        // macOS fallback: estimate available memory using Mach vm_statistics64.
        // Use host_page_size() which is a function call and concurrency-safe.
        var pageSize: vm_size_t = 0
        host_page_size(mach_host_self(), &pageSize)

        var stats = vm_statistics64()
        var count = mach_msg_type_number_t(
            MemoryLayout<vm_statistics64>.size / MemoryLayout<integer_t>.size
        )
        let result = withUnsafeMutablePointer(to: &stats) { statsPtr in
            statsPtr.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { ptr in
                host_statistics64(mach_host_self(), HOST_VM_INFO64, ptr, &count)
            }
        }
        guard result == KERN_SUCCESS else {
            // Fallback: return half of total memory as a rough estimate
            return UInt64(ProcessInfo.processInfo.physicalMemory) / 2
        }
        let ps = UInt64(pageSize)
        let free = UInt64(stats.free_count) * ps
        let inactive = UInt64(stats.inactive_count) * ps
        return free + inactive
        #endif
    }
}

/// デバイスメモリを監視し、メモリ適応型の設定を提供するアクター
///
/// `MemoryMonitor` は `os_proc_available_memory()` を使用して利用可能メモリを追跡し、
/// メモリ警告通知を監視してモデルのアンロードをトリガーします。
///
/// ## Usage
///
/// ```swift
/// let monitor = MemoryMonitor()
/// let contextLength = await monitor.recommendedContextLength()
///
/// await monitor.startMonitoring {
///     await backend.unloadModel()
/// }
/// ```
public actor MemoryMonitor {

    /// コンテキスト長推奨のためのメモリ閾値。
    public enum DeviceMemoryTier: Sendable, Equatable {
        /// 8GB以下（例: iPhone 16 Pro）
        case standard
        /// 12GB以上（例: iPhone 17 Pro）
        case high
    }

    /// メモリ警告発生時に呼び出されるコールバック。
    /// コールバックはモデルのアンロードをトリガーする必要があります。
    public typealias MemoryWarningHandler = @Sendable () async -> Void

    private var memoryWarningHandler: MemoryWarningHandler?
    private var isMonitoring: Bool = false
    private var observationTask: Task<Void, Never>?

    /// メモリ情報のプロバイダー。テスト容易性のために注入可能。
    private let memoryProvider: any MemoryProvider

    /// 新しいメモリモニターを作成します。
    ///
    /// - Parameter memoryProvider: メモリ情報のプロバイダー。
    ///   デフォルトはOSに問い合わせる `SystemMemoryProvider`。
    public init(memoryProvider: (any MemoryProvider)? = nil) {
        self.memoryProvider = memoryProvider ?? SystemMemoryProvider()
    }

    /// 監視が現在アクティブかどうか。
    ///
    /// `startMonitoring` と `stopMonitoring` が正しく動作することを検証するために
    /// テスト目的で公開されています。
    public var isCurrentlyMonitoring: Bool {
        isMonitoring
    }

    /// デバイスメモリに基づく推奨コンテキスト長を返します。
    ///
    /// - 8GB以下: 2048
    /// - 12GB以上: 4096
    ///
    /// - Returns: 推奨コンテキスト長（トークン単位）。
    public func recommendedContextLength() -> Int {
        let tier = deviceMemoryTier()
        switch tier {
        case .standard: return 2048
        case .high: return 4096
        }
    }

    /// 物理メモリ総量に基づくデバイスメモリティアを返します。
    ///
    /// - Returns: 12GB未満のデバイスは `.standard`、12GB以上は `.high`。
    public func deviceMemoryTier() -> DeviceMemoryTier {
        let totalMemory = memoryProvider.totalMemoryBytes()
        if totalMemory >= 12 * 1024 * 1024 * 1024 { // 12GB
            return .high
        } else {
            return .standard
        }
    }

    /// 現在利用可能なメモリをバイト単位で返します。
    ///
    /// - Returns: プロセスが現在利用可能なメモリのバイト数。
    public func availableMemory() -> UInt64 {
        memoryProvider.availableMemoryBytes()
    }

    /// メモリ警告の監視を開始します。
    ///
    /// メモリ警告が検出されると、ハンドラが呼び出されます。
    /// このメソッドを複数回呼び出すとハンドラは更新されますが、
    /// 重複するオブザーバーは作成されません。
    ///
    /// - Parameter handler: メモリ警告を受信した際に呼び出されるクロージャ。
    public func startMonitoring(onWarning handler: @escaping MemoryWarningHandler) {
        self.memoryWarningHandler = handler
        guard !isMonitoring else { return }
        isMonitoring = true

        let handlerRef = handler
        observationTask = Task { [weak self] in
            let notifications = NotificationCenter.default.notifications(
                named: Self.memoryWarningNotificationName
            )
            for await _ in notifications {
                guard !Task.isCancelled else { break }
                await handlerRef()
            }
            await self?.setMonitoring(false)
        }
    }

    /// メモリ警告の監視を停止します。
    ///
    /// 通知監視タスクをキャンセルし、ハンドラをクリアします。
    public func stopMonitoring() {
        observationTask?.cancel()
        observationTask = nil
        isMonitoring = false
        memoryWarningHandler = nil
    }

    private func setMonitoring(_ value: Bool) {
        isMonitoring = value
    }

    /// メモリ警告の通知名。
    ///
    /// iOS では `UIApplication.didReceiveMemoryWarningNotification` に対応します。
    /// パッケージでの UIKit 依存を避けるために文字列ベースの名前を使用しています。
    nonisolated public static let memoryWarningNotificationName = Notification.Name(
        "UIApplicationDidReceiveMemoryWarningNotification"
    )
}
