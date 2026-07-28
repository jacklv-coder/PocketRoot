#if canImport(UIKit) && canImport(SwiftTerm)
import Foundation
import PocketRootCore
import SwiftTerm
import UIKit

@MainActor
final class PTYTerminalBridge: NSObject, @preconcurrency TerminalViewDelegate {
    typealias SessionFactory = @Sendable () async throws -> any PocketRootSession

    private let sessionFactory: SessionFactory
    private let allowsInput: Bool
    private weak var terminalView: TerminalView?
    private var session: (any PocketRootSession)?
    private var connectionTask: Task<Void, Never>?
    private var operationTail: Task<Void, Never>?
    private var pendingSize: PocketRootTerminalSize?
    private var pendingInput = Data()

    var titleHandler: ((String) -> Void)?
    var directoryHandler: ((String?) -> Void)?
    var sessionEndHandler: ((PocketRootTerminalSessionEndReason) -> Void)?

    init(
        allowsInput: Bool,
        sessionFactory: @escaping SessionFactory
    ) {
        self.allowsInput = allowsInput
        self.sessionFactory = sessionFactory
    }

    func attach(to terminalView: TerminalView) {
        guard connectionTask == nil else {
            return
        }
        self.terminalView = terminalView
        terminalView.terminalDelegate = self
        connectionTask = Task { [weak self, sessionFactory] in
            do {
                let session = try await sessionFactory()
                guard let self, !Task.isCancelled else {
                    await session.terminate()
                    return
                }
                self.session = session
                if let pendingSize = self.pendingSize {
                    self.pendingSize = nil
                    self.enqueue { session in
                        try await session.resize(to: pendingSize)
                    }
                }
                if !self.pendingInput.isEmpty {
                    let input = self.pendingInput
                    self.pendingInput.removeAll(keepingCapacity: false)
                    self.enqueue { session in
                        try await session.write(input)
                    }
                }
                for await event in session.events {
                    guard !Task.isCancelled else {
                        break
                    }
                    self.consume(event)
                }
            } catch is CancellationError {
                return
            } catch {
                let message = error.localizedDescription
                self?.feedStatus("\r\nPocketRoot terminal error: \(message)\r\n")
                self?.sessionEndHandler?(.failed(message))
            }
        }
    }

    func detach() {
        terminalView?.terminalDelegate = nil
        terminalView = nil
        connectionTask?.cancel()
        connectionTask = nil
        operationTail?.cancel()
        operationTail = nil
        pendingSize = nil
        pendingInput.removeAll(keepingCapacity: false)
        if let session {
            Task {
                await session.terminate()
            }
        }
        session = nil
    }

    func sizeChanged(source _: TerminalView, newCols: Int, newRows: Int) {
        let size = PocketRootTerminalSize(
            rows: UInt16(clamping: newRows),
            columns: UInt16(clamping: newCols)
        )
        guard session != nil else {
            pendingSize = size
            return
        }
        enqueue { session in
            try await session.resize(to: size)
        }
    }

    func setTerminalTitle(source _: TerminalView, title: String) {
        titleHandler?(title)
    }

    func hostCurrentDirectoryUpdate(source _: TerminalView, directory: String?) {
        directoryHandler?(directory)
    }

    func send(source _: TerminalView, data: ArraySlice<UInt8>) {
        guard allowsInput else {
            return
        }
        let input = Data(data)
        guard session != nil else {
            let availableBytes = max(0, 64 * 1_024 - pendingInput.count)
            pendingInput.append(input.prefix(availableBytes))
            return
        }
        enqueue { session in
            try await session.write(input)
        }
    }

    func scrolled(source _: TerminalView, position _: Double) {}

    func requestOpenLink(
        source _: TerminalView,
        link: String,
        params _: [String: String]
    ) {
        guard let url = URL(string: link),
              let scheme = url.scheme?.lowercased(),
              ["http", "https"].contains(scheme)
        else {
            return
        }
        UIApplication.shared.open(url)
    }

    func bell(source _: TerminalView) {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    func clipboardCopy(source _: TerminalView, content: Data) {
        // OSC 52 is guest-controlled. Do not mutate the user's clipboard
        // without an explicit host-app approval flow.
    }

    func clipboardRead(source _: TerminalView) -> Data? {
        // Reading the host clipboard from a guest process is denied by default.
        nil
    }

    func iTermContent(source _: TerminalView, content _: ArraySlice<UInt8>) {}

    func rangeChanged(source _: TerminalView, startY _: Int, endY _: Int) {}

    private func consume(_ event: PocketRootSessionEvent) {
        switch event {
        case .started:
            break
        case .standardOutput(let data), .standardError(let data):
            terminalView?.feed(byteArray: Array(data)[...])
        case .exited(let exitCode):
            feedStatus("\r\n[Process exited with code \(exitCode)]\r\n")
            session = nil
            operationTail?.cancel()
            operationTail = nil
            sessionEndHandler?(.exited(exitCode))
        case .failed(let message):
            feedStatus("\r\n[PocketRoot terminal failed: \(message)]\r\n")
            session = nil
            operationTail?.cancel()
            operationTail = nil
            sessionEndHandler?(.failed(message))
        }
    }

    private func feedStatus(_ text: String) {
        terminalView?.feed(text: text)
    }

    private func enqueue(
        _ operation: @escaping @Sendable (any PocketRootSession) async throws -> Void
    ) {
        guard let session else {
            return
        }
        let previous = operationTail
        operationTail = Task { [weak self] in
            await previous?.value
            guard !Task.isCancelled else {
                return
            }
            do {
                try await operation(session)
            } catch is CancellationError {
                return
            } catch {
                self?.feedStatus(
                    "\r\n[PocketRoot terminal input failed: \(error.localizedDescription)]\r\n"
                )
            }
        }
    }
}
#endif
