SwiftyURLProtocol is an `URLProtocol` wrapper. Can be used in conjunction with `UIWebView` to provide http/sock proxy support.

## Features

- [x] Multiple proxies
- [x] Router to define which proxy to use for a request
- [x] fixes SOCKS proxy bug on iOS (hosts are resolved locally instead of via proxy)

## Requirements

- iOS 8.0+ / macOS 10.10+
- Xcode 8.1+
- Swift 3.0+

## Installation

Include `SwiftyURLProtocol` as an framework into your project.

## Usage

### URLSession

To use `SwiftyURLProtocol` with `URLSession` add it into `URLSessionConfiguration.protocolClasses`

```swift
import SwiftyURLProtocol

SwiftyURLProtocol.setRouter { (request) -> ProxyURLProtocol.Proxy? in
    return ProxyURLProtocol.Proxy.socks(host: "127.0.0.1", port: 9050, probe: nil)
}

let config = URLSessionConfiguration.default
config.protocolClasses = [SwiftyURLProtocol.self]

let task = session.dataTask(with: URL(string: "http://google.com")!) { (data, response, error) in
    ...
}
        
task.resume()
```
#### UIWebView

URLProtocol.registerClass(ProxyURLProtocol.self)

To use `SwiftyURLProtocol` with `UIWebView` register it in `URLProtocol`

```swift
import SwiftyURLProtocol

// route all .onion hosts via socks proxy. Everything else will be accessed directly.
SwiftyURLProtocol.setRouter { (request) -> ProxyURLProtocol.Proxy? in
    if request.url?.host?.hasSuffix(".onion") ?? false {
        return ProxyURLProtocol.Proxy.socks(host: "127.0.0.1", port: 9050, probe: nil)
    }
    else {
        return nil
    }
}

URLProtocol.registerClass(SwiftyURLProtocol.self)
        
task.resume()
```