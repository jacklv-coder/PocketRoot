import PocketRootCore

/// Creates a PocketRoot system backed by the pinned IshEmbed adapter.
public enum PocketRootIshRuntimeFactory {
    /// True only after an arm64 iOS build has selected and linked IshEmbed.
    ///
    /// This is a runtime feature probe, not an architecture-selection mechanism.
    /// A target that links the Experimental product must already exclude x86_64
    /// Simulator builds because SwiftPM cannot condition a product dependency on
    /// the destination architecture.
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
    /// - Important: Native shutdown now returns after soft-halting and joining
    ///   the embedded kernel, but the process-global iSH state still permits
    ///   only one boot/shutdown lifecycle. Create a new host process to boot
    ///   again after the returned system reaches `.terminated`.
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
