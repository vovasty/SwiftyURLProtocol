//
//  SwiftyURLProtocol.swift
//
//  Copyright © 2017 Solomenchuk, Vlad (http://aramzamzam.net/).
//
//  Permission is hereby granted, free of charge, to any person obtaining a copy
//  of this software and associated documentation files (the "Software"), to deal
//  in the Software without restriction, including without limitation the rights
//  to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
//  copies of the Software, and to permit persons to whom the Software is
//  furnished to do so, subject to the following conditions:
//
//  The above copyright notice and this permission notice shall be included in
//  all copies or substantial portions of the Software.
//
//  THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
//  IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
//  FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
//  AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
//  LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
//  OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
//  THE SOFTWARE.
//

import Foundation

/// Types adopting the `Stopable` protocol can be used to provide objects, which activity can be stopped
public protocol Stopable {

    //Stops any activity
    func stop()
}

let swiftyURLProtocolPassHeader = "X-SwiftyURLProtocol-Pass"

public extension SwiftyURLProtocol {

    /// `Proxy` is the type used to configure external proxies.
    public enum Proxy {

        /// socks proxy.
        ///
        /// - host:                 an ip or a host of the proxy.
        /// - port:                 the port of the proxy
        /// - probe:                closure to perform test of a host.
        case socks(host: String, port: Int, probe: SwiftyURLProtocol.Probe?)
        case http(host: String, port: Int, probe: SwiftyURLProtocol.Probe?)
    }

    /// `Router` is the type used to define which proxy should be used for particular request.
    public typealias Router = (_ request: URLRequest) -> SwiftyURLProtocol.Proxy?

    /// `Probe` is the type used to test host.
    ///
    /// - host:                 an ip or a host of the proxy.
    /// - closure:              should be called when probe is complete.
    public typealias Probe = (_ host: String, _ closure: @escaping (_ error: Error?) -> Void) -> Stopable

}

open class SwiftyURLProtocol: URLProtocol {
    fileprivate var session: Foundation.URLSession?
    fileprivate var httpConnection: HTTPConnection?
    fileprivate var probe: Stopable?
    fileprivate var probeTimer: Timer?

    private static var router: Router?

    /// sets a `Router` for `URLProtocol`
    public static func setRouter(router: @escaping Router) {
        SwiftyURLProtocol.router = router
    }

    override open class func canInit(with request: URLRequest) -> Bool {
        guard URLProtocol.property(forKey: swiftyURLProtocolPassHeader, in: request) == nil else { return false }
        return router?(request) != nil
    }

    override init(request: URLRequest, cachedResponse: CachedURLResponse?, client: URLProtocolClient?) {
        guard let request = (request as NSURLRequest).mutableCopy() as? NSMutableURLRequest else {
            assert(false)
        }

        URLProtocol.setProperty(true, forKey: swiftyURLProtocolPassHeader, in: request)

        super.init(request: request as URLRequest, cachedResponse: cachedResponse, client: client)
    }

    override open class func canonicalRequest(for request: URLRequest) -> URLRequest {
        return request
    }

    override open func startLoading() {
        guard let host = request.url?.host else {
            client?.urlProtocol(self, didFailWithError: NSError(domain: NSCocoaErrorDomain, code: -1, userInfo: nil))
            return
        }

        guard let router = SwiftyURLProtocol.router else { return }
        guard let proxyType = router(request) else { return }

        let closure: (Error?) -> Void = {[weak self] (error) -> Void in
            guard let myself = self else { return }

            myself.probeTimer?.invalidate()
            myself.probeTimer = nil

            guard error == nil else {
                myself.client?.urlProtocol(myself, didFailWithError: error! )
                return
            }

            let config = URLSessionConfiguration.default

            switch proxyType {
            case .socks(let proxyHost, let proxyPort, _):
                config.connectionProxyDictionary = [
                    kCFProxyTypeKey as AnyHashable: kCFProxyTypeSOCKS,
                    kCFStreamPropertySOCKSVersion as AnyHashable: kCFStreamSocketSOCKSVersion5,
                    kCFStreamPropertySOCKSProxyHost as AnyHashable: proxyHost,
                    kCFStreamPropertySOCKSProxyPort as AnyHashable: proxyPort
                ]

                myself.httpConnection = HTTPConnection(request: myself.request, configuration: config)
                myself.httpConnection?.delegate = self
                myself.httpConnection?.start()
            case .http(let proxyHost, let proxyPort, _):
                config.connectionProxyDictionary = [
                    kCFNetworkProxiesHTTPProxy as AnyHashable: proxyHost,
                    kCFNetworkProxiesHTTPPort as AnyHashable: proxyPort,
                    kCFNetworkProxiesHTTPEnable as AnyHashable: true
                ]

                myself.session = Foundation.URLSession(configuration: config,
                                                       delegate: myself,
                                                       delegateQueue: OperationQueue.current)
                let dataTask = myself.session?.dataTask(with: myself.request)
                dataTask?.resume()
            }
        }

        switch proxyType {
        case .socks(_, _, let probe):
            if probe != nil {
                self.probe = probe?(host, closure)
            } else {
                closure(nil)
            }
        case .http(_, _, let probe):
            if probe != nil {
                self.probe = probe?(host, closure)
            } else {
                closure(nil)
            }
        }

        let timeout = request.timeoutInterval > 20 ? request.timeoutInterval - 10 : 90

        probeTimer = Timer(timeInterval: timeout, repeats: false) { [weak self] (_) in
            guard let myself = self else { return }

            let error = NSError(domain: NSCocoaErrorDomain,
                                code: -1,
                                userInfo: [NSLocalizedDescriptionKey: "probe timeout"])

            myself.client?.urlProtocol(myself,
                                       didFailWithError: error)
            myself.stopLoading()
        }
    }

