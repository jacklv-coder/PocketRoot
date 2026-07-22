import Foundation
import PocketRootCore
import PocketRootIshRuntime
import PocketRootResources

/// The verified RootFS installation and the system configured to boot it.
public struct PocketRootPreparedIshSystem: Sendable {
    /// The Experimental native system. Its pinned iSH shutdown path exits the
    /// entire host App process and does not return to Swift.
    public let system: PocketRootSystem
    public let installation: PocketRootRootFSInstallation

    public init(
        system: PocketRootSystem,
        installation: PocketRootRootFSInstallation
    ) {
        self.system = system
        self.installation = installation
    }
}

/// Composes the opt-in RootFS installer and Experimental IshEmbed adapter.
public enum PocketRootIshSystemFactory {
    /// Verifies and materializes a caller-supplied archive, then creates a
    /// system configured for that fakefs. This method never downloads assets
    /// and does not boot the process-global runtime. The returned system applies
    /// the configured guest identity gate when its `boot()` method is called.
    /// A nil health check pins v0.3.3 only for the exact built-in manifest and
    /// otherwise uses the version-agnostic Alpine ARM64 gate.
    @available(macOS 13.0, *)
    public static func prepareSystem(
        archiveURL: URL,
        applicationSupportURL: URL,
        manifest: PocketRootRootFSArtifactManifest = .ishEmbedV0_3_3,
        systemConfiguration: PocketRootConfiguration? = nil,
        workDirectory: String = "/",
        supervisorGuestPath: String? = nil,
        kernelLogFileDescriptor: Int32 = -1,
        maximumStandardOutputBytes: Int = 8 * 1_024 * 1_024,
        maximumStandardErrorBytes: Int = 4 * 1_024 * 1_024,
        healthCheck: PocketRootIshRuntimeHealthCheckConfiguration? = nil
    ) async throws -> PocketRootPreparedIshSystem {
        let installer = PocketRootRootFSInstaller(
            baseDirectoryURL: applicationSupportURL,
            manifest: manifest
        )
        let installation = try await installer.prepareArchive(at: archiveURL)
        let requestedConfiguration = systemConfiguration ?? PocketRootConfiguration()
        let configuration = PocketRootConfiguration(
            rootFSVersion: manifest.version,
            defaultWorkingDirectory: requestedConfiguration.defaultWorkingDirectory,
            commandTimeout: requestedConfiguration.commandTimeout
        )
        let resolvedHealthCheck = healthCheck ?? defaultHealthCheck(for: manifest)
        let system = PocketRootIshRuntimeFactory.makeSystem(
            configuration: configuration,
            runtimeConfiguration: PocketRootIshRuntimeConfiguration(
                rootFSURL: installation.rootFSURL,
                workDirectory: workDirectory,
                supervisorGuestPath: supervisorGuestPath,
                kernelLogFileDescriptor: kernelLogFileDescriptor,
                maximumStandardOutputBytes: maximumStandardOutputBytes,
                maximumStandardErrorBytes: maximumStandardErrorBytes,
                healthCheck: resolvedHealthCheck
            )
        )

        return PocketRootPreparedIshSystem(
            system: system,
            installation: installation
        )
    }

    static func defaultHealthCheck(
        for manifest: PocketRootRootFSArtifactManifest
    ) -> PocketRootIshRuntimeHealthCheckConfiguration {
        manifest == .ishEmbedV0_3_3 ? .ishEmbedV0_3_3 : .alpineARM64
    }
}
