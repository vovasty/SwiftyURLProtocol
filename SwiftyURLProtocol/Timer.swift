//
//  Timer.swift
//  TrekNoir
//
//  Created by Solomenchuk, Vlad on 4/19/17.
//  Copyright © 2017 Aramzamzam LLC. All rights reserved.
//

import Foundation

class Timer {
    fileprivate let timer: DispatchSourceTimer
    
    init(timeInterval: Int,
         repeats: Bool,
         queue: DispatchQueue = DispatchQueue.main,
         fireImmediately: Bool = false,
         block:@escaping (_ timer: Timer) -> Void) {
        timer = DispatchSource.makeTimerSource(queue: queue)
        timer.setEventHandler { block(self) }
        
        let startTime = DispatchTime.now() + (fireImmediately ? 0.0 : Double(timeInterval))
        
        if repeats {
            timer.scheduleRepeating(deadline: startTime,
                                    interval: DispatchTimeInterval.seconds(timeInterval))
        } else {
            timer.scheduleOneshot(deadline: startTime)
        }
        timer.resume()
    }
    
    func invalidate() {
        timer.cancel()
    }
    
    deinit {
        timer.cancel()
    }
}
