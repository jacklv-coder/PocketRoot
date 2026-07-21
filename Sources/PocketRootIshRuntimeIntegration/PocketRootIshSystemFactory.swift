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
    /// and does not boot the irreversible process-global runtime.
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
        maximumStandardErrorBytes: Int = 4 * 1_024 * 1_024
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
        let system = PocketRootIshRuntimeFactory.makeSystem(
            configuration: configuration,
            runtimeConfiguration: PocketRootIshRuntimeConfiguration(
                rootFSURL: installation.rootFSURL,
                workDirectory: workDirectory,
                supervisorGuestPath: supervisorGuestPath,
                kernelLogFileDescriptor: kernelLogFileDescriptor,
                maximumStandardOutputBytes: maximumStandardOutputBytes,
                maximumStandardErrorBytes: maximumStandardErrorBytes
            )
        )

        return PocketRootPreparedIshSystem(
            system: system,
            installation: installation
        )
    }
}
