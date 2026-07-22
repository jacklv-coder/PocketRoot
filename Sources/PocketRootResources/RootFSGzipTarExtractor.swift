import CPocketRootArchiveSupport
import Foundation

public enum PocketRootArchiveExtractionError: Error, Sendable, Equatable {
    case sourceUnavailable(String)
    case destinationAlreadyExists(String)
    case gzipDecompressionFailed(String)
    case truncatedArchive
    case invalidHeader(String)
    case unsafePath(String)
    case unsupportedEntryType(path: String, type: UInt8)
    case entryLimitExceeded(Int)
    case expandedSizeLimitExceeded(UInt64)
    case fileSystemFailure(String)
}

extension PocketRootArchiveExtractionError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .sourceUnavailable(let path):
            return "The gzip archive is not a readable local file: \(path)"
        case .destinationAlreadyExists(let path):
            return "The extraction destination already exists: \(path)"
        case .gzipDecompressionFailed(let message):
            return "Unable to decompress the RootFS gzip stream: \(message)"
        case .truncatedArchive:
            return "The RootFS tar archive is truncated."
        case .invalidHeader(let message):
            return "The RootFS tar archive has an invalid header: \(message)"
        case .unsafePath(let path):
            return "The RootFS tar archive contains an unsafe path: \(path)"
        case .unsupportedEntryType(let path, let type):
            return "The RootFS tar entry \(path) has unsupported type \(type)."
        case .entryLimitExceeded(let limit):
            return "The RootFS tar archive exceeds the \(limit)-entry limit."
        case .expandedSizeLimitExceeded(let limit):
            return "The RootFS archive exceeds the \(limit)-byte expanded-size limit."
        case .fileSystemFailure(let message):
            return "RootFS extraction failed while writing files: \(message)"
        }
    }
}

/// Extracts a gzip-compressed POSIX ustar archive without invoking host tools.
///
/// The extractor intentionally accepts only directories and regular files.
/// iSH fakefs represents guest links and device metadata in `meta.db`, so the
/// audited RootFS does not require host symlink or device-node extraction.
public struct PocketRootGzipTarExtractor: Sendable, Equatable {
    public let maximumExpandedArchiveByteCount: UInt64
    public let maximumEntryCount: Int

    public init(
        maximumExpandedArchiveByteCount: UInt64 = 256 * 1_024 * 1_024,
        maximumEntryCount: Int = 100_000
    ) {
        self.maximumExpandedArchiveByteCount = maximumExpandedArchiveByteCount
        self.maximumEntryCount = maximumEntryCount
    }

    public func extract(archiveURL: URL, to destinationURL: URL) throws {
        let fileManager = FileManager.default
        var sourceIsDirectory: ObjCBool = false
        guard archiveURL.isFileURL,
              fileManager.fileExists(
                atPath: archiveURL.path,
                isDirectory: &sourceIsDirectory
              ),
              !sourceIsDirectory.boolValue
        else {
            throw PocketRootArchiveExtractionError.sourceUnavailable(archiveURL.path)
        }
        let sourceValues = try archiveURL.resourceValues(
            forKeys: [.isRegularFileKey, .isSymbolicLinkKey]
        )
        guard sourceValues.isRegularFile == true,
              sourceValues.isSymbolicLink != true
        else {
            throw PocketRootArchiveExtractionError.sourceUnavailable(archiveURL.path)
        }

        guard destinationURL.isFileURL,
              !fileManager.fileExists(atPath: destinationURL.path)
        else {
            throw PocketRootArchiveExtractionError.destinationAlreadyExists(
                destinationURL.path
            )
        }

        let parentURL = destinationURL.deletingLastPathComponent()
        try fileManager.createDirectory(at: parentURL, withIntermediateDirectories: true)

        let tarURL = parentURL.appendingPathComponent(
            ".pocketroot-\(UUID().uuidString).tar",
            isDirectory: false
        )
        defer {
            try? fileManager.removeItem(at: tarURL)
        }

        try decompressGzip(archiveURL: archiveURL, tarURL: tarURL)

        var completed = false
        defer {
            if !completed {
                try? fileManager.removeItem(at: destinationURL)
            }
        }

        do {
            try fileManager.createDirectory(
                at: destinationURL,
                withIntermediateDirectories: false
            )
            try extractTar(tarURL: tarURL, destinationURL: destinationURL)
            completed = true
        } catch let error as PocketRootArchiveExtractionError {
            throw error
        } catch {
            throw PocketRootArchiveExtractionError.fileSystemFailure(
                error.localizedDescription
            )
        }
    }

