//
//  ProxyURLProtocolTests.swift
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
import XCTest
@testable import SwiftyURLProtocol

class Rslvr: Stopable {
    init (closure: (_ error: Error?) -> Void) {
        let error = NSError(domain: "test", code: -1, userInfo: nil)
        closure(error)
    }
    func stop(){}
}

class SwiftyURLProtocolTests: XCTestCase {
    
    //run ssh -N -D 9050 127.0.0.1 -v
    func testSocks() {
        let exp = expectation(description: "http")
        
        SwiftyURLProtocol.setRouter { (request) -> SwiftyURLProtocol.Proxy? in
            return SwiftyURLProtocol.Proxy.socks(host: "127.0.0.1", port: 9050, probe: nil)
        }

        let config = URLSessionConfiguration.default
        config.protocolClasses = [SwiftyURLProtocol.self]

        let session = URLSession(configuration: config)
        let task = session.dataTask(with: URL(string: "http://google.com")!) { (_, _, error) in
            XCTAssertNil(error)
            exp.fulfill()
        }
        
        task.resume()
        waitForExpectations(timeout: 100)
    }
    
    func testProbe() {
        let exp = expectation(description: "resolver")
        
        SwiftyURLProtocol.setRouter { (request) -> SwiftyURLProtocol.Proxy? in
            return SwiftyURLProtocol.Proxy.socks(host: "127.0.0.1", port: 9050) { (host, closure) -> Stopable in
                return Rslvr(closure: closure)
            }
        }

        let config = URLSessionConfiguration.default
        config.protocolClasses = [SwiftyURLProtocol.self]

        let session = URLSession(configuration: config)
        let task = session.dataTask(with: URL(string: "http://google.com")!) { (_, _, error) in
            XCTAssertNotNil(error)
            exp.fulfill()
        }
        
        task.resume()
        waitForExpectations(timeout: 100)
    }
}
