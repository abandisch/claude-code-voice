import Foundation

// Not final: ReplyCollector subclasses it.
class RedirectRefuser: NSObject, URLSessionTaskDelegate {
    // A 3xx then surfaces as a failed response; the audio is never re-sent elsewhere.
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(nil)
    }
}

enum CollectedReply { case body(status: Int, data: Data), tooLarge, transport(Error) }

// Per-task delegate that stops reading past its limit. A per-task delegate does not get the session
// delegate's redirect handling, so it inherits the refusal.
final class ReplyCollector: RedirectRefuser, URLSessionDataDelegate {
    private var body = Data()
    private var tooLarge = false
    private let limit: Int
    private let done: (CollectedReply) -> Void

    init(limit: Int = maxReplyBytes, done: @escaping (CollectedReply) -> Void) {
        self.limit = limit
        self.done = done
        super.init()
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse,
                    completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
        tooLarge = !replyFits(response.expectedContentLength, limit: limit)
        completionHandler(tooLarge ? .cancel : .allow)
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        guard !tooLarge, replyFits(Int64(body.count + data.count), limit: limit) else {
            tooLarge = true
            return dataTask.cancel()
        }
        body.append(data)
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        let status = (task.response as? HTTPURLResponse)?.statusCode ?? 0
        if tooLarge { return done(.tooLarge) }
        done(error.map(CollectedReply.transport) ?? .body(status: status, data: body))
    }
}
