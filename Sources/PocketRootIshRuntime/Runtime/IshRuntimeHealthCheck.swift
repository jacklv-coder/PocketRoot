import Foundation

enum IshRuntimeHealthCheck {
    static let maximumOutputBytes = 4 * 1_024

    /// NUL separators keep guest-controlled newlines from changing the field layout.
    static let shellCommand = #"""
    set -eu
    pocketroot_arch="$(/bin/uname -m)"
    pocketroot_os_release="$(/bin/cat /etc/os-release)"
    pocketroot_cwd="$(pwd -P)"
    pocketroot_expected_cwd="$(CDPATH= cd -P "$1" && pwd -P)"
    printf '%s\0%s\0%s\0%s\0' \
        "$pocketroot_arch" "$pocketroot_os_release" \
        "$pocketroot_cwd" "$pocketroot_expected_cwd"
    """#

    static func validateConfiguration(
        _ configuration: PocketRootIshRuntimeHealthCheckConfiguration,
        workingDirectory: String
    ) throws {
        guard isValidExpectation(configuration.expectedArchitecture),
              isValidExpectation(configuration.expectedOperatingSystemID),
              configuration.expectedOperatingSystemVersionID.map(isValidExpectation) ?? true
        else {
            throw IshRuntimeHealthCheckError.invalidConfiguration(
                "expected guest identity values must be non-empty UTF-8 strings without NUL bytes"
            )
        }

        let timeout = configuration.timeout.timeInterval
        guard timeout > 0, timeout <= 60 else {
            throw IshRuntimeHealthCheckError.invalidConfiguration(
                "timeout must be greater than zero and no longer than 60 seconds"
            )
        }

        guard workingDirectory.hasPrefix("/"), !workingDirectory.utf8.contains(0) else {
            throw IshRuntimeHealthCheckError.invalidConfiguration(
                "guest working directory must be an absolute path without NUL bytes"
            )
        }
    }

    static func makeRequest(
        configuration: PocketRootIshRuntimeHealthCheckConfiguration,
        workingDirectory: String
    ) -> IshDriverCommandRequest {
        IshDriverCommandRequest(
            arguments: ["/bin/sh", "-c", shellCommand, "pocketroot-health", workingDirectory],
            workingDirectory: workingDirectory,
            environment: [
                "LC_ALL": "C",
                "PATH": "/usr/sbin:/usr/bin:/sbin:/bin",
            ],
            timeout: max(configuration.timeout.timeInterval, 0.001),
            mergeStandardError: false,
            standardInput: Data(),
            maximumStandardOutputBytes: maximumOutputBytes,
            maximumStandardErrorBytes: maximumOutputBytes
        )
    }

    static func validate(
        _ result: IshDriverCommandResult,
        configuration: PocketRootIshRuntimeHealthCheckConfiguration,
        workingDirectory: String
    ) throws {
        guard !result.timedOut else {
            throw IshRuntimeHealthCheckError.timedOut
        }
        guard result.signal == 0 else {
            throw IshRuntimeHealthCheckError.commandFailed(
                "guest health command terminated with signal \(result.signal)"
            )
        }
        guard result.exitCode == 0 else {
            throw IshRuntimeHealthCheckError.commandFailed(
                "guest health command exited with status \(result.exitCode)"
            )
        }

        let fields = result.standardOutput.split(
            separator: 0,
            omittingEmptySubsequences: false
        )
        guard fields.count == 5, fields.last?.isEmpty == true else {
            throw IshRuntimeHealthCheckError.malformedResponse
        }
        let values = try fields.dropLast().map { bytes -> String in
            guard let value = String(data: Data(bytes), encoding: .utf8) else {
                throw IshRuntimeHealthCheckError.malformedResponse
            }
            return value
        }

        guard values[0] == configuration.expectedArchitecture else {
            throw IshRuntimeHealthCheckError.identityMismatch(
                field: "architecture",
                expected: configuration.expectedArchitecture,
                actual: values[0]
            )
        }
        let operatingSystem = try parseOperatingSystemRelease(values[1])
        guard operatingSystem.id == configuration.expectedOperatingSystemID else {
            throw IshRuntimeHealthCheckError.identityMismatch(
                field: "operating system",
                expected: configuration.expectedOperatingSystemID,
                actual: operatingSystem.id ?? ""
            )
        }
        if let expectedVersion = configuration.expectedOperatingSystemVersionID,
           operatingSystem.versionID != expectedVersion {
            throw IshRuntimeHealthCheckError.identityMismatch(
                field: "operating system version",
                expected: expectedVersion,
                actual: operatingSystem.versionID ?? ""
            )
        }
        guard values[2] == values[3] else {
            throw IshRuntimeHealthCheckError.identityMismatch(
                field: "working directory",
                expected: values[3],
                actual: values[2]
            )
        }
    }

    private static func parseOperatingSystemRelease(
        _ contents: String
    ) throws -> (id: String?, versionID: String?) {
        var id: String?
        var versionID: String?

        for line in contents.split(whereSeparator: \.isNewline) {
            guard !line.isEmpty, !line.hasPrefix("#"),
                  let separator = line.firstIndex(of: "=")
            else {
                continue
            }

            let key = line[..<separator]
            guard key == "ID" || key == "VERSION_ID" else {
                continue
            }
            let rawValue = line[line.index(after: separator)...]
            let value = try parseOperatingSystemReleaseValue(rawValue)

            if key == "ID" {
                guard id == nil else {
                    throw IshRuntimeHealthCheckError.malformedResponse
                }
                id = value
            } else {
                guard versionID == nil else {
                    throw IshRuntimeHealthCheckError.malformedResponse
                }
                versionID = value
            }
        }

        return (id, versionID)
    }

    private static func parseOperatingSystemReleaseValue(
        _ rawValue: Substring
    ) throws -> String {
        guard let first = rawValue.first else {
            return ""
        }
        guard first == "\"" || first == "'" else {
            return String(rawValue)
        }
        guard rawValue.count >= 2, rawValue.last == first else {
            throw IshRuntimeHealthCheckError.malformedResponse
        }

        let contents = rawValue.dropFirst().dropLast()
        var result = ""
        var escaped = false
        for character in contents {
            if escaped {
                guard character == "\\" || character == "\"" || character == "'"
                    || character == "$" || character == "`"
                else {
                    throw IshRuntimeHealthCheckError.malformedResponse
                }
                result.append(character)
                escaped = false
            } else if character == "\\" {
                escaped = true
            } else {
                result.append(character)
            }
        }
        guard !escaped else {
            throw IshRuntimeHealthCheckError.malformedResponse
        }
        return result
    }

    private static func isValidExpectation(_ value: String) -> Bool {
        !value.isEmpty && !value.utf8.contains(0)
    }
}

enum IshRuntimeHealthCheckError: LocalizedError, Equatable {
    case invalidConfiguration(String)
    case timedOut
    case commandFailed(String)
    case malformedResponse
    case identityMismatch(field: String, expected: String, actual: String)

    var errorDescription: String? {
        switch self {
        case .invalidConfiguration(let reason):
            return "Invalid post-boot health-check configuration: \(reason)."
        case .timedOut:
            return "Post-boot guest health check timed out."
        case .commandFailed(let reason):
            return "Post-boot guest health check failed: \(reason)."
        case .malformedResponse:
            return "Post-boot guest health check returned a malformed identity response."
        case .identityMismatch(let field, let expected, let actual):
            return "Post-boot guest \(field) mismatch: expected "
                + "\(String(reflecting: expected)), found \(String(reflecting: actual))."
        }
    }
}
