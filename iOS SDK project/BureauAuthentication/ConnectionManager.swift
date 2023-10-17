#if canImport(UIKit)
import UIKit
#else
import Foundation
#endif
import Network
import os

typealias ResultHandler = (ConnectionResult) -> Void

let BureauSdkVersion = "2.0"

// Force connectivity to cellular only
// CellularConnectionManager might switch from tls to non-tls between redirects
//
@available(iOS 12.0, *)
class ConnectionManager: ConnectionManagerDelegate {
    
    private var connection: NWConnection?
    
    //Mitigation for tcp timeout not triggering any events.
    private var timer: Timer?
    private var CONNECTION_TIME_OUT = 5.0
    private let MAX_REDIRECTS = 10
    private var pathMonitor: NWPathMonitor?
    private var checkResponseHandler: ResultHandler!
    
    public convenience init(connectionTimeout: Double) {
        self.init()
        self.CONNECTION_TIME_OUT = connectionTimeout
    }
    
    func open(url: URL, accessToken: String?, operators: String?, completion: @escaping ([String : Any]) -> Void) {
        
        let requestId = UUID().uuidString
        
        guard let _ = url.scheme, let _ = url.host else {
            completion(convertNetworkErrorToDictionary(err:NetworkError.other("No scheme or host found")))
            return
        }
        
        var redirectCount = 0
        // This closure will be called on main thread
        checkResponseHandler = { [weak self] (response) -> Void in
            
            guard let self = self else {
                var json = [String : Any]()
                json["error"] = "sdk_error"
                json["error_description"] = "Unable to carry on"
                completion(json)
                return
            }
            
            switch response {
            case .follow(let redirectResult):
                if let url = redirectResult.url {
                    redirectCount+=1
                    if redirectCount <= self.MAX_REDIRECTS {
                        self.createTimer()
                        self.activateConnectionForDataFetch(url: url, accessToken: nil, operators: nil, cookies: redirectResult.cookies, requestId: requestId, completion: self.checkResponseHandler)
                    } else {
                        self.cleanUp()
                        completion(self.convertNetworkErrorToDictionary(err: NetworkError.tooManyRedirects))
                    }
                } else {
                    self.cleanUp()
                }
            case .err(let error):
                self.cleanUp()
                completion(self.convertNetworkErrorToDictionary(err: error))
            case .dataOK(let connResp):
                self.cleanUp()
                completion(self.convertConnectionResponseToDictionary(resp: connResp))
            case .dataErr(let connResp):
                self.cleanUp()
                completion(self.convertConnectionResponseToDictionary(resp: connResp))
            }
        }
        //Initiating on the main thread to synch, as all connection update/state events will also be called on main thread
        DispatchQueue.main.async {
            self.startMonitoring()
            self.createTimer()
            self.activateConnectionForDataFetch(url: url, accessToken: accessToken, operators: operators, cookies: nil,requestId: requestId, completion: self.checkResponseHandler)
        }
    }
    
    func convertConnectionResponseToDictionary(resp: ConnectionResponse)  -> [String : Any] {
        var json: [String : Any] = [:]
        json["http_status"] = resp.status
        do {
            // load JSON response into a dictionary
            if let body = resp.body, let dictionary = try JSONSerialization.jsonObject(with: body, options: .mutableContainers) as? [String : Any] {
                json["response_body"] = dictionary
            }
        } catch {
            if let body = resp.body {
                json["response_raw_body"] = body
            } else {
                return convertNetworkErrorToDictionary(err: NetworkError.other("JSON deserializarion"))
            }
            
        }
        return json
    }
    
    func convertNetworkErrorToDictionary(err: NetworkError) -> [String : Any] {
        var json = [String : Any]()
        switch err {
        case .invalidRedirectURL(let string):
            json["error"] = "sdk_redirect_error"
            json["error_description"] = string
        case .tooManyRedirects:
            json["error"] = "sdk_redirect_error"
            json["error_description"] = "Too many redirects"
        case .connectionFailed(let string):
            json["error"] = "sdk_connection_error"
            json["error_description"] = string
        case .connectionCantBeCreated(let string):
            json["error"] = "sdk_connection_error"
            json["error_description"] = string
        case .other(let string):
            json["error"] = "sdk_error"
            json["error_description"] = string
        }
        return json
    }
    
    
    // MARK: - Internal
    func cancelExistingConnection() {
        if self.connection != nil {
            self.connection?.cancel() // This should trigger a state update
            self.connection = nil
        }
    }
    
