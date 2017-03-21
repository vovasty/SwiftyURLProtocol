//
//  ProxyURLProtocol.swift
//  SwiftyI2P
//
//  Created by Solomenchuk, Vlad on 12/19/15.
//  Copyright © 2015 Aramzamzam LLC. All rights reserved.
//

import Foundation

public protocol Stopable {
    func stop()
}

let ProxyURLProtocolPassHeader = "X-ProxyURLProtocol-Pass"

public extension ProxyURLProtocol {
    public enum Proxy {
        case socks(host: String, port: Int, resolver: ProxyURLProtocol.Resolver)
        case http(host: String, port: Int, resolver: ProxyURLProtocol.Resolver)
    }
    
    public typealias Router = (_ request: URLRequest) -> ProxyURLProtocol.Proxy?
    
    public typealias Resolver = (_ host: String, _ timeout: TimeInterval, _ closure: @escaping (_ error: Error?) -> Void) -> Stopable?

}

open class ProxyURLProtocol: URLProtocol {
    fileprivate var session: Foundation.URLSession?
    fileprivate var httpConnection: HTTPConnection?
    fileprivate var resolver: Stopable?

    private static var router: Router?
    
    public static func setRouter(router: @escaping Router) {
        ProxyURLProtocol.router = router
    }

    override open class func canInit(with request: URLRequest) -> Bool {
        guard URLProtocol.property(forKey: ProxyURLProtocolPassHeader, in: request) == nil else { return false }
        return router?(request) != nil
    }

    override init(request: URLRequest, cachedResponse: CachedURLResponse?, client: URLProtocolClient?) {
        let request = (request as NSURLRequest).mutableCopy() as! NSMutableURLRequest
        URLProtocol.setProperty(true, forKey: ProxyURLProtocolPassHeader, in: request)

        super.init(request: request as URLRequest, cachedResponse: cachedResponse, client: client)
    }

    override open class func canonicalRequest(for request: URLRequest) -> URLRequest {
        return request
    }

    override open func startLoading() {
        guard let host = request.url?.host else {
            client?.urlProtocol(self, didFailWithError: NSError(domain: NSCocoaErrorDomain, code: -1, userInfo: nil) )
            return
        }
        
        guard let router = ProxyURLProtocol.router else { return }
        guard let proxyType = router(request) else { return }

        let handler: (Error?) -> Void = {[weak self] (error) -> Void in
            guard let myself = self else { return }

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

        let timeout = request.timeoutInterval > 20 ? request.timeoutInterval - 10 : 90
        
        switch proxyType {
        case .socks(_, _, let resolver):
            self.resolver = resolver(host, timeout, handler)
        case .http(_, _, let resolver):
            self.resolver = resolver(host, timeout, handler)
        }
    }

    override open func stopLoading() {
        resolver?.stop()
        session?.invalidateAndCancel()
        httpConnection?.invalidateAndStop()
        httpConnection = nil
        session = nil
    }
}

extension ProxyURLProtocol: HTTPConnectionDelegate {
    func http(connection: HTTPConnection, didReceiveResponse response: URLResponse) {
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: URLCache.StoragePolicy.allowed)
    }

    func http(connection: HTTPConnection, didReceiveData data: Data) {
        client?.urlProtocol(self, didLoad: data)
    }
    
    func http(connection: HTTPConnection, didCompleteWithError error: Error?) {
        if let error = error {
            client?.urlProtocol(self, didFailWithError: error)
        }
        else {
            client?.urlProtocolDidFinishLoading(self)
        }
    }
    
    func http(connection: HTTPConnection, willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest) {
        let redirectRequest = (request as NSURLRequest).mutableCopy() as! NSMutableURLRequest
        URLProtocol.removeProperty(forKey: ProxyURLProtocolPassHeader, in: redirectRequest)
        // Tell the client about the redirect.
        
        client?.urlProtocol(self, wasRedirectedTo: redirectRequest as URLRequest, redirectResponse: response)
        
        // Stop our load.  The CFNetwork infrastructure will create a new NSURLProtocol instance to run
        // the load of the redirect.
        
        // The following ends up calling -URLSession:task:didCompleteWithError: with NSURLErrorDomain / NSURLErrorCancelled,
        // which specificallys traps and ignores the error.
        
        connection.invalidateAndStop()
        client?.urlProtocol(self, didFailWithError: NSError(domain: NSCocoaErrorDomain, code: NSUserCancelledError, userInfo: nil) )
    }
}

extension ProxyURLProtocol: URLSessionDelegate {
    //NSURLSessionDelegate
    func URLSession(_ session: Foundation.URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest, completionHandler: (URLRequest?) -> Void) {
        let redirectRequest = (request as NSURLRequest).mutableCopy() as! NSMutableURLRequest
        URLProtocol.removeProperty(forKey: ProxyURLProtocolPassHeader, in: redirectRequest)
        // Tell the client about the redirect.
        
        client?.urlProtocol(self, wasRedirectedTo: redirectRequest as URLRequest, redirectResponse: response)
        
        // Stop our load.  The CFNetwork infrastructure will create a new NSURLProtocol instance to run
        // the load of the redirect.
        
        // The following ends up calling -URLSession:task:didCompleteWithError: with NSURLErrorDomain / NSURLErrorCancelled,
        // which specificallys traps and ignores the error.
        
        task.cancel()
        client?.urlProtocol(self, didFailWithError: NSError(domain: NSCocoaErrorDomain, code: NSUserCancelledError, userInfo: nil) )
    }
    
    //    func URLSession(session: NSURLSession, task: NSURLSessionTask, didReceiveChallenge challenge: NSURLAuthenticationChallenge, completionHandler: (NSURLSessionAuthChallengeDisposition, NSURLCredential?) -> Void) {
    //        client?.URLProtocol(self, didReceiveAuthenticationChallenge: challenge)
    //    }
    
    func URLSession(_ session: Foundation.URLSession, dataTask: URLSessionDataTask, didReceiveResponse response: URLResponse, completionHandler: (Foundation.URLSession.ResponseDisposition) -> Void) {
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: URLCache.StoragePolicy.allowed)
        completionHandler(Foundation.URLSession.ResponseDisposition.allow)
    }
    
    func URLSession(_ session: Foundation.URLSession, task: URLSessionTask, didCompleteWithError error: NSError?) {
        if let error = error {
            client?.urlProtocol(self, didFailWithError: error)
        }
        else {
            client?.urlProtocolDidFinishLoading(self)
        }
    }
    
    func URLSession(_ session: Foundation.URLSession, dataTask: URLSessionDataTask, didReceiveData data: Data) {
        client?.urlProtocol(self, didLoad: data)
    }
}
