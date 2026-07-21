import Foundation

struct RootFSMetadata: Sendable, Equatable {
    let version: String
    let rootURL: URL
    let guestArchitecture: String

    init(
        version: String,
        rootURL: URL,
        guestArchitecture: String = "arm64"
    ) {
        self.version = version
        self.rootURL = rootURL
        self.guestArchitecture = guestArchitecture
    }
}
