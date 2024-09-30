/*******************************************************************************************
 * Owner  : Kurian Ninan K
 * File Name        :  BureauAuth.swift
 * Module Name      :  Common
 * Description      : This class calls the initiate and finalise URL
 *******************************************************************************************/

import Foundation
import Network

enum NetworkError1: Error {
    case url
    case server
}

var STATUS_COMPLETE :Int64 = 1;
var STATUS_NETWORK_UNAVAILABLE  :Int64 = -2;
var STATUS_ONDIFFERENTNETWORK  :Int64 = -3 ;
var STATUS_EXCEPTION  :Int64 = -4 ;
var STATUS_UNKNOWN  :Int64 = 0;

extension URLSession {
    func synchronousDataTask(urlrequest: URLRequest) -> (data: Data?, response: URLResponse?, error: Error?) {
        var data: Data?
        var response: URLResponse?
        var error: Error?
        
        let semaphore = DispatchSemaphore(value: 0)
        
        let dataTask = self.dataTask(with: urlrequest) {
            data = $0
            response = $1
            error = $2
            
            semaphore.signal()
        }
        dataTask.resume()
        
        _ = semaphore.wait(timeout: .distantFuture)
        
        return (data, response, error)
    }
}


public class BureauAuth {
    private let components: URLComponents
    private let clientId : String?
    private let mode : Mode?
    private let callBackUrl : String?
    private let timeOut: Int?
    private let wifiEnabled: Bool?
    
    private init(components: URLComponents,clientId: String?,mode:  Mode?,callBackUrl: String?,timeOut: Int?,wifiEnabled: Bool) {
        self.components = components
        self.clientId = clientId
        if let modeValue = mode{
            self.mode = modeValue
        }else{
            self.mode = Mode.production
        }
        self.callBackUrl = callBackUrl
        self.timeOut = timeOut
        self.wifiEnabled = wifiEnabled
    }
    
    public enum Mode {
        case sandbox
        case production
    }
    
    public class Builder{
        private var components: URLComponents
        private var clientId : String?
        private var mode = Mode.production
        private var callBackUrl : String?
        private var timeOut: Int?
        private var wifiEnabled: Bool?
        
        public init() {
            self.components = URLComponents()
            self.clientId = ""
            self.mode = Mode.sandbox
            self.callBackUrl = String()
            self.timeOut = 10
            self.wifiEnabled = true
            if #available(iOS 12.0, *) {
                _ = NetworkReachability()
            }
        }
        
        public func setClientId(clientId: String) -> Builder {
            self.clientId = clientId
            return self
        }
        
        public func setCallBackUrl(callBackUrl: String) -> Builder {
            self.callBackUrl = callBackUrl
            return self
        }
        
        public func setTimeout(timeoutinSeconds: Int) -> Builder{
            self.timeOut = timeoutinSeconds
            return self
        }
        
        public func setMode(mode: Mode) -> Builder{
            self.mode = mode
            return self
        }
        
        public func disableWifiSwitchOver() -> Builder{
            self.wifiEnabled = false
            return self
        }
        