    func createConnectionUpdateHandler(completion: @escaping ResultHandler, readyStateHandler: @escaping ()-> Void) -> (NWConnection.State) -> Void {
        return { [weak self] (newState) in
            switch (newState) {
            case .setup:
                print("Connection State: Setup\n")
            case .preparing:
                print("Connection State: Preparing\n")
            case .ready:
                let msg = self?.connection.debugDescription ?? "No connection details"
                print("Connection State: Ready \(msg)\n")
                readyStateHandler() //Send and Receive
            case .waiting(let error):
                print("Connection State: Waiting \(error.localizedDescription) \n")
            case .cancelled:
                print("Connection State: Cancelled\n")
            case .failed(let error):
                completion(.err(NetworkError.other("Connection State: Failed \(error.localizedDescription)")))
            @unknown default:
                print("Connection ERROR State not defined\n")
                completion(.err(NetworkError.other("Connection State: Unknown \(newState)")))
            }
        }
    }
    
    // MARK: - Utility methods
    func createHttpCommand(url: URL, accessToken: String?, operators: String?, cookies: [HTTPCookie]?, requestId: String?) -> String? {
        guard let host = url.host, let scheme = url.scheme  else {
            return nil
        }
        var path = url.path
        // the path method is stripping ending / so adding it back
        if (url.absoluteString.hasSuffix("/") && !url.path.hasSuffix("/")) {
            path += "/"
        }

        if (path.count == 0) {
            path = "/"
        }

        var cmd = String(format: "GET %@", path)
        
        if let q = url.query {
            cmd += String(format:"?%@", q)
        }
        
        cmd += String(format:" HTTP/1.1\r\nHost: %@", host)
        if (scheme.starts(with:"https") && url.port != nil && url.port != 443) {
            cmd += String(format:":%d", url.port!)
        } else if (scheme.starts(with:"http") && url.port != nil && url.port != 80) {
            cmd += String(format:":%d", url.port!)
        }
        if let token = accessToken {
            cmd += "\r\nAuthorization: Bearer \(String(describing: token)) "
        }
        if let req = requestId {
            cmd += "\r\nx-bureau-sdk-request: \(String(describing: req)) "
        }
        if let op = operators {
            cmd += "\r\nx-bureau-ops: \(String(describing: op)) "
        }
#if targetEnvironment(simulator)
        cmd += "\r\nx-bureau-mode: sandbox"
#endif
        if let cookies = cookies {
            var cookieCount = 0
            var cookieString = String()
            for i in 0..<cookies.count {
                if (((cookies[i].isSecure && scheme == "https") || (!cookies[i].isSecure)) && (cookies[i].domain == "" || (cookies[i].domain != "" && host.contains(cookies[i].domain))) && (cookies[i].path == "" ||  path.starts(with: cookies[i].path))) {
                    if (cookieCount > 0) {
                        cookieString += "; "
                    }
                    cookieString += String(format:"%@=%@", cookies[i].name, cookies[i].value)
                    cookieCount += 1
                }
            }
            if (cookieString.count > 0) {
                cmd += "\r\nCookie: \(String(describing: cookieString))"
            }
        }
        cmd += "\r\nUser-Agent: \(BureauSdkVersion) "
        cmd += "\r\nAccept: text/html,application/xhtml+xml,application/xml,*/*"
        cmd += "\r\nConnection: close\r\n\r\n"
        return cmd
    }
    
    func createConnection(scheme: String, host: String, port: Int? = nil) -> NWConnection? {
        if scheme.isEmpty ||
            host.isEmpty ||
            !(scheme.hasPrefix("http") ||
              scheme.hasPrefix("https")) {
            return nil
        }
        
        let tcpOptions = NWProtocolTCP.Options()
        tcpOptions.connectionTimeout = 5 //Secs
        tcpOptions.enableKeepalive = false
        
        var tlsOptions: NWProtocolTLS.Options?
        var fport = (port != nil ? NWEndpoint.Port(integerLiteral: NWEndpoint.Port.IntegerLiteralType(port!)) : NWEndpoint.Port.http)
        
        if (scheme.starts(with:"https")) {
            fport = (port != nil ? NWEndpoint.Port(integerLiteral: NWEndpoint.Port.IntegerLiteralType(port!)) : NWEndpoint.Port.https)
            tlsOptions = .init()
            tcpOptions.enableFastOpen = true //Save on tcp round trip by using first tls packet
        }
        
        let params = NWParameters(tls: tlsOptions , tcp: tcpOptions)
        params.serviceClass = .responsiveData
#if !targetEnvironment(simulator)
        // force network connection to cellular only
        params.requiredInterfaceType = .cellular
        params.prohibitExpensivePaths = false
        params.prohibitedInterfaceTypes = [.wifi, .loopback, .wiredEthernet]
#endif
        connection = NWConnection(host: NWEndpoint.Host(host), port: fport, using: params)
        return connection
    }
    
