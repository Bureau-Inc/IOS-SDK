Bureau SDK for iOS
==========================================
## Integration
```Java
 - Drag and drop the BureauAuth.xcframework into the project
 - Verify the BureauAuth.xcframework is included under frameworks,Libraries, and Embedded content(Under Targets) and Embed & Sign option is selected
 - import BureauAuthentication into the class where the framework is needed
 - In your info.plist file add this:
 
<key>NSAppTransportSecurity</key>
	<dict>
		<key>NSAllowsArbitraryLoads</key>
		<true/>
		<key>NSExceptionDomains</key>
		<dict>
			<key>mcext.zumigo.com</key>
			<dict>
				<key>NSExceptionAllowsInsecureHTTPLoads</key>
				<true/>
				<key>NSIncludesSubdomains</key>
				<true/>
			</dict>
			<key>passport.airtel.in</key>
			<dict>
				<key>NSExceptionAllowsInsecureHTTPLoads</key>
				<true/>
				<key>NSIncludesSubdomains</key>
				<true/>
			</dict>
			<key>partnerapi.jio.com</key>
			<dict>
                		<key>NSExceptionAllowsInsecureHTTPLoads</key>
                		<true/>
                		<key>NSIncludesSubdomains</key>
                		<true/>
            		</dict>
		</dict>
	</dict>
   
```
## SDK Initialization
```Java

let bureauObj = BureauAuth.Builder()
          .setClientId(clientId: "e72a4414-a416-4872-8eea-6b51d6cd96e1")
          .build()
            
     //Other Options in builder are
        //setTimeout - total timeout in seconds
        //setCallBackUrl
        //mode - sandbox and production
```

## Usage
```Java
let response = bureauObj.makeAuthCall(mobile: "", correlationId: "")

```

If makeAuthCall() method returns 'True' you can go ahead and wait for the callback from Bureau servers or poll the [userinfo API](https://docs.bureau.id/openapi/pin-point/tag/PinPoint/paths/~1userinfo/get/).
For an example SDK usage, please take a look [here](https://github.com/Bureau-Inc/IOS-SDK/tree/master/iOS%20SDK%20integration%20example)
## Minimum iOS Version
iOS 13.0
