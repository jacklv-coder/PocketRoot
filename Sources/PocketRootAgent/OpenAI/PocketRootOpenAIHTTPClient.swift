import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

struct PocketRootOpenAIHTTPResult: @unchecked Sendable {
    let data: Data
    let response: HTTPURLResponse
}

protocol PocketRootOpenAIHTTPClient: Sendable {
    func send(
        _ request: URLRequest,
        maximumResponseBodyBytes: Int
    ) async throws -> PocketRootOpenAIHTTPResult
}

struct PocketRootURLSessionOpenAIHTTPClient: Sendable {
    let session: URLSession

    init(session: URLSession) {
        self.session = session
    }

    init() {
        session = PocketRootOpenAIURLSession.shared
    }
}

extension PocketRootURLSessionOpenAIHTTPClient: PocketRootOpenAIHTTPClient {
    func send(
        _ request: URLRequest,
        maximumResponseBodyBytes: Int
    ) async throws -> PocketRootOpenAIHTTPResult {
        let (bytes, response) = try await session.bytes(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw PocketRootOpenAIResponsesError.invalidHTTPResponse
        }

        let expectedLength = httpResponse.expectedContentLength
        if expectedLength > maximumResponseBodyBytes {
            throw PocketRootOpenAIResponsesError.responseBodyLimitExceeded(
                maximumResponseBodyBytes
            )
        }

        var data = Data()
        if expectedLength > 0 {
            data.reserveCapacity(
                min(Int(expectedLength), maximumResponseBodyBytes)
            )
        }
        for try await byte in bytes {
            guard data.count < maximumResponseBodyBytes else {
                throw PocketRootOpenAIResponsesError.responseBodyLimitExceeded(
                    maximumResponseBodyBytes
                )
            }
            data.append(byte)
        }

        return PocketRootOpenAIHTTPResult(
            data: data,
            response: httpResponse
        )
    }
}

private enum PocketRootOpenAIURLSession {
    static let shared: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpCookieAcceptPolicy = .never
        configuration.httpShouldSetCookies = false
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.urlCache = nil
        return URLSession(
            configuration: configuration,
            delegate: PocketRootNoRedirectDelegate(),
            delegateQueue: nil
        )
    }()
}

private final class PocketRootNoRedirectDelegate:
    NSObject,
    URLSessionTaskDelegate,
    @unchecked Sendable
{
    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping (URLRequest?) -> Void
    ) {
        completionHandler(nil)
    }
}