    private func decompressGzip(archiveURL: URL, tarURL: URL) throws {
        var errorBuffer = [CChar](repeating: 0, count: 512)
        let status: Int32 = errorBuffer.withUnsafeMutableBufferPointer { errorPointer in
            archiveURL.withUnsafeFileSystemRepresentation { sourcePath in
                tarURL.withUnsafeFileSystemRepresentation { destinationPath in
                    guard let sourcePath, let destinationPath else {
                        return 1
                    }
                    return pocketroot_gzip_decompress(
                        sourcePath,
                        destinationPath,
                        maximumExpandedArchiveByteCount,
                        errorPointer.baseAddress,
                        errorPointer.count
                    )
                }
            }
        }

        guard status == 0 else {
            let message = errorBuffer.withUnsafeBufferPointer { pointer in
                guard let baseAddress = pointer.baseAddress, baseAddress.pointee != 0 else {
                    return "Unknown gzip error (status \(status))."
                }
                return String(cString: baseAddress)
            }
            if message.contains("exceeds the configured size limit") {
                throw PocketRootArchiveExtractionError.expandedSizeLimitExceeded(
                    maximumExpandedArchiveByteCount
                )
            }
            throw PocketRootArchiveExtractionError.gzipDecompressionFailed(message)
        }
    }

    private func extractTar(tarURL: URL, destinationURL: URL) throws {
        let input: FileHandle
        do {
            input = try FileHandle(forReadingFrom: tarURL)
        } catch {
            throw PocketRootArchiveExtractionError.fileSystemFailure(
                error.localizedDescription
            )
        }
        defer {
            try? input.close()
        }

        var zeroBlockCount = 0
        var entryCount = 0
        var expandedFileByteCount: UInt64 = 0
        var directoryModes: [(URL, Int)] = []
        var materializedPaths = Set<String>()
        var materializedDirectoryIdentities = Set<FileIdentity>()

        while true {
            guard let header = try readBlockAllowingEndOfFile(from: input) else {
                throw PocketRootArchiveExtractionError.truncatedArchive
            }

            if header.allSatisfy({ $0 == 0 }) {
                zeroBlockCount += 1
                if zeroBlockCount == 2 {
                    break
                }
                continue
            }
            zeroBlockCount = 0

            entryCount += 1
            guard entryCount <= maximumEntryCount else {
                throw PocketRootArchiveExtractionError.entryLimitExceeded(
                    maximumEntryCount
                )
            }

            let entry = try parseHeader(header)
            guard entry.size <= maximumExpandedArchiveByteCount,
                  expandedFileByteCount <= maximumExpandedArchiveByteCount - entry.size
            else {
                throw PocketRootArchiveExtractionError.expandedSizeLimitExceeded(
                    maximumExpandedArchiveByteCount
                )
            }
            expandedFileByteCount += entry.size

            let entryURL = try safeDestinationURL(
                for: entry.path,
                under: destinationURL
            )
            if shouldSkipAppleMetadata(entry.path) {
                try discardPayload(size: entry.size, from: input)
                try discardPadding(afterPayloadSize: entry.size, from: input)
                continue
            }
            if entry.type != .extendedHeader,
               !materializedPaths.insert(entryURL.path).inserted
            {
                throw PocketRootArchiveExtractionError.fileSystemFailure(
                    "A duplicate entry exists at \(entryURL.path)."
                )
            }
            switch entry.type {
            case .extendedHeader:
                // The audited archive uses per-entry PAX records only for
                // timestamps and macOS provenance xattrs. Guest filesystem
                // metadata lives in fakefs meta.db, so these host attributes
                // are intentionally not restored.
                try discardPayload(size: entry.size, from: input)

            case .directory:
                var isDirectory: ObjCBool = false
                if FileManager.default.fileExists(
                    atPath: entryURL.path,
                    isDirectory: &isDirectory
                ) {
                    guard isDirectory.boolValue else {
                        throw PocketRootArchiveExtractionError.fileSystemFailure(
                            "A non-directory already exists at \(entryURL.path)."
                        )
                    }
                } else {
                    try FileManager.default.createDirectory(
                        at: entryURL,
                        withIntermediateDirectories: true
                    )
                }
                let identity = try fileIdentity(at: entryURL)
                guard materializedDirectoryIdentities.insert(identity).inserted else {
                    throw PocketRootArchiveExtractionError.fileSystemFailure(
                        "A duplicate directory target exists at \(entryURL.path)."
                    )
                }
                directoryModes.append((entryURL, entry.mode))
                try discardPayload(size: entry.size, from: input)

            case .regularFile:
                let parentURL = entryURL.deletingLastPathComponent()
                try FileManager.default.createDirectory(
                    at: parentURL,
                    withIntermediateDirectories: true
                )
                guard !FileManager.default.fileExists(atPath: entryURL.path),
                      FileManager.default.createFile(
                        atPath: entryURL.path,
                        contents: nil
                      )
                else {
                    throw PocketRootArchiveExtractionError.fileSystemFailure(
                        "A duplicate entry exists at \(entryURL.path)."
                    )
                }
                try writePayload(size: entry.size, from: input, to: entryURL)
                try setPOSIXMode(entry.mode, at: entryURL)
            }

            try discardPadding(afterPayloadSize: entry.size, from: input)
        }

        for (directoryURL, mode) in directoryModes.reversed() {
            try setPOSIXMode(mode, at: directoryURL)
        }
    }