        public func build() -> BureauAuth {
            if self.mode == .production{
                self.components.host = "https://api.bureau.id/v2/auth/"
            }else{
                self.components.host = "https://api.sandbox.bureau.id/v2/auth/"
            }
            return BureauAuth(components: self.components, clientId: self.clientId, mode: self.mode, callBackUrl: self.callBackUrl, timeOut: self.timeOut,wifiEnabled: self.wifiEnabled ?? false)
        }
    }
    
    typealias FireAPICompletion =  (_ respose :String?, _ error: NetworkError1?) -> Void
    // API exposed to the SDK
    
    
    public func makeAuthCall(mobile: String,correlationId: String) -> AuthenticationStatus {
        var response = ""
        let semaphore = DispatchSemaphore(value: 0)
        if mode == Mode.sandbox {
            print("Bureau SDK:","Bureau SDK Transaction Mobile: ",mobile," CorrelationID: ",correlationId," clientID: ",clientId ?? "DEFCLIENTID"," timeout: ",timeOut ?? -1);
        }
        let group = DispatchGroup()
        group.enter()
        NetworkReachability().checkAvailableNetwork(completionHandler: {(bool) in
            print(Singleton.isWifiAvailable, Singleton.isCellularAvailable)
            if Singleton.isWifiAvailable && !Singleton.isCellularAvailable{
                print("STATUS CODE:", STATUS_ONDIFFERENTNETWORK)
            }else if !Singleton.isWifiAvailable && !Singleton.isCellularAvailable{
                print("STATUS CODE:", STATUS_NETWORK_UNAVAILABLE)
            }
            group.leave()
        })
        group.wait()
        
        print("isWifiAvailable: ", Singleton.isWifiAvailable, "isCellularAvailable: ", Singleton.isCellularAvailable)
        if(response == String(STATUS_ONDIFFERENTNETWORK)) {
            return .onDifferentNetwork
        }
        else if (response == String(STATUS_NETWORK_UNAVAILABLE)){
            return .networkUnavailable
        }else{
            if ((wifiEnabled ?? false) && Singleton.isWifiAvailable){
                print("Bureau SDK:","Wifi Enabled")
                self.fireURLWIFI(mobileNumber: mobile, correlationId: correlationId){(apiResponse, networkError) in
                    if let responseValue = apiResponse {
                        response = responseValue
                    } else {
                        response = "Error"
                    }
                    semaphore.signal()
                }
            }else{
                print("Bureau SDK:","Wifi Disabled")
                response = self.fireNormalURl(mobileNumber: mobile, correlationId: correlationId)
                semaphore.signal()
            }
            
            let timeoutInSeconds = timeOut ?? 20
            if semaphore.wait(timeout: .now() + .seconds(timeoutInSeconds)) == .timedOut {
                if mode == Mode.sandbox{
                    print("Bureau SDK:","Timeout Exiting")
                }
                print("Bureau SDK:","Timeout Exiting")
                response = "timeout"
            }
        }
        let responseString = String(response.prefix(20))
        NSLog(responseString)
        if verifyResponse(response: responseString){
            print("STATUS CODE:", STATUS_COMPLETE)
            return .completed
        }else{
            print("STATUS CODE:", STATUS_EXCEPTION)
            return .unknown
        }
    }
    
    
    public func makeAuthCall(mobile: String,correlationId: String) -> Bool{
        var response = ""
        let semaphore = DispatchSemaphore(value: 0)
        if mode == Mode.sandbox{
            print("Bureau SDK:","Bureau SDK Transaction Mobile: ",mobile," CorrelationID: ",correlationId," clientID: ",clientId ?? "DEFCLIENTID"," timeout: ",timeOut ?? -1);
        }
        let group = DispatchGroup()
        group.enter()
        NetworkReachability().checkAvailableNetwork(completionHandler: {(bool) in
            print(Singleton.isWifiAvailable, Singleton.isCellularAvailable)
            if Singleton.isWifiAvailable && !Singleton.isCellularAvailable{
                print("STATUS CODE:", STATUS_ONDIFFERENTNETWORK)
            }else if !Singleton.isWifiAvailable && !Singleton.isCellularAvailable{
                print("STATUS CODE:", STATUS_NETWORK_UNAVAILABLE)
            }
            group.leave()
        })
        group.wait()
        
        print("isWifiAvailable: ", Singleton.isWifiAvailable, "isCellularAvailable: ", Singleton.isCellularAvailable)
        if(response == String(STATUS_ONDIFFERENTNETWORK) || response == String(STATUS_NETWORK_UNAVAILABLE)){
            return false
        }else{
            if ((wifiEnabled ?? false) && Singleton.isWifiAvailable){
                print("Bureau SDK:","Wifi Enabled")
                self.fireURLWIFI(mobileNumber: mobile, correlationId: correlationId){(apiResponse, networkError) in
                    if let responseValue = apiResponse {
                        response = responseValue
                    } else {
                        response = "Error"
                    }
                    semaphore.signal()
                }
            }else{
                print("Bureau SDK:","Wifi Disabled")
                response = self.fireNormalURl(mobileNumber: mobile, correlationId: correlationId)
                semaphore.signal()
            }
            
            let timeoutInSeconds = timeOut ?? 20
            if semaphore.wait(timeout: .now() + .seconds(timeoutInSeconds)) == .timedOut {
                if mode == Mode.sandbox{
                    print("Bureau SDK:","Timeout Exiting")
                }
                print("Bureau SDK:","Timeout Exiting")
                response = "timeout"
            }
        }
        let responseString = String(response.prefix(20))
        NSLog(responseString)
        if verifyResponse(response: responseString){
            print("STATUS CODE:", STATUS_COMPLETE)
            return true
        }else{
            print("STATUS CODE:", STATUS_EXCEPTION)
            return false
        }
    }
    
    private func fireNormalURl(mobileNumber: String, correlationId: String) -> String{
        
        if mode == Mode.sandbox{
            print("Bureau SDK:","fireNormalURL correlationID : ", correlationId);
        }
        
        let errorResponse = "ERROR: Unknown HTTP Response"
        
        let queryItems = [URLQueryItem(name: "clientId", value: clientId), URLQueryItem(name: "correlationId", value: correlationId),URLQueryItem(name: "msisdn", value: mobileNumber),URLQueryItem(name: "callbackUrl", value: callBackUrl)]
        
        var urlComps = URLComponents(string: "\(components.host ?? "https://api.bureau.id/v2/auth/")initiate")!
        urlComps.queryItems = queryItems
        
        let finalUrl = urlComps.url!.absoluteString
        guard let finalUrlObject = URL(string: finalUrl) else { return errorResponse }
        
        let request = URLRequest(url: finalUrlObject)
        print("Bureau SDK:","FireNormalUrl Sending Get request: ",finalUrl)
        
        let (_, response, error) = URLSession.shared.synchronousDataTask(urlrequest: request)
        let httpResponse = response as? HTTPURLResponse
        
        print("Bureau SDK:","urlresponse: ",response ?? "Nil Response")
        
        if httpResponse?.statusCode != 200 {
            //error scenario
            print("Bureau SDK:","Task ended with status: \(String(describing: error))")
            return errorResponse
        }else {
            //success scenario
            print("Bureau SDK: ","Transaction Successful")
            return "HTTP/1.1 200 success"
        }
    }
    
    private func fireURLWIFI(mobileNumber: String,correlationId: String,completionHandler: @escaping FireAPICompletion){
        if mode == Mode.sandbox{
            print("Bureau SDK:","fireURL: correlationID : ", correlationId);
        }
        let queryItems = [URLQueryItem(name: "clientId", value: clientId), URLQueryItem(name: "correlationId", value: correlationId),URLQueryItem(name: "msisdn", value: mobileNumber),URLQueryItem(name: "callbackUrl", value: callBackUrl)]
        var urlComps = URLComponents(string: "\(components.host ?? "https://api.bureau.id/v2/auth/")initiate")!
        urlComps.queryItems = queryItems
        let finalUrl = urlComps.url!.absoluteString
        print("Bureau SDK:","fireURLWIFI Sending Get request: ",finalUrl)
        if #available(iOS 12.0, *) {
            let connectionManager = ConnectionManager()
            connectionManager.open(url: urlComps.url!, accessToken: nil, operators:"", completion: {(response) in
                completionHandler(String(response["http_status"] as? Int ?? 400) , nil)
            })
        }else{
            print("Bureau SDK: LOW iOS Version")
        }
    }
    
    private func verifyResponse(response: String) -> Bool{
        ///acceptabel response code 200-299
        let acceptableCodeRegex = ".*[2][0-9][0-9].*"
        let result = response.range(
            of: acceptableCodeRegex,
            options: .regularExpression
        )
        
        return result != nil
    }
    
}
