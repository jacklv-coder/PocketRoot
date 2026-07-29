import Foundation
import PocketRootCore

public struct PocketRootFileEntry: Sendable, Equatable, Hashable, Identifiable {
    public enum Kind: String, Sendable {
        case directory
        case file
        case symbolicLink
        case other

        var allowsOpening: Bool {
            self == .directory || self == .file
        }
    }

    public let name: String
    public let path: String
    public let kind: Kind
    public let size: Int64

    public var id: String {
        path
    }
}

public struct PocketRootFilePreview: Sendable, Equatable {
    public let path: String
    public let data: Data
    public let isTruncated: Bool

    public var text: String? {
        String(data: data, encoding: .utf8)
    }
}

public struct PocketRootFileExport: Sendable, Equatable {
    public let path: String
    public let suggestedFilename: String
    public let data: Data
}

public enum PocketRootFileBrowserError: LocalizedError, Sendable, Equatable {
    case invalidPath
    case invalidName
    case protectedPath
    case renameUnavailable
    case transferTooLarge(maximumBytes: Int)
    case destinationExists(String)
    case commandFailed(path: String, message: String)
    case invalidDirectoryResponse

    public var errorDescription: String? {
        switch self {
        case .invalidPath:
            return "The guest path must be an absolute path without NUL bytes."
        case .invalidName:
            return "The item name must be 1–255 UTF-8 bytes and cannot contain '/', NUL, '.' or '..'."
        case .protectedPath:
            return "The guest root directory cannot be deleted."
        case .renameUnavailable:
            return "This file browser was not configured with native rename support."
        case .transferTooLarge(let maximumBytes):
            return "File transfer is limited to \(maximumBytes) bytes."
        case .destinationExists(let path):
            return "An item already exists at \(path)."
        case .commandFailed(let path, let message):
            return "Unable to access \(path): \(message)"
        case .invalidDirectoryResponse:
            return "The guest returned an invalid directory listing."
        }
    }
}

