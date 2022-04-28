#ifndef HTTPRequester_h
#define HTTPRequester_h

#import <Foundation/Foundation.h>
#import "SocketAddress.h"
#import "sslfuncs.h"

@interface HTTPRequester : NSObject
+ (NSString *)performGetRequest:(NSURL *)url;
+ (NSString *)getIPAddress;
@end

#endif /* HTTPRequester_h */
