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
    
    var isWifiAvailable = false
    var isCellularAvailable = false
    
    lazy var pathUpdateHandler: ((NWPath) -> Void) = { path in
        self.path = path
        Singleton.isCellularAvailable = path.usesInterfaceType(.cellular)
        Singleton.isWifiAvailable = path.usesInterfaceType(.wifi)
    }
    
    let backgroudQueue = DispatchQueue.global(qos: .background)
    
    init() {
        pathMonitor = NWPathMonitor()
        pathMonitor.pathUpdateHandler = self.pathUpdateHandler
        pathMonitor.start(queue: backgroudQueue)
    }
    
    func checkAvailableNetwork(completionHandler: @escaping (_ respose :Bool) -> Void){
        if let availInterface = self.path?.availableInterfaces{
            print(availInterface.map({$0.type}))
        }
    }
}

class Singleton{
    ///To keep track of wifi status
    static var isWifiAvailable: Bool = false
    static var isCellularAvailable: Bool = false
}