    func parseHttpStatusCode(response: String) -> Int {
        let status = response[response.index(response.startIndex, offsetBy: 9)..<response.index(response.startIndex, offsetBy: 12)]
        return Int(status) ?? 0
    }
    
    /// Decodes a response, first attempting with UTF8 and then fallback to ascii
    /// - Parameter data: Data which contains the response
    /// - Returns: decoded response as String
    func decodeResponse(data: Data) -> String? {
        guard let response = String(data: data, encoding: .utf8) else {
            return String(data: data, encoding: .ascii)
        }
        return response
    }
    
    func parseRedirect(requestUrl: URL, response: String, cookies: [HTTPCookie]?) -> RedirectResult? {
        guard let _ = requestUrl.host else {
            return nil
        }
        //header could be named "Location" or "location"
        if let range = response.range(of: #"ocation: (.*)\r\n"#, options: .regularExpression) {
            let location = response[range]
            let redirect = location[location.index(location.startIndex, offsetBy: 9)..<location.index(location.endIndex, offsetBy: -1)]
            // some location header are not properly encoded
            let cleanRedirect = redirect.replacingOccurrences(of: " ", with: "+")
            if let redirectURL =  URL(string: String(cleanRedirect)) {
                return RedirectResult(url: redirectURL.host == nil ? URL(string: redirectURL.description, relativeTo: requestUrl)! : redirectURL, cookies: self.parseCookies(url:requestUrl, response: response, existingCookies: cookies))
            } else {
                return nil
            }
        }
        return nil
    }
    
    func parseCookies(url: URL, response: String, existingCookies: [HTTPCookie]?) -> [HTTPCookie]? {
        var cookies = [HTTPCookie]()
        if let existing = existingCookies {
            for i in 0..<existing.count {
                cookies.append(existing[i])
            }
        }
        var position = response.startIndex
        while let range = response.range(of: #"ookie: (.*)\r\n"#, options: .regularExpression, range: position..<response.endIndex) {
            let line = response[range]
            let optCookieString:Substring? = line[line.index(line.startIndex, offsetBy: 7)..<line.index(line.endIndex, offsetBy: -1)]
            if let cookieString = optCookieString {
                let optCs: [HTTPCookie]? = HTTPCookie.cookies(withResponseHeaderFields: ["Set-Cookie" : String(cookieString)], for: url)
                if let cs = optCs  {
                    if (!cs.isEmpty) {
                        cookies.append((cs.first)!)
                    }
                }
            }
            position = range.upperBound
        }
        return (!cookies.isEmpty) ? cookies : nil
    }
    
    func createTimer() {
        
        if let timer = self.timer, timer.isValid {
            os_log("Invalidating the existing timer", type: .debug)
            timer.invalidate()
        }
        
        os_log("Starting a new timer", type: .debug)
        self.timer = Timer.scheduledTimer(timeInterval: self.CONNECTION_TIME_OUT,
                                          target: self,
                                          selector: #selector(self.fireTimer),
                                          userInfo: nil,
                                          repeats: false)
    }
    
    @objc func fireTimer() {
        timer?.invalidate()
        checkResponseHandler(.err(NetworkError.connectionCantBeCreated("Connection cancelled - time out")))
    }
    
