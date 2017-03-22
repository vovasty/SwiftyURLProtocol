//
//  Timer
//
//  Created by Solomenchuk, Vlad on 3/15/17.
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

public class Timer {
    fileprivate let timer: DispatchSourceTimer

    public init(timeout: Int,
                  queue: DispatchQueue = DispatchQueue.global(qos: DispatchQoS.QoSClass.default),
             repeatable: Bool,
        fireImmediately: Bool = false,
                  block:@escaping (_ timer: Timer) -> Void) {
        timer = DispatchSource.makeTimerSource(queue: queue)
        timer.setEventHandler { block(self) }

        let startTime = DispatchTime.now() + (fireImmediately ? 0.0 : Double(timeout))

        if repeatable {
            timer.scheduleRepeating(deadline: startTime,
                                    interval: DispatchTimeInterval.seconds(timeout))
        } else {
            timer.scheduleOneshot(deadline: startTime)
        }
    }

    public func start() {
        timer.resume()
    }

    public func stop() {
        timer.cancel()
    }

    deinit {
        timer.cancel()
    }
}