    private func parseHeader(_ header: Data) throws -> TarEntry {
        guard header.count == 512 else {
            throw PocketRootArchiveExtractionError.truncatedArchive
        }
        let bytes = [UInt8](header)

        let storedChecksum = try parseOctal(
            bytes[148..<156],
            fieldName: "checksum"
        )
        let computedChecksum = bytes.enumerated().reduce(UInt64(0)) { result, element in
            let (index, byte) = element
            return result + UInt64((148..<156).contains(index) ? 32 : byte)
        }
        guard storedChecksum == computedChecksum else {
            throw PocketRootArchiveExtractionError.invalidHeader(
                "checksum mismatch"
            )
        }

        let magic = try parseString(bytes[257..<263], fieldName: "magic")
        guard magic == "ustar" else {
            throw PocketRootArchiveExtractionError.invalidHeader(
                "unsupported archive format"
            )
        }

        let name = try parseString(bytes[0..<100], fieldName: "name")
        let prefix = try parseString(bytes[345..<500], fieldName: "prefix")
        let path = prefix.isEmpty ? name : "\(prefix)/\(name)"
        guard !path.isEmpty else {
            throw PocketRootArchiveExtractionError.invalidHeader("empty entry path")
        }

        let size = try parseOctal(bytes[124..<136], fieldName: "size")
        let modeValue = try parseOctal(bytes[100..<108], fieldName: "mode")
        guard modeValue <= UInt64(Int.max) else {
            throw PocketRootArchiveExtractionError.invalidHeader("mode overflow")
        }

        let typeByte = bytes[156]
        let type: TarEntry.EntryType
        switch typeByte {
        case 0, 48:
            type = .regularFile
        case 53:
            type = .directory
        case 103, 120:
            type = .extendedHeader
        default:
            throw PocketRootArchiveExtractionError.unsupportedEntryType(
                path: path,
                type: typeByte
            )
        }

        return TarEntry(
            path: path,
            type: type,
            size: size,
            mode: Int(modeValue) & 0o777
        )
    }

    private func parseString(
        _ bytes: ArraySlice<UInt8>,
        fieldName: String
    ) throws -> String {
        let content = bytes.prefix { $0 != 0 }
        guard let value = String(bytes: content, encoding: .utf8) else {
            throw PocketRootArchiveExtractionError.invalidHeader(
                "\(fieldName) is not valid UTF-8"
            )
        }
        return value
    }

    private func parseOctal(
        _ bytes: ArraySlice<UInt8>,
        fieldName: String
    ) throws -> UInt64 {
        guard bytes.first.map({ $0 & 0x80 == 0 }) ?? true else {
            throw PocketRootArchiveExtractionError.invalidHeader(
                "base-256 \(fieldName) is unsupported"
            )
        }

        let digits = bytes.drop(while: { $0 == 0 || $0 == 32 })
            .prefix(while: { $0 != 0 && $0 != 32 })
        if digits.isEmpty {
            return 0
        }

        var result: UInt64 = 0
        for byte in digits {
            guard (48...55).contains(byte),
                  result <= (UInt64.max - UInt64(byte - 48)) / 8
            else {
                throw PocketRootArchiveExtractionError.invalidHeader(
                    "invalid \(fieldName)"
                )
            }
            result = result * 8 + UInt64(byte - 48)
        }
        return result
    }

