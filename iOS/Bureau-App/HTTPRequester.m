#import "HTTPRequester.h"
#import "SocketAddress.h"
#import "sslfuncs.h"
#import <Foundation/Foundation.h>
#import <ifaddrs.h>
#import <net/if.h>
#import <netdb.h>
#include <arpa/inet.h>
#import <Network/Network.h>

@implementation HTTPRequester

#define IOS_CELLULAR    @"pdp_ip0"
#define IOS_WIFI        @"en0"
#define IP_ADDR_IPv4    @"ipv4"
#define IP_ADDR_IPv6    @"ipv6"


//+ (NSString *)performGetRequest:(NSURL *)url withCookies:(NSString *)cookies {
+ (NSString *)performGetRequest:(NSURL *)url {
 
    // Stores any errors that occur during execution
    OSStatus status;
    
    // All local (cellular interface) IP addresses of this device.
    NSMutableArray<SocketAddress *> *localAddresses = [NSMutableArray array];
    // All remote IP addresses that we're trying to connect to.
    NSMutableArray<SocketAddress *> *remoteAddresses = [NSMutableArray array];
    
    // The local (cellular interface) IP address of this device.
    SocketAddress *localAddress;
    // The remote IP address that we're trying to connect to.
    SocketAddress *remoteAddress;
    
    NSPredicate *ipv4Predicate = [NSPredicate predicateWithBlock:^BOOL(SocketAddress *evaluatedObject, NSDictionary<NSString *, id> *bindings) {
        return evaluatedObject.sockaddr->sa_family == AF_INET;
    }];
    NSPredicate *ipv6Predicate = [NSPredicate predicateWithBlock:^BOOL(SocketAddress *evaluatedObject, NSDictionary<NSString *, id> *bindings) {
        return evaluatedObject.sockaddr->sa_family == AF_INET6;
    }];
    
    struct ifaddrs *ifaddrPointer;
    struct ifaddrs *ifaddrs;
    
    status = getifaddrs(&ifaddrPointer);
    if (status) {
        return nil;
    }
    
    ifaddrs = ifaddrPointer;
    while (ifaddrs) {
        // If the interface is up
        if (ifaddrs->ifa_flags & IFF_UP) {
            // If the interface is the pdp_ip0 (cellular) interface
            if (strcmp(ifaddrs->ifa_name, "pdp_ip0") == 0) {
                switch (ifaddrs->ifa_addr->sa_family) {
                    case AF_INET:  // IPv4
                    case AF_INET6: // IPv6
                        [localAddresses addObject:[[SocketAddress alloc] initWithSockaddr:ifaddrs->ifa_addr]];
                        break;
                }
            }
        }
        ifaddrs = ifaddrs->ifa_next;
    }
    
    struct addrinfo *addrinfoPointer;
    struct addrinfo *addrinfo;
    
    // Generate "hints" for the DNS lookup (namely, search for both IPv4 and
    // IPv6 addresses)
    struct addrinfo hints;
    memset(&hints, 0, sizeof(hints));
    hints.ai_family = AF_UNSPEC;
    hints.ai_socktype = SOCK_STREAM;
    
    const char* service = [[url scheme] UTF8String];
    
    if(url.port) {
        NSString *portString = [NSString stringWithFormat: @"%@", [url port]];
        service = [portString UTF8String];
    }
    
    status = getaddrinfo([[url host] UTF8String], service, &hints, &addrinfoPointer);
    if (status) {
        freeifaddrs(ifaddrPointer);
        NSString *toReturn = @"ERROR: CANNOT FIND REMOTE ADDRESS";
        return toReturn;
    }
    
    addrinfo = addrinfoPointer;
    
    while (addrinfo) {
        switch (addrinfo->ai_addr->sa_family) {
            case AF_INET:  // IPv4
            case AF_INET6: // IPv6
                [remoteAddresses addObject:[[SocketAddress alloc] initWithSockaddr:addrinfo->ai_addr]];
                break;
        }
        addrinfo = addrinfo->ai_next;
    }
    
    if ((localAddress = [[localAddresses filteredArrayUsingPredicate:ipv6Predicate] lastObject]) && (remoteAddress = [[remoteAddresses filteredArrayUsingPredicate:ipv6Predicate] lastObject])) {
        // Select the IPv6 route, if possible
    }
    else if ((localAddress = [[localAddresses filteredArrayUsingPredicate:ipv4Predicate] lastObject]) && (remoteAddress = [[remoteAddresses filteredArrayUsingPredicate:ipv4Predicate] lastObject])) {
        // Select the IPv4 route, if possible (and no IPv6 route is available)
    }
    else {                                                                                                                                                                                             // No route found, abort
        freeaddrinfo(addrinfoPointer);
        NSString *toReturn = @"ERROR: NO ROUTES FOUND";
        return toReturn;
    }
    
    // Create a new socket
    int sock = socket(localAddress.sockaddr->sa_family, SOCK_STREAM, 0);
    if(sock == -1) {
        NSString *toReturn = @"ERROR: CANNOT CREATE SOCKET";
        return toReturn;
    }
    
    NSLog (@"Local addresses = %@", localAddresses);
    NSLog (@"Remote addresses = %@", remoteAddresses);
    NSLog (@"Local address = %@", localAddress);
    NSLog (@"Remote address = %@", remoteAddress);
    
    // Bind the socket to the local address
    bind(sock, localAddress.sockaddr, localAddress.size);
    
    // Connect to the remote address using the socket
    status = connect(sock, remoteAddress.sockaddr, remoteAddress.size);
    if (status) {
        freeaddrinfo(addrinfoPointer);
        NSString *toReturn =  @"ERROR: CANNOT CONNECT SOCKET TO REMOTE ADDRESS";
        return toReturn;
    }
    
    NSString *requestString = [NSString stringWithFormat:@"GET %@%@ HTTP/1.1\r\nHost: %@%@\r\n", [url path], [url query] ? [@"?" stringByAppendingString:[url query]] : @"", [url host], [url port] ? [@":" stringByAppendingFormat:@"%@", [url port]] : @""];
    
    requestString = [requestString stringByAppendingString:@"Connection: close\r\n\r\n"];
   
    const char* request = [requestString UTF8String];

    char buffer[4096];
    
    if ([[url scheme] isEqualToString:@"http"]) {
        write(sock, request, strlen(request));
        
        int received = 0;
        int total = sizeof(buffer)-1;
        do {
            int bytes = (int)read(sock, buffer+received, total-received);
            if (bytes < 0) {
                NSString *toReturn = @"ERROR: PROBLEM READING RESPONSE";
                return toReturn;
            } else if(bytes==0) {
                break;
            }
            
            received += bytes;
        } while (received < total);
    
    } else {
        #pragma clang diagnostic push
        #pragma clang diagnostic ignored "-Wdeprecated-declarations"
        if(@available (*, iOS 13.0)) {
            
            OSStatus status;
            // Setup SSL
            SSLContextRef context = SSLCreateContext(kCFAllocatorDefault, kSSLClientSide, kSSLStreamType);
            
            status = SSLSetIOFuncs(context, ssl_read, ssl_write);
            if (status) {
                SSLClose(context);
                CFRelease(context);
                NSString *toReturn = @"ERROR: SSL1";
                return toReturn;
            }
            
            status = SSLSetConnection(context, (SSLConnectionRef)&sock);
            if (status) {
                SSLClose(context);
                CFRelease(context);
                NSString *toReturn = @"ERROR: SSL2";
                return toReturn;
            }
            
            status = SSLSetPeerDomainName(context, [[url host] UTF8String], strlen([[url host] UTF8String]));
            if (status) {
                SSLClose(context);
                CFRelease(context);
                NSString *toReturn = @"ERROR: SSL3";
                return toReturn;
            }
            
            // Repeat this until it doesn't error out
            do {
                status = SSLHandshake(context);
            } while (status == errSSLWouldBlock);
            if (status) {
                SSLClose(context);
                CFRelease(context);
                NSString *toReturn = @"ERROR: SSL4";
                return toReturn;
            }
            
            size_t processed = 0;
            status = SSLWrite(context, request, strlen(request), &processed);
            if (status) {
                SSLClose(context);
                CFRelease(context);
                NSString *toReturn = @"ERROR: SSL5";
                return toReturn;
            }
            
            do {
                status = SSLRead(context, buffer, sizeof(buffer) - 1, &processed);
                buffer[processed] = 0;
                
                // If the buffer was filled, then continue reading
                if (processed == sizeof(buffer) - 1) {
                    status = errSSLWouldBlock;
                }
            } while (status == errSSLWouldBlock);
            
            if (status && status != errSSLClosedGraceful) {
                SSLClose(context);
                CFRelease(context);
                NSString *toReturn = @"ERROR: SSL6";
                
                return toReturn;
            }
        }
        #pragma clang diagnostic pop
        
        if(@available (iOS 13.0, *)) {
            //TODO: Please add code from Network.framework if needed. FYI i am getting silent auth message for iOS 13+ as well.
        }
    }
    
    NSString *response = [[NSString alloc] initWithBytes:buffer length:sizeof(buffer) encoding:NSASCIIStringEncoding];
  
    if ([response rangeOfString:@"HTTP/"].location == NSNotFound) {
        NSString *toReturn = @"ERROR: Done";
        return toReturn;
    }
    
    NSUInteger prefixLocation = [response rangeOfString:@"HTTP/"].location + 9;
    
    NSRange toReturnRange = NSMakeRange(prefixLocation, 1);
    
    NSString* urlResponseCode = [response substringWithRange:toReturnRange];
    
    if ([urlResponseCode isEqualToString:@"3"]) {
        NSRegularExpression *regex = [NSRegularExpression regularExpressionWithPattern:@"Location: (.*)\r\n" options:NSRegularExpressionCaseInsensitive error:NULL];
        
        NSArray *myArray = [regex matchesInString:response options:0 range:NSMakeRange(0, [response length])] ;
        
        NSString* redirectLink = @"";
        
        for (NSTextCheckingResult *match in myArray) {
            NSRange matchRange = [match rangeAtIndex:1];
            redirectLink = [response substringWithRange:matchRange];
        }
        
        response = @"REDIRECT:";
        response = [response stringByAppendingString:redirectLink];
    }

    return response;
}

