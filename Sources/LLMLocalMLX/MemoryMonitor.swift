import Foundation
import LLMLocalClient

/// Source of the memory numbers used to decide what a device can run.
///
/// Exists so tests can substitute fixed numbers for whatever the running device happens to
/// report; production code uses the system implementation.
public protocol MemoryProvider: Sendable {
    /// The device's total physical memory in bytes.
    func totalMemoryBytes() -> UInt64

    /// Memory available for use right now, in bytes.
    ///
    /// The meaning is platform-specific. On iOS-family platforms this is headroom left to this
    /// process before the system kills it; elsewhere it is an estimate of reclaimable system
    /// memory. Neither is this process's current footprint.
    ///
    /// - Throws: ``LLMLocalError/memoryUnreadable(reason:)`` when no measurement can be taken. An
    ///   implementation must not substitute a plausible number: the value decides whether weights
    ///   are loaded into a process jetsam is about to kill, and a caller cannot tell a guess from a
    ///   reading.
    func availableMemoryBytes() throws -> UInt64
}

/// Memory numbers read from the OS.
///
/// On iOS, tvOS, and watchOS, available memory is `os_proc_available_memory()`: the bytes this
/// process may still allocate before it exceeds its jetsam limit. That is a per-process budget,
/// not free system RAM, and it is what actually decides whether the app survives.
///
/// On macOS there is no such call, so free plus inactive pages from Mach's `vm_statistics64`
/// stand in — a system-wide estimate of what could be reclaimed, which is a much looser bound
/// than the iOS budget. Both Mach calls are checked, and a failure in either throws
/// ``LLMLocalError/memoryUnreadable(reason:)`` rather than producing a number.
///
/// Nothing is guessed here. Half of physical memory used to be returned when the statistics query
/// failed, and the page size query's own return code was discarded entirely — leaving a page size
/// of zero, an available figure of zero, and every model on the device judged too large, with no
/// way for the caller to tell that from a device genuinely out of memory.
struct SystemMemoryProvider: MemoryProvider, Sendable {
    func totalMemoryBytes() -> UInt64 {
        UInt64(ProcessInfo.processInfo.physicalMemory)
    }

    func availableMemoryBytes() throws -> UInt64 {
        #if os(iOS) || os(tvOS) || os(watchOS)
        return UInt64(os_proc_available_memory())
        #else
        // macOS: estimate available memory from Mach's vm_statistics64.
        // host_page_size() is a function call and concurrency-safe.
        var pageSize: vm_size_t = 0
        let pageSizeResult = host_page_size(mach_host_self(), &pageSize)
        guard pageSizeResult == KERN_SUCCESS else {
            throw LLMLocalError.memoryUnreadable(
                reason: "host_page_size failed with kern_return_t \(pageSizeResult)."
            )
        }
        guard pageSize > 0 else {
            throw LLMLocalError.memoryUnreadable(
                reason: "host_page_size succeeded but reported a page size of zero."
            )
        }

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
            throw LLMLocalError.memoryUnreadable(
                reason: "host_statistics64 failed with kern_return_t \(result)."
            )
        }
        let ps = UInt64(pageSize)
        let free = UInt64(stats.free_count) * ps
        let inactive = UInt64(stats.inactive_count) * ps
        return free + inactive
        #endif
    }
}

