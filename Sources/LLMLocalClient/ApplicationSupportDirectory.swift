import Foundation

/// The one way this package asks the system where Application Support is.
///
/// Three places used to ask independently and disagreed about what to do when the answer came back
/// empty: two force-unwrapped it and crashed the app, one fell back to the temporary directory and
/// carried on writing multi-gigabyte weights somewhere the system may reclaim at any moment. Both
/// are wrong in the same way — the caller never finds out. A crash blames the library for a device
/// condition it could have reported, and a silent move to a purgeable directory turns "your model
/// is downloaded" into a claim that stops being true without notice.
///
/// So the answer is neither: the lookup throws, and every caller that needs a default directory
/// throws with it.
public enum ApplicationSupportDirectory {

    /// The user's Application Support directory.
    ///
    /// - Parameter fileManager: File manager to ask. Injectable so the empty answer — which the
    ///   real system essentially never gives — can be exercised.
    /// - Returns: URL of the Application Support directory.
    /// - Throws: ``LLMLocalError/storageUnreadable(path:reason:)`` when the system returns no
    ///   directory.
    public static func url(using fileManager: FileManager = .default) throws -> URL {
        guard let url = fileManager.urls(
            for: .applicationSupportDirectory, in: .userDomainMask
        ).first else {
            throw LLMLocalError.storageUnreadable(
                path: "Application Support",
                reason: "The system returned no Application Support directory for the user domain."
            )
        }
        return url
    }
}