+(NSString *)getIPAddress
{
    NSArray *searchArray = @[ IOS_WIFI @"/" IP_ADDR_IPv4, IOS_WIFI @"/" IP_ADDR_IPv6, IOS_CELLULAR @"/" IP_ADDR_IPv4, IOS_CELLULAR @"/" IP_ADDR_IPv6 ];
    
    NSDictionary *addresses = [self getIPAddresses];
    NSLog(@"addresses: %@", addresses);

    __block NSString *address;
    [searchArray enumerateObjectsUsingBlock:^(NSString *key, NSUInteger idx, BOOL *stop)
        {
            address = addresses[key];
            if(address) *stop = YES;
        } ];
    return address ? address : @"0.0.0.0";
}

+(NSDictionary *)getIPAddresses
{
    NSMutableDictionary *addresses = [NSMutableDictionary dictionaryWithCapacity:8];

    // retrieve the current interfaces - returns 0 on success
    struct ifaddrs *interfaces;
    if(!getifaddrs(&interfaces)) {
        // Loop through linked list of interfaces
        struct ifaddrs *interface;
        for(interface=interfaces; interface; interface=interface->ifa_next) {
            if(!(interface->ifa_flags & IFF_UP) /* || (interface->ifa_flags & IFF_LOOPBACK) */ ) {
                continue; // deeply nested code harder to read
            }
            const struct sockaddr_in *addr = (const struct sockaddr_in*)interface->ifa_addr;
            char addrBuf[ MAX(INET_ADDRSTRLEN, INET6_ADDRSTRLEN) ];
            if(addr && (addr->sin_family==AF_INET || addr->sin_family==AF_INET6)) {
                NSString *name = [NSString stringWithUTF8String:interface->ifa_name];
                NSString *type;
                if(addr->sin_family == AF_INET) {
                    if(inet_ntop(AF_INET, &addr->sin_addr, addrBuf, INET_ADDRSTRLEN)) {
                        type = IP_ADDR_IPv4;
                    }
                } else {
                    const struct sockaddr_in6 *addr6 = (const struct sockaddr_in6*)interface->ifa_addr;
                    if(inet_ntop(AF_INET6, &addr6->sin6_addr, addrBuf, INET6_ADDRSTRLEN)) {
                        type = IP_ADDR_IPv6;
                    }
                }
                if(type) {
                    NSString *key = [NSString stringWithFormat:@"%@/%@", name, type];
                    addresses[key] = [NSString stringWithUTF8String:addrBuf];
                }
            }
        }
        // Free memory
        freeifaddrs(interfaces);
    }
    return [addresses count] ? addresses : nil;
}

@end
