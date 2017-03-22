//
//  SwiftyURLProtocolTests.swift
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
import XCTest
@testable import SwiftyURLProtocol

class ConnectionDelegate: HTTPConnectionDelegate {
    private var didCompleteWithError: ((Error?) -> Void)?
    private var willPerformHTTPRedirection: ((HTTPURLResponse, URLRequest) -> Void)?

    init() {}

    func http(connection: HTTPConnection, didReceiveResponse: URLResponse) {

    }

    func http(connection: HTTPConnection, didReceiveData: Data) {

    }

    func http(connection: HTTPConnection,
              willPerformHTTPRedirection response: HTTPURLResponse,
              newRequest request: URLRequest) {
        willPerformHTTPRedirection?(response, request)
    }
    func http(connection: HTTPConnection, didCompleteWithError error: Error?) {
        didCompleteWithError?(error)
    }

    @discardableResult
    func willPerformHTTPRedirection(handler: @escaping (HTTPURLResponse, URLRequest) -> Void) -> Self {
        willPerformHTTPRedirection = handler
        return self
    }

    @discardableResult
    func didCompleteWithError(handler: @escaping (Error?) -> Void) -> Self {
        didCompleteWithError = handler
        return self
    }
}

class HTTPConnectionTests: XCTestCase {
    func testHttps() {
        let exp = expectation(description: "https")
        let request = URLRequest(url: URL(string: "https://www.google.com")!)
        let conn = HTTPConnection(request: request, configuration: URLSessionConfiguration.default)
        let delegate = ConnectionDelegate()

        delegate.didCompleteWithError { (error) in
            XCTAssertNil(error)
            exp.fulfill()
        }

        conn.delegate = delegate
        conn.start()

        waitForExpectations(timeout: 10)
    }

    func testHttp() {
        let exp = expectation(description: "http")

        let request = URLRequest(url: URL(string: "http://www.google.com")!)
        let conn = HTTPConnection(request: request, configuration: URLSessionConfiguration.default)
        let delegate = ConnectionDelegate()

        delegate.didCompleteWithError { (error) in
            XCTAssertNil(error)
            exp.fulfill()
        }
        conn.delegate = delegate
        conn.start()

        waitForExpectations(timeout: 10)
    }

    func testRedirect() {
        let exp = expectation(description: "http")

        let request = URLRequest(url: URL(string: "http://google.com")!)
        let conn = HTTPConnection(request: request, configuration: URLSessionConfiguration.default)
        let delegate = ConnectionDelegate()
        delegate.didCompleteWithError { (error) in
            XCTAssertNil(error)
            exp.fulfill()
            }
            .willPerformHTTPRedirection { (_, _) in
                exp.fulfill()
        }
        conn.delegate = delegate
        conn.start()

        waitForExpectations(timeout: 10)
    }
}
