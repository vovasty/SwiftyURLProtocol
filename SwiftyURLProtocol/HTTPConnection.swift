//
//  HTTPConnection.swift
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

extension URLRequest {
    var httpMessage: CFHTTPMessage? {
        guard let httpMethod = httpMethod, let url = url else {
            return nil
        }

        let result = CFHTTPMessageCreateRequest(nil,
                                                httpMethod as CFString,
                                                url as CFURL, kCFHTTPVersion1_1).takeRetainedValue()

        for header in allHTTPHeaderFields ?? [:] {
            CFHTTPMessageSetHeaderFieldValue(result,
                                             header.key as CFString,
                                             header.value as CFString)
        }

        if let cookies = HTTPCookieStorage.shared.cookies(for: url), !cookies.isEmpty {
            let cookieHeaders = HTTPCookie.requestHeaderFields(with: cookies)
            for cookieHeader in cookieHeaders {
                CFHTTPMessageSetHeaderFieldValue(result,
                                                 cookieHeader.key as CFString,
                                                 cookieHeader.value as CFString)
            }
        }

        if let body = self.httpBody {
            CFHTTPMessageSetBody(result, body as CFData)
        }

        return result
    }
}

extension HTTPURLResponse {
    convenience init?(url: URL, message: CFHTTPMessage) {
        let statusCode = CFHTTPMessageGetResponseStatusCode(message)
        let httpVersion = CFHTTPMessageCopyVersion(message).takeRetainedValue() as String
        let headerFields = CFHTTPMessageCopyAllHeaderFields(message)?.takeRetainedValue() as? [String: String]

        self.init(url: url, statusCode: statusCode, httpVersion: httpVersion, headerFields: headerFields)
    }
}

protocol HTTPConnectionDelegate: class {
    func http(connection: HTTPConnection, didReceiveResponse: URLResponse)
    func http(connection: HTTPConnection, didReceiveData: Data)
    func http(connection: HTTPConnection,
              willPerformHTTPRedirection response: HTTPURLResponse,
              newRequest request: URLRequest)
    func http(connection: HTTPConnection, didCompleteWithError error: Error?)
}

class HTTPConnection: NSObject {
    public let request: URLRequest
    public let configuration: URLSessionConfiguration
    var httpStream: InputStream?
    var haveReceivedResponse: Bool = false
    var runLoop = RunLoop.main
    var runLoopMode = RunLoopMode.defaultRunLoopMode
    fileprivate var buf = [UInt8](repeating: 0, count: 1024)

    weak var delegate: HTTPConnectionDelegate?

    init(request: URLRequest, configuration: URLSessionConfiguration) {
        self.request = request
        self.configuration = configuration
    }

    func start() {
        assert(self.httpStream == nil)

        guard let httpMessage = request.httpMessage else {
            let error = NSError(domain: NSCocoaErrorDomain, code: NSUserCancelledError, userInfo: nil)
            delegate?.http(connection: self, didCompleteWithError: error)
            return
        }

        let httpStream = createHttpStream(request: request, httpMessage: httpMessage)
        self.httpStream = httpStream
        setupSSL(httpStream: httpStream)
        setupProxy(httpStream: httpStream, configuration: configuration)

        httpStream.delegate = self
        httpStream.schedule(in: runLoop, forMode: runLoopMode)
        httpStream.open()
    }

    private func setupSSL(httpStream: InputStream) {
        // SSL/TLS hardening -- this is a TLS request
        if request.url?.scheme?.lowercased() == "https" {
            var sslOptions: [String: CFString] = [:]

            // Enforce TLS version
            // https://developer.apple.com/library/ios/technotes/tn2287/_index.html#//apple_ref/doc/uid/DTS40011309

            switch configuration.tlsMinimumSupportedProtocol {
            case .tlsProtocol1:
                sslOptions[kCFStreamSSLLevel as String] = kCFStreamSocketSecurityLevelTLSv1
            default: break
            }

            CFReadStreamSetProperty(httpStream,
                                    CFStreamPropertyKey(rawValue: kCFStreamPropertySSLSettings),
                                    sslOptions as CFDictionary)

            //TODO: SSL validation
        }
    }

    private func createHttpStream(request: URLRequest, httpMessage: CFHTTPMessage) -> InputStream {
        let httpStream: InputStream

        if let httpBodyStream = request.httpBodyStream {
            httpStream = CFReadStreamCreateForStreamedHTTPRequest(kCFAllocatorDefault,
                                                                  httpMessage,
                                                                  httpBodyStream).takeRetainedValue()
        } else {
            httpStream = CFReadStreamCreateForHTTPRequest(kCFAllocatorDefault, httpMessage).takeRetainedValue()
        }

        CFReadStreamSetProperty(httpStream,
                                CFStreamPropertyKey(kCFStreamPropertyHTTPAttemptPersistentConnection),
                                kCFBooleanTrue)

        return httpStream
    }

