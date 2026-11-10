import Foundation

/// Providers must not redirect screenshots or bearer credentials to another host.
final class ProviderTransport: NSObject, URLSessionTaskDelegate {
    private static let delegate = ProviderTransport()
    static let session = URLSession(configuration: .ephemeral, delegate: delegate, delegateQueue: nil)

    func urlSession(_ session: URLSession, task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(nil)
    }
}
