import Foundation

@available(macOS 13.0, *)
public protocol PocketRootSession: Sendable {
    var configuration: PocketRootSessionConfiguration { get }
    var events: AsyncStream<PocketRootSessionEvent> { get }

    func write(_ data: Data) async throws
    func resize(to size: PocketRootTerminalSize) async throws
    func sendSignal(_ signal: Int32) async throws
    func closeInput() async throws
    func terminate() async
}