    override open func stopLoading() {
        probeTimer?.invalidate()
        probe?.stop()
        session?.invalidateAndCancel()
        httpConnection?.invalidateAndStop()
        httpConnection = nil
        session = nil
        probeTimer = nil
        probe = nil
    }

    deinit {
        stopLoading()
    }
}

extension SwiftyURLProtocol: HTTPConnectionDelegate {
    func http(connection: HTTPConnection, didReceiveResponse response: URLResponse) {
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: URLCache.StoragePolicy.allowed)
    }

    func http(connection: HTTPConnection, didReceiveData data: Data) {
        client?.urlProtocol(self, didLoad: data)
    }

    func http(connection: HTTPConnection, didCompleteWithError error: Error?) {
        if let error = error {
            client?.urlProtocol(self, didFailWithError: error)
        } else {
            client?.urlProtocolDidFinishLoading(self)
        }
    }

    func http(connection: HTTPConnection,
              willPerformHTTPRedirection response: HTTPURLResponse,
              newRequest request: URLRequest) {
        guard let redirectRequest = (request as NSURLRequest).mutableCopy() as? NSMutableURLRequest else {
            assert(false)
        }
        URLProtocol.removeProperty(forKey: swiftyURLProtocolPassHeader, in: redirectRequest)
        // Tell the client about the redirect.

        client?.urlProtocol(self, wasRedirectedTo: redirectRequest as URLRequest, redirectResponse: response)

        // Stop our load.  The CFNetwork infrastructure will create a new NSURLProtocol instance to run
        // the load of the redirect.

        // The following ends up calling -URLSession:task:didCompleteWithError: with 
        // NSURLErrorDomain / NSURLErrorCancelled,
        // which specificallys traps and ignores the error.

        connection.invalidateAndStop()

        let error = NSError(domain: NSCocoaErrorDomain, code: NSUserCancelledError, userInfo: nil)
        client?.urlProtocol(self, didFailWithError: error)
    }
}

extension SwiftyURLProtocol: URLSessionDelegate {
    //NSURLSessionDelegate
    func URLSession(_ session: Foundation.URLSession,
                    task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest,
                    completionHandler: (URLRequest?) -> Void) {

        guard let redirectRequest = (request as NSURLRequest).mutableCopy() as? NSMutableURLRequest else {
            assert(false)
        }

        URLProtocol.removeProperty(forKey: swiftyURLProtocolPassHeader, in: redirectRequest)
        // Tell the client about the redirect.

        client?.urlProtocol(self, wasRedirectedTo: redirectRequest as URLRequest, redirectResponse: response)

        // Stop our load.  The CFNetwork infrastructure will create a new NSURLProtocol instance to run
        // the load of the redirect.

        // The following ends up calling -URLSession:task:didCompleteWithError: with 
        // NSURLErrorDomain / NSURLErrorCancelled,
        // which specificallys traps and ignores the error.

        task.cancel()

        let error = NSError(domain: NSCocoaErrorDomain, code: NSUserCancelledError, userInfo: nil)
        client?.urlProtocol(self, didFailWithError: error)
    }

    func URLSession(_ session: Foundation.URLSession,
                    dataTask: URLSessionDataTask,
                    didReceiveResponse response: URLResponse,
                    completionHandler: (Foundation.URLSession.ResponseDisposition) -> Void) {
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: URLCache.StoragePolicy.allowed)
        completionHandler(Foundation.URLSession.ResponseDisposition.allow)
    }
    func URLSession(_ session: Foundation.URLSession, task: URLSessionTask, didCompleteWithError error: NSError?) {
        if let error = error {
            client?.urlProtocol(self, didFailWithError: error)
        } else {
            client?.urlProtocolDidFinishLoading(self)
        }
    }

    func URLSession(_ session: Foundation.URLSession, dataTask: URLSessionDataTask, didReceiveData data: Data) {
        client?.urlProtocol(self, didLoad: data)
    }
}
