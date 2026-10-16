import Foundation

struct HTTPResult {
    let data: Data
    let status: Int
    var retryAfter: String? = nil
}
protocol HTTPTransport {
    func send(_ request: URLRequest) async throws -> HTTPResult
}
final class NoRedirect: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    func urlSession(_ session: URLSession, task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest,
                    completionHandler: @escaping (URLRequest?) -> Void) { completionHandler(nil) }
}
final class URLSessionTransport: HTTPTransport {
    private let session: URLSession
    init() {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 8
        configuration.timeoutIntervalForResource = 10
        configuration.urlCache = nil
        configuration.httpCookieStorage = nil
        session = URLSession(configuration: configuration, delegate: NoRedirect(), delegateQueue: nil)
    }
    deinit { session.invalidateAndCancel() }
    func send(_ request: URLRequest) async throws -> HTTPResult {
        do {
            let (data, response) = try await session.data(for: request)
            guard let response = response as? HTTPURLResponse else { throw SleepError.invalidResponse }
            return HTTPResult(data: data, status: response.statusCode, retryAfter: response.value(forHTTPHeaderField: "Retry-After"))
        } catch is CancellationError { throw CancellationError() }
        catch let error as URLError where error.code == .cancelled { throw CancellationError() }
        catch let error as SleepError { throw error }
        catch { throw SleepError.unavailable }
    }
}