    func startMonitoring() {
        if let monitor = pathMonitor { monitor.cancel() }
        pathMonitor = NWPathMonitor()
        pathMonitor?.pathUpdateHandler = { path in
            let interfaceTypes = path.availableInterfaces.map { $0.type }
            for interfaceType in interfaceTypes {
                switch interfaceType {
                case .wifi:
                    print("<--Connetion: Wifi Enabled -->")
                case .cellular:
                    print("<--Connetion: Cellular ipv4 \(path.supportsIPv4.description) ipv6 \(path.supportsIPv6.description) -->")
                case .wiredEthernet:
                    print("<--Connetion:Wired Ethernet-->")
                case .loopback:
                    print("<--Connetion: Loopback-->")
                case .other:
                    print("<--Connetion: other-->")
                default:
                    print("<--Connetion: unknown-->")
                }
            }
        }
        pathMonitor?.start(queue: .main)
    }
    
    func stopMonitoring() {
        if let monitor = pathMonitor {
            monitor.cancel()
            pathMonitor = nil
        }
    }
    
    func cleanUp() {
        self.timer?.invalidate()
        self.stopMonitoring()
        self.cancelExistingConnection()
    }
    
    
    func activateConnectionForDataFetch(url: URL, accessToken: String?, operators: String?, cookies: [HTTPCookie]?, requestId: String?, completion: @escaping ResultHandler) {
        self.cancelExistingConnection()
        guard let scheme = url.scheme,
              let host = url.host else {
            completion(.err(NetworkError.other("URL has no Host or Scheme")))
            return
        }
        
        guard let command = createHttpCommand(url: url, accessToken: accessToken, operators: operators, cookies: cookies, requestId: requestId),
              let data = command.data(using: .utf8) else {
            completion(.err(NetworkError.other("Unable to create HTTP Request command")))
            return
        }
                
        connection = createConnection(scheme: scheme, host: host, port: url.port)
        if let connection = connection {
            connection.stateUpdateHandler = createConnectionUpdateHandler(completion: completion, readyStateHandler: { [weak self] in
                self?.sendAndReceiveWithBody(requestUrl: url, data: data, cookies:cookies, completion: completion)
            })
            // All connection events will be delivered on the main thread.
            connection.start(queue: .main)
        } else {
            os_log("Problem creating a connection ", url.absoluteString)
            completion(.err(NetworkError.connectionCantBeCreated("Problem creating a connection \(url.absoluteString)")))
        }
    }
    
    func sendAndReceiveWithBody(requestUrl: URL, data: Data, cookies: [HTTPCookie]?, completion: @escaping ResultHandler) {
        connection?.send(content: data, completion: NWConnection.SendCompletion.contentProcessed({ (error) in
            if let err = error {
                os_log("Sending error %s", type: .error, err.localizedDescription)
                completion(.err(NetworkError.other(err.localizedDescription)))
                
            }
        }))
        
        timer?.invalidate()

        //Read the entire response body
        connection?.receiveMessage { data, context, isComplete, error in
            
            os_log("Receive isComplete: %s", isComplete.description)
            if let err = error {
                completion(.err(NetworkError.other(err.localizedDescription)))
                return
            }
            
            if let d = data, !d.isEmpty, let response = self.decodeResponse(data: d) {
                
                os_log("Response:\n %s", response)
                
                let status = self.parseHttpStatusCode(response: response)
                os_log("\n----\nHTTP status: %s", String(status))
                
                switch status {
                case 200...202:
                    if let r = self.getResponseBody(response: response) {
                        completion(.dataOK(ConnectionResponse(status: status, body: r)))
                    } else {
                        completion(.dataOK(ConnectionResponse(status: status, body: nil)))
                    }
                case 204:
                    completion(.dataOK(ConnectionResponse(status: status, body: nil)))
                case 301...303, 307...308:
                    guard let ru = self.parseRedirect(requestUrl: requestUrl, response: response, cookies: cookies) else {
                        completion(.err(NetworkError.invalidRedirectURL("Invalid URL - unable to parseRecirect")))
                        return
                    }
                    completion(.follow(ru))
                case 400...451:
                    if let r = self.getResponseBody(response: response) {
                        completion(.dataErr(ConnectionResponse(status: status, body:r)))
                    } else {
                        completion(.err(NetworkError.other("Unexpected HTTP Status \(status)")))
                    }
                case 500...511:
                    if let r = self.getResponseBody(response: response) {
                        completion(.dataErr(ConnectionResponse(status: status, body:r)))
                    } else {
                        completion(.err(NetworkError.other("Unexpected HTTP Status \(status)")))
                    }
                default:
                    completion(.err(NetworkError.other("Unexpected HTTP Status \(status)")))
                }
            } else {
                completion(.err(NetworkError.other("Response has no data or corrupt")))
            }
        }
    }
    
