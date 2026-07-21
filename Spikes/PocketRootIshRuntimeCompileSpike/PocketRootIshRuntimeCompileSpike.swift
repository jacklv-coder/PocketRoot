import Foundation
import PocketRootIshRuntimeIntegration
import UIKit

/// Forces the complete native adapter graph through a final executable link.
@main
final class PocketRootIshRuntimeCompileSpike: UIResponder, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        // The archive is intentionally absent. Referencing the complete async
        // composition forces Resources, zlib, IshEmbed, and sqlite through the
        // final app link without starting the irreversible runtime.
        Task {
            _ = try? await PocketRootIshSystemFactory.prepareSystem(
                archiveURL: URL(fileURLWithPath: "/pocketroot-compile-spike.tar.gz"),
                applicationSupportURL: URL(
                    fileURLWithPath: "/pocketroot-compile-spike-support",
                    isDirectory: true
                )
            )
        }
        return true
    }
}