/// A bounded, NUL-safe file browser for the PocketRoot guest filesystem.
@available(macOS 13.0, *)
public actor PocketRootFileBrowser {
    public static let maximumTransferBytes = 1 * 1_024 * 1_024
    private static let maximumPreviewBytes = 512 * 1_024

    private let executor: any PocketRootTerminalCommandExecutor
    private let renameExecutor: (any PocketRootFileRenameExecutor)?
    private let timeout: Duration

    public init(
        executor: any PocketRootTerminalCommandExecutor,
        renameExecutor: (any PocketRootFileRenameExecutor)? = nil,
        timeout: Duration = .seconds(30)
    ) {
        self.executor = executor
        self.renameExecutor = renameExecutor
        self.timeout = timeout
    }

    public init(
        system: PocketRootSystem,
        timeout: Duration = .seconds(30)
    ) {
        executor = system
        renameExecutor = system
        self.timeout = timeout
    }

    public func listDirectory(at path: String) async throws -> [PocketRootFileEntry] {
        let path = try Self.validate(path)
        let command = """
        cd -- \(Self.shellQuote(path)) || exit $?
        for item in * .[!.]* ..?*; do
          if [ ! -e "$item" ] && [ ! -L "$item" ]; then continue; fi
          if [ -L "$item" ]; then kind=l
          elif [ -d "$item" ]; then kind=d
          elif [ -f "$item" ]; then kind=f
          else kind=o
          fi
          size=$(stat -c %s -- "$item" 2>/dev/null || printf 0)
          printf '%s\\000%s\\000%s\\000' "$kind" "$size" "$item"
        done
        """
        let result = try await executor.execute(
            .init(
                command: command,
                workingDirectory: "/",
                environment: ["LC_ALL": "C"],
                timeout: timeout
            )
        )
        try Self.validate(result, path: path)
        return try Self.parseDirectory(result.standardOutput, parent: path)
            .sorted { lhs, rhs in
                if lhs.kind == .directory, rhs.kind != .directory {
                    return true
                }
                if lhs.kind != .directory, rhs.kind == .directory {
                    return false
                }
                return lhs.name.localizedStandardCompare(rhs.name)
                    == .orderedAscending
            }
    }

    public func previewFile(
        at path: String,
        maximumBytes: Int = 256 * 1_024
    ) async throws -> PocketRootFilePreview {
        let path = try Self.validate(path)
        let maximumBytes = min(
            max(1, maximumBytes),
            Self.maximumPreviewBytes
        )
        let blockSize = 4_096
        let blockCount = maximumBytes / blockSize + 1
        let command = """
        if [ -L \(Self.shellQuote(path)) ] || [ ! -f \(Self.shellQuote(path)) ]; then
          printf 'Not a regular file.\\n' >&2
          exit 64
        fi
        dd if=\(Self.shellQuote(path)) bs=\(blockSize) count=\(blockCount) 2>/dev/null
        """
        let result = try await executor.execute(
            .init(
                command: command,
                workingDirectory: "/",
                timeout: timeout
            )
        )
        try Self.validate(result, path: path)
        return PocketRootFilePreview(
            path: path,
            data: Data(result.standardOutput.prefix(maximumBytes)),
            isTruncated: result.standardOutput.count > maximumBytes
        )
    }

    /// Imports bounded bytes into a guest directory without replacing an item.
    ///
    /// Bytes are streamed through command stdin into a private staging file,
    /// then committed with the runtime's atomic no-replace rename capability.
    @discardableResult
    public func importFile(
        data: Data,
        named name: String,
        in directoryPath: String
    ) async throws -> String {
        guard data.count <= Self.maximumTransferBytes else {
            throw PocketRootFileBrowserError.transferTooLarge(
                maximumBytes: Self.maximumTransferBytes
            )
        }
        let directoryPath = try Self.validate(directoryPath)
        let targetPath = try Self.childPath(name: name, parent: directoryPath)
        guard let renameExecutor else {
            throw PocketRootFileBrowserError.renameUnavailable
        }
        let stagingPath = try Self.childPath(
            name: ".pocketroot-import-\(UUID().uuidString.lowercased()).tmp",
            parent: directoryPath
        )
        let command = """
        if [ ! -d \(Self.shellQuote(directoryPath)) ]; then
          printf 'Parent directory does not exist.\\n' >&2
          exit 66
        fi
        if [ -e \(Self.shellQuote(targetPath)) ] || [ -L \(Self.shellQuote(targetPath)) ]; then
          printf 'An item with that name already exists.\\n' >&2
          exit 73
        fi
        if [ -e \(Self.shellQuote(stagingPath)) ] || [ -L \(Self.shellQuote(stagingPath)) ]; then
          printf 'Unable to reserve staging file.\\n' >&2
          exit 73
        fi
        umask 077
        set -C
        cat > \(Self.shellQuote(stagingPath)) || exit $?
        [ "$(stat -c %s -- \(Self.shellQuote(stagingPath)))" = "\(data.count)" ] || {
          printf 'Imported byte count did not match.\\n' >&2
          exit 74
        }
        """
        do {
            let result = try await executor.execute(
                .init(
                    command: command,
                    workingDirectory: "/",
                    environment: ["LC_ALL": "C"],
                    timeout: timeout,
                    standardInput: data
                )
            )
            if result.exitCode == 73 {
                throw PocketRootFileBrowserError.destinationExists(targetPath)
            }
            try Self.validate(result, path: targetPath)
            do {
                try await renameExecutor.renameItem(
                    at: stagingPath,
                    to: targetPath,
                    timeout: timeout
                )
            } catch PocketRootError.fileDestinationExists(_) {
                throw PocketRootFileBrowserError.destinationExists(targetPath)
            }
            return targetPath
        } catch {
            await removeStagingFile(at: stagingPath)
            throw error
        }
    }

    /// Reads a regular guest file into a bounded host-side payload.
    public func exportFile(
        at path: String,
        maximumBytes: Int = PocketRootFileBrowser.maximumTransferBytes
    ) async throws -> PocketRootFileExport {
        let path = try Self.validate(path)
        let maximumBytes = min(
            max(1, maximumBytes),
            Self.maximumTransferBytes
        )
        let command = """
        if [ -L \(Self.shellQuote(path)) ] || [ ! -f \(Self.shellQuote(path)) ]; then
          printf 'Not a regular file.\\n' >&2
          exit 64
        fi
        size=$(stat -c %s -- \(Self.shellQuote(path))) || exit $?
        if [ "$size" -gt "\(maximumBytes)" ]; then
          printf 'File exceeds the transfer limit.\\n' >&2
          exit 75
        fi
        # Bound the read itself as well as the preceding size check. Another
        # guest process may grow or replace the file after stat; one extra byte
        # is sufficient for the host-side post-read limit check to reject it.
        head -c \(maximumBytes + 1) -- \(Self.shellQuote(path))
        """
        let result = try await executor.execute(
            .init(
                command: command,
                workingDirectory: "/",
                environment: ["LC_ALL": "C"],
                timeout: timeout
            )
        )
        if result.exitCode == 75 {
            throw PocketRootFileBrowserError.transferTooLarge(
                maximumBytes: maximumBytes
            )
        }
        try Self.validate(result, path: path)
        guard result.standardOutput.count <= maximumBytes else {
            throw PocketRootFileBrowserError.transferTooLarge(
                maximumBytes: maximumBytes
            )
        }
        return PocketRootFileExport(
            path: path,
            suggestedFilename: path.split(separator: "/").last.map(String.init)
                ?? "PocketRoot Export",
            data: result.standardOutput
        )
    }

    /// Creates an empty regular file without replacing an existing item.
    @discardableResult
    public func createFile(
        named name: String,
        in directoryPath: String
    ) async throws -> String {
        let directoryPath = try Self.validate(directoryPath)
        let targetPath = try Self.childPath(name: name, parent: directoryPath)
        let command = """
        if [ ! -d \(Self.shellQuote(directoryPath)) ]; then
          printf 'Parent directory does not exist.\\n' >&2
          exit 66
        fi
        if [ -e \(Self.shellQuote(targetPath)) ] || [ -L \(Self.shellQuote(targetPath)) ]; then
          printf 'An item with that name already exists.\\n' >&2
          exit 73
        fi
        set -C
        : > \(Self.shellQuote(targetPath)) || {
          printf 'Unable to create file.\\n' >&2
          exit 73
        }
        """
        try await executeMutation(command, path: targetPath)
        return targetPath
    }

    /// Creates a directory without replacing an existing item.
    @discardableResult
    public func createDirectory(
        named name: String,
        in directoryPath: String
    ) async throws -> String {
        let directoryPath = try Self.validate(directoryPath)
        let targetPath = try Self.childPath(name: name, parent: directoryPath)
        let command = """
        if [ ! -d \(Self.shellQuote(directoryPath)) ]; then
          printf 'Parent directory does not exist.\\n' >&2
          exit 66
        fi
        mkdir -- \(Self.shellQuote(targetPath))
        """
        try await executeMutation(command, path: targetPath)
        return targetPath
    }

    /// Deletes a file, symbolic link, or directory.
    ///
    /// Non-empty directories require `recursively` to be explicitly enabled.
    public func deleteItem(
        at path: String,
        recursively: Bool = false
    ) async throws {
        let path = try Self.validateMutable(path)
        let deleteDirectory = recursively
            ? "rm -rf -- \(Self.shellQuote(path))"
            : "rmdir -- \(Self.shellQuote(path))"
        let command = """
        if [ ! -e \(Self.shellQuote(path)) ] && [ ! -L \(Self.shellQuote(path)) ]; then
          printf 'The item does not exist.\\n' >&2
          exit 66
        fi
        if [ -d \(Self.shellQuote(path)) ] && [ ! -L \(Self.shellQuote(path)) ]; then
          \(deleteDirectory)
        else
          rm -f -- \(Self.shellQuote(path))
        fi
        """
        try await executeMutation(command, path: path)
    }

    /// Renames an item within its current directory without replacing a peer.
    @discardableResult
    public func renameItem(
        at path: String,
        to name: String
    ) async throws -> String {
        let sourcePath = try Self.validateMutable(path)
        let destinationPath = try Self.childPath(
            name: name,
            parent: Self.parentPath(of: sourcePath)
        )
        guard destinationPath != sourcePath else {
            return sourcePath
        }
        guard let renameExecutor else {
            throw PocketRootFileBrowserError.renameUnavailable
        }
        do {
            try await renameExecutor.renameItem(
                at: sourcePath,
                to: destinationPath,
                timeout: timeout
            )
            return destinationPath
        } catch PocketRootError.fileDestinationExists(_) {
            throw PocketRootFileBrowserError.destinationExists(destinationPath)
        }
    }

    private func executeMutation(
        _ command: String,
        path: String
    ) async throws {
        let result = try await executor.execute(
            .init(
                command: command,
                workingDirectory: "/",
                environment: ["LC_ALL": "C"],
                timeout: timeout
            )
        )
        try Self.validate(result, path: path)
    }

    private func removeStagingFile(at path: String) async {
        let executor = executor
        let request = PocketRootCommandRequest(
            command: "rm -f -- \(Self.shellQuote(path))",
            workingDirectory: "/",
            environment: ["LC_ALL": "C"],
            timeout: timeout
        )
        _ = await Task.detached {
            try? await executor.execute(request)
        }.value
    }

    private static func parseDirectory(
        _ data: Data,
        parent: String
    ) throws -> [PocketRootFileEntry] {
        guard data.last == 0 || data.isEmpty else {
            throw PocketRootFileBrowserError.invalidDirectoryResponse
        }
        let fields = data.split(separator: 0, omittingEmptySubsequences: false)
        let payload = fields.last?.isEmpty == true ? fields.dropLast() : fields[...]
        guard payload.count.isMultiple(of: 3) else {
            throw PocketRootFileBrowserError.invalidDirectoryResponse
        }

        var entries: [PocketRootFileEntry] = []
        var index = payload.startIndex
        while index < payload.endIndex {
            let kindData = payload[index]
            index = payload.index(after: index)
            let sizeData = payload[index]
            index = payload.index(after: index)
            let nameData = payload[index]
            index = payload.index(after: index)

            guard let kindCode = String(data: kindData, encoding: .utf8),
                  let sizeString = String(data: sizeData, encoding: .utf8),
                  let size = Int64(sizeString),
                  size >= 0,
                  let name = String(data: nameData, encoding: .utf8),
                  !name.isEmpty,
                  name != ".",
                  name != "..",
                  !name.contains("/")
            else {
                throw PocketRootFileBrowserError.invalidDirectoryResponse
            }
            let kind: PocketRootFileEntry.Kind
            switch kindCode {
            case "d": kind = .directory
            case "f": kind = .file
            case "l": kind = .symbolicLink
            case "o": kind = .other
            default:
                throw PocketRootFileBrowserError.invalidDirectoryResponse
            }
            let childPath = parent == "/" ? "/" + name : parent + "/" + name
            entries.append(
                PocketRootFileEntry(
                    name: name,
                    path: childPath,
                    kind: kind,
                    size: size
                )
            )
        }
        return entries
    }

    private static func validate(_ path: String) throws -> String {
        guard path.hasPrefix("/"), !path.contains("\0") else {
            throw PocketRootFileBrowserError.invalidPath
        }
        let components = path.split(separator: "/", omittingEmptySubsequences: true)
        var normalized: [Substring] = []
        for component in components {
            switch component {
            case ".":
                continue
            case "..":
                if !normalized.isEmpty {
                    normalized.removeLast()
                }
            default:
                normalized.append(component)
            }
        }
        return "/" + normalized.joined(separator: "/")
    }

    private static func validateMutable(_ path: String) throws -> String {
        let path = try validate(path)
        guard path != "/" else {
            throw PocketRootFileBrowserError.protectedPath
        }
        return path
    }

    private static func validate(name: String) throws -> String {
        guard !name.isEmpty,
              name != ".",
              name != "..",
              !name.contains("/"),
              !name.contains("\0"),
              name.lengthOfBytes(using: .utf8) <= 255
        else {
            throw PocketRootFileBrowserError.invalidName
        }
        return name
    }

    private static func childPath(
        name: String,
        parent: String
    ) throws -> String {
        let name = try validate(name: name)
        return parent == "/" ? "/" + name : parent + "/" + name
    }

    private static func parentPath(of path: String) -> String {
        guard let separator = path.lastIndex(of: "/"),
              separator != path.startIndex
        else {
            return "/"
        }
        return String(path[..<separator])
    }

    private static func validate(
        _ result: PocketRootCommandResult,
        path: String
    ) throws {
        guard !result.timedOut, result.exitCode == 0, result.signal == 0 else {
            let detail = result.timedOut
                ? "operation timed out"
                : result.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
            throw PocketRootFileBrowserError.commandFailed(
                path: path,
                message: detail.isEmpty
                    ? "guest command exited with code \(result.exitCode)"
                    : detail
            )
        }
    }

    private static func shellQuote(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\"'\"'") + "'"
    }
}