    func getResponseBody(response: String) -> Data? {
        if let rangeContentType = response.range(of: #"Content-Type: (.*)\r\n"#, options: .regularExpression) {
            // retrieve content type
            let contentType = response[rangeContentType]
            let type = contentType[contentType.index(contentType.startIndex, offsetBy: 9)..<contentType.index(contentType.endIndex, offsetBy: -1)]
            if (type.contains("application/json") || type.contains("application/hal+json") || type.contains("application/problem+json")) {
                if let range = response.range(of: "\r\n\r\n") {
                    if let rangeTransferEncoding = response.range(of: #"Transfer-Encoding: chunked\r\n"#, options: .regularExpression) {
                        if (!rangeTransferEncoding.isEmpty) {
                            if let r1 = response.range(of: "\r\n\r\n") , let r2 = response.range(of:"\r\n0\r\n") {
                                let c = response[r1.upperBound..<r2.lowerBound]
                                if let start = c.firstIndex(of: "{") {
                                    let json = c[start..<c.index(c.endIndex, offsetBy: 0)]
                                    os_log("json: %s",  String(json))
                                    let jsonString = String(json)
                                    guard let data = jsonString.data(using: .utf8) else {
                                        return nil
                                    }
                                    return data
                                }
                            }
                        }
                    }
                    let content = response[range.upperBound..<response.index(response.endIndex, offsetBy: 0)]
                    if let start = content.firstIndex(of: "{") {
                        let json = content[start..<response.index(response.endIndex, offsetBy: 0)]
                        os_log("json: %s",  String(json))
                        let jsonString = String(json)
                        guard let data = jsonString.data(using: .utf8) else {
                            return nil
                        }
                        return data
                    }
                }
            }
        }
        return nil
    }
    
    
    // Utils
    func post(url: URL, headers: [String : Any], body: String?, completion: @escaping ([String : Any]) -> Void) {
        
        guard let _ = url.scheme, let _ = url.host else {
            completion(convertNetworkErrorToDictionary(err:NetworkError.other("No scheme or host found")))
            return
        }
        
        // This closure will be called on main thread
        checkResponseHandler = { [weak self] (response) -> Void in
            
            guard let self = self else {
                var json = [String : Any]()
                json["error"] = "sdk_error"
                json["error_description"] = "Unable to carry on"
                completion(json)
                return
            }
            
            switch response {
            case .follow(_):
                self.cleanUp()
                completion(self.convertNetworkErrorToDictionary(err: NetworkError.other("Unexpected status")))
            case .err(let error):
                self.cleanUp()
                completion(self.convertNetworkErrorToDictionary(err: error))
            case .dataOK(let connResp):
                self.cleanUp()
                completion(self.convertConnectionResponseToDictionary(resp: connResp))
            case .dataErr(let connResp):
                self.cleanUp()
                completion(self.convertConnectionResponseToDictionary(resp: connResp))
            }
        }
        //Initiating on the main thread to synch, as all connection update/state events will also be called on main thread
        DispatchQueue.main.async {
            self.startMonitoring()
            self.createTimer()
            self.activateConnectionForData(url: url, headers: headers, body: body, completion: self.checkResponseHandler)
        }
    }
    
    func createPostCommand(url: URL, headers: [String : Any], body: String?) -> String? {
        guard let host = url.host, let scheme = url.scheme  else {
            return nil
        }
        var path = url.path
        // the path method is stripping ending / so adding it back
        if (url.absoluteString.hasSuffix("/") && !url.path.hasSuffix("/")) {
            path += "/"
        }
        var cmd = String(format: "POST %@", path)
        
        if let q = url.query {
            cmd += String(format:"?%@", q)
        }
        
        cmd += String(format:" HTTP/1.1\r\nHost: %@", host)
        if (scheme.starts(with:"https") && url.port != nil && url.port != 443) {
            cmd += String(format:":%d", url.port!)
        } else if (scheme.starts(with:"http") && url.port != nil && url.port != 80) {
            cmd += String(format:":%d", url.port!)
        }
        for (key, value) in headers {
            cmd += "\r\n\(key): \(value)"
        }
        
        if let body = body {
            cmd += "\r\nContent-Length: \(body.count)"
            cmd += "\r\nConnection: close\r\n\r\n"
            cmd += "\(body)\r\n\r\n"
        } else {
            cmd += "\r\nContent-Length: 0"
            cmd += "\r\nConnection: close\r\n\r\n"
            
        }
        return cmd
    }
    
