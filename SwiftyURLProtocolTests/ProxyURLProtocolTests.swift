//
//  import XCTest @testable import SwiftyURLProtocol ProxyURLProtocolTests.swift
//  SwiftyURLProtocol
//
//  Created by Solomenchuk, Vlad on 3/21/17.
//  Copyright © 2017 Solomenchuk, Vlad. All rights reserved.
//

import XCTest
@testable import SwiftyURLProtocol

class ProxyURLProtocolTests: XCTestCase {
    
    //run ssh -N -D 9050 127.0.0.1 -v
    func testSocks() {
        let exp = expectation(description: "http")
        let config = URLSessionConfiguration.default
        config.protocolClasses = [ProxyURLProtocol.self]
        
        ProxyURLProtocol.setRouter { (request) -> ProxyURLProtocol.Proxy? in
            return ProxyURLProtocol.Proxy.socks(host: "127.0.0.1", port: 9050) { (host, timeout, closure) -> Stopable? in
                closure(nil)
                return nil
            }
        }
        
        let session = URLSession(configuration: config)
        let task = session.dataTask(with: URL(string: "http://google.com")!) { (_, _, error) in
            XCTAssertNil(error)
            exp.fulfill()
        }
        
        task.resume()
        waitForExpectations(timeout: 100)
    }
}