    private func safeDestinationURL(
        for archivePath: String,
        under destinationURL: URL
    ) throws -> URL {
        guard !archivePath.hasPrefix("/") else {
            throw PocketRootArchiveExtractionError.unsafePath(archivePath)
        }

        let components = archivePath.split(
            separator: "/",
            omittingEmptySubsequences: true
        )
        guard !components.isEmpty,
              components.allSatisfy({ $0 != "." && $0 != ".." })
        else {
            throw PocketRootArchiveExtractionError.unsafePath(archivePath)
        }

        let candidateURL = components.reduce(destinationURL) { partialURL, component in
            partialURL.appendingPathComponent(String(component), isDirectory: false)
        }.standardizedFileURL
        let rootPath = destinationURL.standardizedFileURL.path
        let candidatePath = candidateURL.path
        guard candidatePath.hasPrefix(rootPath + "/") else {
            throw PocketRootArchiveExtractionError.unsafePath(archivePath)
        }
        return candidateURL
    }

    private func shouldSkipAppleMetadata(_ path: String) -> Bool {
        let components = path.split(separator: "/", omittingEmptySubsequences: true)
        return components.contains(where: { $0.hasPrefix("._") })
            || components.first == "__MACOSX"
    }

    private func writePayload(
        size: UInt64,
        from input: FileHandle,
        to outputURL: URL
    ) throws {
        let output = try FileHandle(forWritingTo: outputURL)
        defer {
            try? output.close()
        }

        var remaining = size
        while remaining > 0 {
            let count = Int(min(remaining, 1_048_576))
            let chunk = try readExactly(count, from: input)
            try output.write(contentsOf: chunk)
            remaining -= UInt64(chunk.count)
        }
    }

    private func discardPayload(size: UInt64, from input: FileHandle) throws {
        var remaining = size
        while remaining > 0 {
            let count = Int(min(remaining, 1_048_576))
            let chunk = try readExactly(count, from: input)
            remaining -= UInt64(chunk.count)
        }
    }

    private func discardPadding(
        afterPayloadSize size: UInt64,
        from input: FileHandle
    ) throws {
        let remainder = size % 512
        guard remainder != 0 else {
            return
        }
        _ = try readExactly(Int(512 - remainder), from: input)
    }

    private func readBlockAllowingEndOfFile(from input: FileHandle) throws -> Data? {
        let firstChunk = try input.read(upToCount: 512) ?? Data()
        if firstChunk.isEmpty {
            return nil
        }
        if firstChunk.count == 512 {
            return firstChunk
        }

        var block = firstChunk
        while block.count < 512 {
            let chunk = try input.read(upToCount: 512 - block.count) ?? Data()
            guard !chunk.isEmpty else {
                throw PocketRootArchiveExtractionError.truncatedArchive
            }
            block.append(chunk)
        }
        return block
    }

    private func readExactly(_ count: Int, from input: FileHandle) throws -> Data {
        var data = Data()
        data.reserveCapacity(count)
        while data.count < count {
            let chunk = try input.read(upToCount: count - data.count) ?? Data()
            guard !chunk.isEmpty else {
                throw PocketRootArchiveExtractionError.truncatedArchive
            }
            data.append(chunk)
        }
        return data
    }

    private func setPOSIXMode(_ mode: Int, at url: URL) throws {
        do {
            try FileManager.default.setAttributes(
                [.posixPermissions: NSNumber(value: mode)],
                ofItemAtPath: url.path
            )
        } catch {
            throw PocketRootArchiveExtractionError.fileSystemFailure(
                error.localizedDescription
            )
        }
    }

    private func fileIdentity(at url: URL) throws -> FileIdentity {
        do {
            let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
            guard let device = attributes[.systemNumber] as? NSNumber,
                  let inode = attributes[.systemFileNumber] as? NSNumber
            else {
                throw PocketRootArchiveExtractionError.fileSystemFailure(
                    "Unable to identify the directory at \(url.path)."
                )
            }
            return FileIdentity(
                device: device.uint64Value,
                inode: inode.uint64Value
            )
        } catch let error as PocketRootArchiveExtractionError {
            throw error
        } catch {
            throw PocketRootArchiveExtractionError.fileSystemFailure(
                error.localizedDescription
            )
        }
    }
}

private struct FileIdentity: Hashable {
    let device: UInt64
    let inode: UInt64
}

private struct TarEntry {
    enum EntryType {
        case regularFile
        case directory
        case extendedHeader
    }

    let path: String
    let type: EntryType
    let size: UInt64
    let mode: Int
}
