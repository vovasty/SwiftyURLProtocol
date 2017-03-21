//
//  SwiftyURLProtocolTests.swift
//  SwiftyURLProtocolTests
//
//  Created by Solomenchuk, Vlad on 3/15/17.
//  Copyright © 2017 Solomenchuk, Vlad. All rights reserved.
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
    func http(connection: HTTPConnection, willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest) {
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
