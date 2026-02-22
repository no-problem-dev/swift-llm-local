import Foundation

/// Protocol for providing memory information.
///
/// Conforming types supply total and available memory values.
/// The protocol enables dependency injection for testability,
/// allowing tests to use mock providers instead of querying the system.
public protocol MemoryProvider: Sendable {
    /// Returns the total physical memory of the device in bytes.
    func totalMemoryBytes() -> UInt64

    /// Returns the currently available memory in bytes.
    func availableMemoryBytes() -> UInt64
}

/// System implementation using `ProcessInfo` and platform-specific APIs.
///
/// On iOS/tvOS/watchOS, uses `os_proc_available_memory()` for available memory.
/// On macOS, uses `vm_statistics64` via Mach APIs as a fallback.
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

/// Monitors device memory and provides memory-aware configuration.
///
/// `MemoryMonitor` tracks available memory using `os_proc_available_memory()`
/// and listens for memory warning notifications to trigger model unloading.
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

    /// Memory thresholds for context length recommendation.
    public enum DeviceMemoryTier: Sendable, Equatable {
        /// 8GB or less (e.g., iPhone 16 Pro)
        case standard
        /// 12GB or more (e.g., iPhone 17 Pro)
        case high
    }

    /// Callback to be invoked when a memory warning occurs.
    /// The callback should trigger model unloading.
    public typealias MemoryWarningHandler = @Sendable () async -> Void

    private var memoryWarningHandler: MemoryWarningHandler?
    private var isMonitoring: Bool = false
    private var observationTask: Task<Void, Never>?

    /// Provider for memory information, injectable for testability.
    private let memoryProvider: any MemoryProvider

    /// Creates a new memory monitor.
    ///
    /// - Parameter memoryProvider: The provider for memory information.
    ///   Defaults to `SystemMemoryProvider` which queries the OS.
    public init(memoryProvider: (any MemoryProvider)? = nil) {
        self.memoryProvider = memoryProvider ?? SystemMemoryProvider()
    }

    /// Whether monitoring is currently active.
    ///
    /// This property is exposed for testing purposes to verify
    /// that `startMonitoring` and `stopMonitoring` work correctly.
    public var isCurrentlyMonitoring: Bool {
        isMonitoring
    }

    /// Returns the recommended context length based on device memory.
    ///
    /// - 8GB or less: 2048
    /// - 12GB or more: 4096
    ///
    /// - Returns: The recommended context length in tokens.
    public func recommendedContextLength() -> Int {
        let tier = deviceMemoryTier()
        switch tier {
        case .standard: return 2048
        case .high: return 4096
        }
    }

    /// Returns the device memory tier based on total physical memory.
    ///
    /// - Returns: `.standard` for devices with less than 12GB,
    ///   `.high` for devices with 12GB or more.
    public func deviceMemoryTier() -> DeviceMemoryTier {
        let totalMemory = memoryProvider.totalMemoryBytes()
        if totalMemory >= 12 * 1024 * 1024 * 1024 { // 12GB
            return .high
        } else {
            return .standard
        }
    }

    /// Returns currently available memory in bytes.
    ///
    /// - Returns: The number of bytes of memory currently available to the process.
    public func availableMemory() -> UInt64 {
        memoryProvider.availableMemoryBytes()
    }

    /// Starts monitoring for memory warnings.
    ///
    /// When a memory warning is detected, the handler will be called.
    /// Calling this method multiple times will update the handler
    /// but will not create duplicate observers.
    ///
    /// - Parameter handler: The closure to call when a memory warning is received.
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

    /// Stops monitoring for memory warnings.
    ///
    /// Cancels the notification observation task and clears the handler.
    public func stopMonitoring() {
        observationTask?.cancel()
        observationTask = nil
        isMonitoring = false
        memoryWarningHandler = nil
    }

    private func setMonitoring(_ value: Bool) {
        isMonitoring = value
    }

    /// The notification name for memory warnings.
    ///
    /// On iOS this corresponds to `UIApplication.didReceiveMemoryWarningNotification`.
    /// A string-based name is used to avoid a UIKit dependency in the package.
    nonisolated public static let memoryWarningNotificationName = Notification.Name(
        "UIApplicationDidReceiveMemoryWarningNotification"
    )
}
