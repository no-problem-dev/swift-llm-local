import Foundation

/// Resolves an ``AdapterSource`` to a local file URL.
///
/// This protocol enables Layer 2 (MLXBackend) to resolve adapter sources
/// without directly depending on Layer 1 (AdapterManager). Layer 1 types
/// can conform to this protocol, and Layer 2 accepts it via dependency injection.
///
/// ## Usage
///
/// ```swift
/// // AdapterManager (Layer 1) conforms to this protocol
/// let resolver: any AdapterResolving = adapterManager
///
/// // MLXBackend (Layer 2) uses it without knowing about AdapterManager
/// let backend = MLXBackend(adapterResolver: resolver)
/// ```
public protocol AdapterResolving: Sendable {
    /// Resolves an adapter source to a local file URL.
    ///
    /// For local sources, this may simply validate and return the path.
    /// For remote sources (GitHub Releases, HuggingFace), this may download
    /// the adapter if it is not already cached.
    ///
    /// - Parameter source: The adapter source to resolve.
    /// - Returns: A local file URL pointing to the adapter weights.
    /// - Throws: An error if the adapter cannot be resolved (e.g., download failure,
    ///   file not found).
    func resolve(_ source: AdapterSource) async throws -> URL
}