    func activateConnectionForData(url: URL, headers: [String : Any], body: String?, completion: @escaping ResultHandler) {
        self.cancelExistingConnection()
        guard let scheme = url.scheme,
              let host = url.host else {
            completion(.err(NetworkError.other("URL has no Host or Scheme")))
            return
        }
        
        guard let command = createPostCommand(url: url, headers: headers, body: body),
              let data = command.data(using: .utf8) else {
            completion(.err(NetworkError.other("Unable to create HTTP Request command")))
            return
        }
                
        connection = createConnection(scheme: scheme, host: host, port: url.port)
        if let connection = connection {
            connection.stateUpdateHandler = createConnectionUpdateHandler(completion: completion, readyStateHandler: { [weak self] in
                self?.sendAndReceiveWithBody(requestUrl: url, data: data, completion: completion)
            })
            // All connection events will be delivered on the main thread.
            connection.start(queue: .main)
        } else {
            os_log("Problem creating a connection ", url.absoluteString)
            completion(.err(NetworkError.connectionCantBeCreated("Problem creating a connection \(url.absoluteString)")))
        }
    }
    
    func sendAndReceiveWithBody(requestUrl: URL, data: Data, completion: @escaping ResultHandler) {
        connection?.send(content: data, completion: NWConnection.SendCompletion.contentProcessed({ (error) in
            if let err = error {
                os_log("Sending error %s", type: .error, err.localizedDescription)
                completion(.err(NetworkError.other(err.localizedDescription)))
                
            }
        }))
        
        timer?.invalidate()
        //Read the entire response body
        connection?.receiveMessage { data, context, isComplete, error in
            
            os_log("Receive isComplete: %s", isComplete.description)
            if let err = error {
                completion(.err(NetworkError.other(err.localizedDescription)))
                return
            }
            
            if let d = data, !d.isEmpty, let response = self.decodeResponse(data: d) {
                
                os_log("Response:\n %s", response)
                
                let status = self.parseHttpStatusCode(response: response)
                os_log("\n----\nHTTP status: %s", String(status))
                
                switch status {
                case 200...202:
                    if let r = self.getResponseBody(response: response) {
                        completion(.dataOK(ConnectionResponse(status: status, body: r)))
                    } else {
                        completion(.dataOK(ConnectionResponse(status: status, body: nil)))
                    }
                case 204:
                    completion(.dataOK(ConnectionResponse(status: status, body: nil)))
                case 301...399:
                    completion(.err(NetworkError.other("Unexpected HTTP Status \(status)")))
                case 400...451:
                    if let r = self.getResponseBody(response: response) {
                        completion(.dataErr(ConnectionResponse(status: status, body:r)))
                    } else {
                        completion(.err(NetworkError.other("Unexpected HTTP Status \(status)")))
                    }
                case 500...511:
                    if let r = self.getResponseBody(response: response) {
                        completion(.dataErr(ConnectionResponse(status: status, body:r)))
                    } else {
                        completion(.err(NetworkError.other("Unexpected HTTP Status \(status)")))
                    }
                default:
                    completion(.err(NetworkError.other("Unexpected HTTP Status \(status)")))
                }
            } else {
                completion(.err(NetworkError.other("Response has no data or corrupt")))
            }
        }
    }
}

protocol ConnectionManagerDelegate {
    func open(url: URL, accessToken: String?, operators: String?, completion: @escaping ([String : Any]) -> Void)
    func post(url: URL, headers: [String : Any], body: String?, completion: @escaping ([String : Any]) -> Void)
}

public struct RedirectResult {
    public var url: URL?
    public let cookies: [HTTPCookie]?
}

enum NetworkError: Error, Equatable {
    case invalidRedirectURL(String)
    case tooManyRedirects
    case connectionFailed(String)
    case connectionCantBeCreated(String)
    case other(String)
}


public struct ConnectionResponse {
    public var status: Int
    public let body: Data?
}

enum ConnectionResult {
    case err(NetworkError)
    case dataOK(ConnectionResponse)
    case dataErr(ConnectionResponse)
    case follow(RedirectResult)
}