/// Memory admission checks and memory-warning observation for on-device inference.
///
/// Answers two questions the caller has to ask before and during a load: how big a model this
/// device can hold, and when to give the memory back. Neither is enforced anywhere else —
/// ``MLXBackend`` will load whatever it is given.
///
/// The stakes differ from a server: exceeding the budget on iOS means jetsam terminates the app.
/// There is no allocation failure to catch and no error to show the user, so the check has to
/// happen before the load, and a memory warning has to be treated as the last chance to unload.
///
/// This is event-driven, not sampled. Nothing polls; the actor observes the memory-warning
/// notification and reads memory numbers only when asked.
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

    /// Coarse device classes used to pick a context length.
    public enum DeviceMemoryTier: Sendable, Equatable {
        /// Under 12 GB of physical memory, for example an iPhone 16 Pro at 8 GB.
        case standard
        /// 12 GB of physical memory or more, for example an iPhone 17 Pro.
        case high
    }

    /// Called when the system reports memory pressure.
    ///
    /// It should unload the model. The process is already close to being killed by the time this
    /// runs, so the handler is the last opportunity to release the weights.
    public typealias MemoryWarningHandler = @Sendable () async -> Void

    private var memoryWarningHandler: MemoryWarningHandler?
    private var isMonitoring: Bool = false
    private var observationTask: Task<Void, Never>?

    private let memoryProvider: any MemoryProvider

    /// Creates a memory monitor.
    ///
    /// - Parameter memoryProvider: Where the memory numbers come from. Defaults to querying the
    ///   OS; inject a stub to test admission decisions on a device other than the one running.
    public init(memoryProvider: (any MemoryProvider)? = nil) {
        self.memoryProvider = memoryProvider ?? SystemMemoryProvider()
    }

    /// Whether warning observation is currently running.
    ///
    /// Exposed so tests can assert that starting and stopping take effect.
    public var isCurrentlyMonitoring: Bool {
        isMonitoring
    }

    /// Returns a context length the device can afford, in tokens.
    ///
    /// 2048 below 12 GB of physical memory, 4096 at or above it. The context length is what
    /// bounds KV cache growth, which is the part of the footprint that keeps climbing during a
    /// long conversation, so the tier is deliberately conservative rather than tuned per model.
    public func recommendedContextLength() -> Int {
        let tier = deviceMemoryTier()
        switch tier {
        case .standard: return 2048
        case .high: return 4096
        }
    }

    /// Classifies the device by physical memory, with 12 GB as the boundary between tiers.
    public func deviceMemoryTier() -> DeviceMemoryTier {
        let totalMemory = memoryProvider.totalMemoryBytes()
        if totalMemory >= 12 * 1024 * 1024 * 1024 { // 12GB
            return .high
        } else {
            return .standard
        }
    }

    public func totalMemory() -> UInt64 {
        memoryProvider.totalMemoryBytes()
    }

    /// Memory this process can still allocate, in bytes.
    ///
    /// On iOS this is the jetsam headroom rather than free RAM, and it moves with what other apps
    /// and this app's own caches are doing, so it is only meaningful at the moment it is read.
    ///
    /// - Throws: ``LLMLocalError/memoryUnreadable(reason:)`` when the measurement cannot be taken.
    public func availableMemory() throws -> UInt64 {
        try memoryProvider.availableMemoryBytes()
    }

    /// Whether the model's estimated memory use fits within the current budget.
    ///
    /// Advisory: nothing in the load path consults this. A caller that skips the check and loads
    /// an oversized model gets a terminated app, not a thrown error.
    ///
    /// - Throws: ``LLMLocalError/memoryUnreadable(reason:)`` when the budget cannot be measured.
    ///   `false` means the model does not fit, and is never how an unavailable measurement is
    ///   reported — that answer would reject every model on the device, which is what the caller
    ///   would see if the budget silently came back as zero.
    public func isModelCompatible(_ spec: ModelSpec) throws -> Bool {
        try Double(spec.estimatedMemoryBytes) <= Double(maxAllowedModelMemory())
    }

    /// The largest model this device should be asked to hold, in bytes.
    ///
    /// The baseline differs by platform because the constraint does:
    ///
    /// - **iOS, tvOS, watchOS**: jetsam kills the app well before physical RAM runs out, so the
    ///   budget is 80% of what the process may still allocate right now
    ///   (`os_proc_available_memory()`), not 80% of the device's RAM. The 20% margin covers what
    ///   the weights alone do not: KV cache, activations, MLX's buffer cache, and the rest of the
    ///   app.
    /// - **macOS**: unified memory is plentiful and there is no equivalent per-process kill, so
    ///   the budget stays at 80% of total physical memory.
    ///
    /// - Throws: ``LLMLocalError/memoryUnreadable(reason:)`` when the platform budget cannot be
    ///   measured.
    public func maxAllowedModelMemory() throws -> UInt64 {
        #if os(iOS) || os(tvOS) || os(watchOS)
        // Available memory moves at runtime, so decide from the value at call time. Sizing against
        // physical total instead passes a 4-5 GB model on an 8 GB device and crashes on hardware.
        return try UInt64(Double(memoryProvider.availableMemoryBytes()) * 0.8)
        #else
        return UInt64(Double(memoryProvider.totalMemoryBytes()) * 0.8)
        #endif
    }

    /// Starts observing memory warnings and calls the handler on each one.
    ///
    /// Calling this again replaces the handler without adding a second observer, so repeated
    /// calls are safe. The handler runs for every warning, not once, and should unload the model.
    ///
    /// - Parameter handler: Invoked on each memory warning.
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

    /// Stops observing memory warnings, cancelling the observation task and dropping the handler.
    public func stopMonitoring() {
        observationTask?.cancel()
        observationTask = nil
        isMonitoring = false
        memoryWarningHandler = nil
    }

    private func setMonitoring(_ value: Bool) {
        isMonitoring = value
    }

    /// Name of the notification treated as a memory warning.
    ///
    /// Spelled as a string so the package does not have to import UIKit; on iOS it is the same
    /// name as `UIApplication.didReceiveMemoryWarningNotification`. Nothing posts it on macOS, so
    /// observation there stays idle unless the app posts it itself.
    nonisolated public static let memoryWarningNotificationName = Notification.Name(
        "UIApplicationDidReceiveMemoryWarningNotification"
    )
}
