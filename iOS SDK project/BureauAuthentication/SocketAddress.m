#import "SocketAddress.h"
#import <Foundation/Foundation.h>
#import <arpa/inet.h>
#import <netinet/in.h>
#import <sys/socket.h>

@implementation SocketAddress
- (instancetype)initWithSockaddr:(struct sockaddr *)sockaddr {
	self = [super init];
	self.sockaddr = sockaddr;
	return self;
}

- (socklen_t)size {
	switch (self.sockaddr->sa_family) {
	case AF_INET:
		return sizeof(struct sockaddr_in);
	case AF_INET6:
		return sizeof(struct sockaddr_in6);
	default:
		return 0;
	}
}

- (NSString *)description {
	NSString *family;
	NSString *address;
	int bufferSize = MAX(INET_ADDRSTRLEN, INET6_ADDRSTRLEN);
	char buffer[bufferSize];
	switch (self.sockaddr->sa_family) {
		case AF_INET:
			family = @"IPv4";
			address = [NSString stringWithUTF8String:inet_ntop(self.sockaddr->sa_family, &((struct sockaddr_in *)self.sockaddr)->sin_addr, buffer, bufferSize)];
			break;
		case AF_INET6:
			family = @"IPv6";
			address = [NSString stringWithUTF8String:inet_ntop(self.sockaddr->sa_family, &((struct sockaddr_in6 *)self.sockaddr)->sin6_addr, buffer, bufferSize)];
			break;
	}
	return [NSString stringWithFormat:@"%@ %@", family, address];
}
@end
