import Foundation

/// Turns an adapter source into a local file URL, downloading and caching it when needed.
///
/// The seam exists so a backend can load adapters without depending on the registry that stores
/// them: the registry conforms to this protocol and is injected into the backend, which keeps the
/// inference layer free of download, cache, and file-layout concerns.
///
/// ## Usage
///
/// ```swift
/// let resolver: any AdapterResolving = adapterRegistry
///
/// // The backend uses adapters without knowing where they come from.
/// let backend = MLXBackend(adapterResolver: resolver)
/// ```
public protocol AdapterResolving: Sendable {
    /// Produces a local URL for an adapter, fetching it first if it is not already cached.
    ///
    /// A local source is only checked for existence and handed straight back. A remote source is
    /// downloaded on a cache miss, so the first call can take as long as the transfer while later
    /// calls return immediately. It is called on the load path before any GPU work starts, which is
    /// what makes a bad adapter fail fast instead of after the base weights are resident.
    ///
    /// - Parameter source: Adapter to resolve.
    /// - Throws: ``LLMLocalError/adapterMergeFailed(reason:)`` when the adapter is missing or the
    ///   fetch fails.
    func resolve(_ source: AdapterSource) async throws -> URL
}
