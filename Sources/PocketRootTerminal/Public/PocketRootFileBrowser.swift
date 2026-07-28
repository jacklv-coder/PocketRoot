import Foundation
import PocketRootCore

public struct PocketRootFileEntry: Sendable, Equatable, Hashable, Identifiable {
    public enum Kind: String, Sendable {
        case directory
        case file
        case symbolicLink
        case other
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

public enum PocketRootFileBrowserError: LocalizedError, Sendable, Equatable {
    case invalidPath
    case commandFailed(path: String, message: String)
    case invalidDirectoryResponse

    public var errorDescription: String? {
        switch self {
        case .invalidPath:
            return "The guest path must be an absolute path without NUL bytes."
        case .commandFailed(let path, let message):
            return "Unable to read \(path): \(message)"
        case .invalidDirectoryResponse:
            return "The guest returned an invalid directory listing."
        }
    }
}

/// A bounded, NUL-safe file browser for the PocketRoot guest filesystem.
@available(macOS 13.0, *)
public actor PocketRootFileBrowser {
    private static let maximumPreviewBytes = 512 * 1_024

    private let executor: any PocketRootTerminalCommandExecutor
    private let timeout: Duration

    public init(
        executor: any PocketRootTerminalCommandExecutor,
        timeout: Duration = .seconds(30)
    ) {
        self.executor = executor
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
        if [ ! -f \(Self.shellQuote(path)) ]; then
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
