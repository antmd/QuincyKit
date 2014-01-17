//
//  BWDelegateLogger-Protocol.h
//  CrashReporting
//
//  Created by Ant on 17/01/2014.
//  Copyright (c) 2014 dervishsoftware. All rights reserved.
//

typedef NS_ENUM(NSUInteger, BWLogLevel) {
    BW_LOG_LEVEL_DEBUG
    , BW_LOG_LEVEL_INFO
    , BW_LOG_LEVEL_WARN
    , BW_LOG_LEVEL_ERROR
    
};

// The CrashManager delegate should implement 'logAtLevel:message:' to do
// logging for the CrashManager
@protocol BWDelegateLogger <NSObject>
@optional
-(void)logAtLevel:(BWLogLevel)level message:(NSString*)message;
@end

@interface NSObject (BWDelegate)
-(id)delegate;
@end