    private func setupProxy(httpStream: InputStream, configuration: URLSessionConfiguration) {
        if let connectionProxyDictionary = configuration.connectionProxyDictionary {
            let proxyType = connectionProxyDictionary[kCFProxyTypeKey as AnyHashable] as? String ?? ""
            let httpProxyEnable = configuration.connectionProxyDictionary?[kCFNetworkProxiesHTTPEnable as AnyHashable]
                as? Bool ?? false

            if  proxyType == kCFProxyTypeHTTP as String || httpProxyEnable {
                if let host = connectionProxyDictionary[kCFNetworkProxiesHTTPProxy as AnyHashable] as? String,
                    let port = connectionProxyDictionary[kCFNetworkProxiesHTTPPort as AnyHashable] as? Int {
                    let proxyDict = [host: port]

                    CFReadStreamSetProperty(httpStream, CFStreamPropertyKey(kCFNetworkProxiesHTTPProxy
                    ), proxyDict as CFDictionary)
                }
            } else if proxyType == kCFProxyTypeSOCKS as String {
                if let host = connectionProxyDictionary[kCFStreamPropertySOCKSProxyHost as AnyHashable] as? String,
                    let port = connectionProxyDictionary[kCFStreamPropertySOCKSProxyPort as AnyHashable] as? Int {
                    let proxyDict: [String: Any] = [kCFStreamPropertySOCKSProxyHost as String: host,
                                                    kCFStreamPropertySOCKSProxyPort as String: port]

                    CFReadStreamSetProperty(httpStream,
                                            CFStreamPropertyKey(kCFStreamPropertySOCKSProxy),
                                            proxyDict as CFDictionary)
                }
            }
        }
    }

    func invalidateAndStop() {
        delegate = nil
        httpStream?.delegate = nil
        httpStream?.remove(from: runLoop, forMode: runLoopMode)
        httpStream?.close()
        httpStream = nil
    }

    deinit {
        invalidateAndStop()
    }
}

extension HTTPConnection: StreamDelegate {
    public func stream(_ aStream: Stream, handle eventCode: Stream.Event) {
        assert(aStream == httpStream)

        // Handle the response as soon as it's available
        if !haveReceivedResponse,
            // swiftlint:disable force_cast
            let response = aStream.property(forKey: Stream.PropertyKey(kCFStreamPropertyHTTPResponseHeader as String)),
            CFHTTPMessageIsHeaderComplete(response as! CFHTTPMessage),
            let url = aStream.property(forKey: Stream.PropertyKey(kCFStreamPropertyHTTPFinalURL as String)) as? URL,
            let urlResponse = HTTPURLResponse(url: url, message: response as! CFHTTPMessage) {
            // swiftlint:enable force_cast

            //TODO: Authentication

            // By reaching this point, the response was not a valid request for authentication,
            // so go ahead and report it
            haveReceivedResponse = true

            /* Handle redirects */
            if [301, 302, 307].contains(urlResponse.statusCode),
                let newURL = urlResponse.allHeaderFields["Location"] as? String {

                var newRequest = request
                newRequest.httpShouldUsePipelining = true
                newRequest.url = URL(string: newURL, relativeTo: request.url)
                if request.mainDocumentURL == request.url {
                    // Previous request *was* the maindocument request.
                    newRequest.mainDocumentURL = newRequest.url
                }
                delegate?.http(connection: self, willPerformHTTPRedirection: urlResponse, newRequest: newRequest)
            } else {
                delegate?.http(connection: self, didReceiveResponse: urlResponse)
            }
        }

        // Next course of action depends on what happened to the stream
        switch  eventCode {
        case Stream.Event.errorOccurred:    // Report an error in the stream as the operation failing
            delegate?.http(connection: self, didCompleteWithError: aStream.streamError)

        case Stream.Event.endEncountered:   // Report the end of the stream to the delegate
            delegate?.http(connection: self, didCompleteWithError: nil)
        case Stream.Event.hasBytesAvailable:
            guard let aStream = aStream as? InputStream else { return }
            var data = Data(capacity: 1024)

            while aStream.hasBytesAvailable {
                let count = aStream.read(&buf, maxLength: 1024)
                data.append(buf, count: count)
            }

            delegate?.http(connection: self, didReceiveData: data)
        default: break
        }
    }
}
