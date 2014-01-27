//
//  BWDelegatedLoggingMacros.h
//  CrashReporting
//
//  Created by Ant on 17/01/2014.
//

#import "BWDelegateLogger-Protocol.h"

// WARNING: Should only be included in implementation files

// Define several logging macros 'LOG_DEBUG', 'LOG_INFO', etc.
// When used in the context of a member method, these logging macros
// assume the existence of a member property 'delegate', pointing to
// a delegate conforming to the BWDelegateLogger Protocol

#undef LOG_DEBUG
#undef LOG_INFO
#undef LOG_WARN
#undef LOG_ERROR
#define _STRINGIFY(VALUE) #VALUE
#define STRINGIFY(VALUE) _STRINGIFY(VALUE)
static inline void _logAtLevel(id obj, BWLogLevel level, NSString *message)
{
    if ([obj respondsToSelector:@selector(delegate)] &&
        [[obj delegate] respondsToSelector:@selector(logAtLevel:message:)]) {
        [[obj delegate] logAtLevel:level message:message];
    }
}
#define LIBRARY_NAME QuincyKit
#ifdef DEBUG
#define LOG_DEBUG(_format, ...)                                                                    \
    _logAtLevel(                                                                                   \
            self, BW_LOG_LEVEL_DEBUG,                                                              \
            [NSString stringWithFormat:@"%s %s: %@", STRINGIFY(LIBRARY_NAME), __PRETTY_FUNCTION__, \
                                       [NSString stringWithFormat:_format, ##__VA_ARGS__]])
#else
#define LOG_DEBUG(_format, ...)
#endif
#define _LOG(_level, _prefix, _format, ...)                                                        \
    _logAtLevel(                                                                                   \
            self, _level,                                                                          \
            [@_prefix stringByAppendingString:[NSString stringWithFormat:_format, ##__VA_ARGS__]])
#define LOG_INFO(format, ...)                                                                      \
    _LOG(BW_LOG_LEVEL_INFO, STRINGIFY(LIBRARY_NAME) ": ", format, ##__VA_ARGS__)
#define LOG_WARN(format, ...)                                                                      \
    _LOG(BW_LOG_LEVEL_WARN, STRINGIFY(LIBRARY_NAME) ": ", format, ##__VA_ARGS__)
#define LOG_ERROR(format, ...)                                                                     \
    _LOG(BW_LOG_LEVEL_ERROR, STRINGIFY(LIBRARY_NAME) ": ", format, ##__VA_ARGS__)
