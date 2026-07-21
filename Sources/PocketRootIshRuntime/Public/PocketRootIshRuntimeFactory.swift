import PocketRootCore

/// Creates a PocketRoot system backed by the pinned IshEmbed adapter.
public enum PocketRootIshRuntimeFactory {
    /// True only when the current build can link the arm64 iOS IshEmbed binary.
    public static var isAvailable: Bool {
        #if os(iOS) && arch(arm64) && canImport(IshEmbed)
        true
        #else
        false
        #endif
    }

    @available(macOS 13.0, *)
    /// Creates the Experimental process-global native runtime.
    ///
    /// - Important: At the pinned upstream revision, calling `shutdown()` on
    ///   the returned system deliberately terminates the entire host App with
    ///   `_exit(0)`. Native shutdown does not return to Swift. This product
    ///   must remain opt-in until the host-process termination contract is
    ///   accepted or replaced by a rebuilt upstream artifact.
    public static func makeSystem(
        configuration: PocketRootConfiguration = PocketRootConfiguration(),
        runtimeConfiguration: PocketRootIshRuntimeConfiguration
    ) -> PocketRootSystem {
        PocketRootSystem(
            configuration: configuration,
            runtime: IshLinuxRuntime(configuration: runtimeConfiguration)
        )
    }
}
