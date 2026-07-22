import Foundation

struct UnsupportedIshDriver: IshRuntimeDriver {
    func boot(_ options: IshDriverBootOptions) throws {
        throw UnsupportedIshDriverError()
    }

    func execute(_ request: IshDriverCommandRequest) throws -> IshDriverCommandResult {
        throw UnsupportedIshDriverError()
    }

    func shutdown() throws {
        throw UnsupportedIshDriverError()
    }
}

struct UnsupportedIshDriverError: LocalizedError {
    var errorDescription: String? {
        "IshEmbed is available only for arm64 iOS device and Simulator builds."
    }
}

func makeDefaultIshRuntimeDriver() -> any IshRuntimeDriver {
    #if os(iOS) && arch(arm64) && canImport(IshEmbed)
    IshEmbedDriver()
    #else
    UnsupportedIshDriver()
    #endif
}
