#if canImport(UIKit) && canImport(SwiftTerm)
import Foundation
import PocketRootCore
import SwiftTerm
import UIKit

@MainActor
final class PTYTerminalBridge: NSObject, @preconcurrency TerminalViewDelegate {
    typealias SessionFactory = @Sendable () async throws -> any PocketRootSession

    private static let maximumAccessibilitySnapshotBytes = 16 * 1_024

    private let sessionFactory: SessionFactory
    private let allowsInput: Bool
    private weak var terminalView: TerminalView?
    private var session: (any PocketRootSession)?
    private var connectionTask: Task<Void, Never>?
    private var operationTail: Task<Void, Never>?
    private var detachTask: Task<Void, Never>?
    private var accessibilityUpdateTask: Task<Void, Never>?
    private var accessibilityOutput = Data()
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
        guard connectionTask == nil, detachTask == nil else {
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

    func detach(completion: (@MainActor () -> Void)? = nil) {
        terminalView?.terminalDelegate = nil
        terminalView = nil
        accessibilityUpdateTask?.cancel()
        accessibilityUpdateTask = nil
        if let detachTask {
            Task {
                await detachTask.value
                completion?()
            }
            return
        }
        let connectingTask = connectionTask
        connectingTask?.cancel()
        connectionTask = nil
        let queuedOperation = operationTail
        queuedOperation?.cancel()
        operationTail = nil
        pendingSize = nil
        pendingInput.removeAll(keepingCapacity: false)
        let activeSession = session
        session = nil
        guard connectingTask != nil
                || queuedOperation != nil
                || activeSession != nil
        else {
            completion?()
            return
        }
        let task = Task { [weak self] in
            if let activeSession {
                await activeSession.terminate()
            }
            await connectingTask?.value
            await queuedOperation?.value
            self?.detachTask = nil
            completion?()
        }
        detachTask = task
    }

    func sizeChanged(source _: TerminalView, newCols: Int, newRows: Int) {
        let size = PocketRootTerminalSize(
            rows: UInt16(clamping: newRows),
            columns: UInt16(clamping: newCols)
        )
        updateAccessibilitySnapshot()
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
            appendAccessibilityOutput(data)
            scheduleAccessibilitySnapshot()
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
        appendAccessibilityOutput(Data(text.utf8))
        updateAccessibilitySnapshot()
    }

    private func appendAccessibilityOutput(_ data: Data) {
        let limit = Self.maximumAccessibilitySnapshotBytes
        if data.count >= limit {
            accessibilityOutput = Data(data.suffix(limit))
            return
        }
        let overflow = accessibilityOutput.count + data.count - limit
        if overflow > 0 {
            accessibilityOutput.removeFirst(overflow)
        }
        accessibilityOutput.append(data)
    }

    private func scheduleAccessibilitySnapshot() {
        guard accessibilityUpdateTask == nil else {
            return
        }
        accessibilityUpdateTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 100_000_000)
            guard !Task.isCancelled, let self else {
                return
            }
            accessibilityUpdateTask = nil
            updateAccessibilitySnapshot()
        }
    }

    private func updateAccessibilitySnapshot() {
        guard let terminalView else {
            return
        }
        let terminal = terminalView.getTerminal()
        let dimensions = terminal.getDims()
        let transcript = String(decoding: accessibilityOutput, as: UTF8.self)
        terminalView.accessibilityValue =
            "rows=\(dimensions.rows) columns=\(dimensions.cols)\n\(transcript)"
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
