//
//  Reachability.swift
//  BureauAuthentication
//
//  Created by Abhinand on 13/06/22.
//  Copyright © 2022 Keyvalue. All rights reserved.
//

import Foundation
import Network


///To check whether the device is connected to wifi or not
///handler will be running in background thread
@available(iOS 12.0, *)
class NetworkReachability {

   var pathMonitor: NWPathMonitor!
   var path: NWPath?
    
   lazy var pathUpdateHandler: ((NWPath) -> Void) = { path in
    self.path = path
    if path.status == NWPath.Status.satisfied {
        NSLog("satisfied")
        Singleton.isWifiAvailable = true
    } else if path.status == NWPath.Status.unsatisfied {
        NSLog("unsatisfied")
        Singleton.isWifiAvailable = false
    } else if path.status == NWPath.Status.requiresConnection {
        Singleton.isWifiAvailable = true
        NSLog("requiresConnection")
    }
}

let backgroudQueue = DispatchQueue.global(qos: .background)

init() {
    pathMonitor = NWPathMonitor(requiredInterfaceType: .wifi)
    pathMonitor.pathUpdateHandler = self.pathUpdateHandler
    pathMonitor.start(queue: backgroudQueue)
   }

 func isNetworkAvailable() -> Bool {
        if let path = self.path {
           if path.status == NWPath.Status.satisfied {
            return true
          }
        }
          return false
   }
 }


class Singleton{
    ///To keep track of wifi status
    static var isWifiAvailable: Bool = true
}
