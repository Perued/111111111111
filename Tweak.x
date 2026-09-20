#import <Foundation/Foundation.h>

// 1. 获取沙盒 Documents 目录路径
static NSString *getDocumentDirectory() {
    NSArray *paths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
    return paths.firstObject;
}

// 2. 配置文件和日志文件的具体路径
static NSString *getConfigFile() {
    return [getDocumentDirectory() stringByAppendingPathComponent:@"TargetDomains.json"];
}

static NSString *getLogFile() {
    return [getDocumentDirectory() stringByAppendingPathComponent:@"InterceptLog.txt"];
}

// 3. 写入拦截日志 (追加模式)
static void logInterceptedURL(NSString *urlStr) {
    NSString *logPath = getLogFile();
    
    // 格式化当前时间
    NSDateFormatter *formatter = [[NSDateFormatter alloc] init];
    [formatter setDateFormat:@"yyyy-MM-dd HH:mm:ss"];
    NSString *timeStr = [formatter stringFromDate:[NSDate date]];
    
    NSString *logMsg = [NSString stringWithFormat:@"[%@] 成功拦截: %@\n", timeStr, urlStr];
    
    // 如果日志文件不存在，先创建
    if (![[NSFileManager defaultManager] fileExistsAtPath:logPath]) {
        [logMsg writeToFile:logPath atomically:YES encoding:NSUTF8StringEncoding error:nil];
    } else {
        // 追加写入
        NSFileHandle *handle = [NSFileHandle fileHandleForWritingAtPath:logPath];
        [handle seekToEndOfFile];
        [handle writeData:[logMsg dataUsingEncoding:NSUTF8StringEncoding]];
        [handle closeFile];
    }
}

// 4. 读取 JSON 配置文件中的动态域名列表
static NSArray* getDynamicDomains() {
    NSString *configPath = getConfigFile();
    NSData *data = [NSData dataWithContentsOfFile:configPath];
    if (data) {
        NSDictionary *dict = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
        if (dict && [dict isKindOfClass:[NSDictionary class]]) {
            NSArray *domains = dict[@"domains"];
            if ([domains isKindOfClass:[NSArray class]]) {
                return domains;
            }
        }
    }
    return @[];
}
// ==========================================
// 可变请求层 (NSMutableURLRequest)
// ==========================================
%hook NSMutableURLRequest

- (void)setURL:(NSURL *)URL {
    if (URL) {
        NSString *urlStr = URL.absoluteString;
        
        // 【新增】1. 动态配置文件拦截逻辑
        BOOL isDynamicIntercepted = NO;
        NSArray *dynamicDomains = getDynamicDomains();
        for (NSString *domain in dynamicDomains) {
            // 如果读取到的域名不是空，且当前 URL 包含了这个域名
            if (domain.length > 0 && [urlStr containsString:domain]) {
                // 记录到日志文件
                logInterceptedURL(urlStr);
                // 路由到特定黑洞
                URL = [NSURL URLWithString:@"http://127.0.0.1/blackhole_dynamic_custom"];
                isDynamicIntercepted = YES;
                break; // 拦截成功，跳出循环
            }
        }
        
        // 2. 如果没有被动态拦截，走原本的逻辑
        if (!isDynamicIntercepted) {
            if ([urlStr containsString:@"dda_gray_page_control"] || [urlStr containsString:@"gray_page_control"]) {
                URL = [NSURL URLWithString:@"http://127.0.0.1/blackhole_investigate"];
            } else if ([urlStr containsString:@"log.imdada"] || [urlStr containsString:@"apm"] || [urlStr containsString:@"crash"] || [urlStr containsString:@"trace"]) {
                URL = [NSURL URLWithString:@"http://127.0.0.1/blackhole_apm"];
            } else if ([urlStr containsString:@"color.imdada.cn"]) {
                NSError *error = nil;
                NSRegularExpression *regex = [NSRegularExpression regularExpressionWithPattern:@"([?&])(?:eid|sign|hdid)=[^&]*" 
                                                                                       options:NSRegularExpressionCaseInsensitive 
                                                                                         error:&error];
                if (!error) {
                    urlStr = [regex stringByReplacingMatchesInString:urlStr options:0 range:NSMakeRange(0, urlStr.length) withTemplate:@"$1"];
                    urlStr = [urlStr stringByReplacingOccurrencesOfString:@"&&" withString:@"&"];
                    urlStr = [urlStr stringByReplacingOccurrencesOfString:@"?&" withString:@"?"];
                    if ([urlStr hasSuffix:@"?"] || [urlStr hasSuffix:@"&"]) {
                        urlStr = [urlStr substringToIndex:urlStr.length - 1];
                    }
                    URL = [NSURL URLWithString:urlStr];
                }
            }
        }
    }
    %orig(URL);
}

%end
// 5. 初始化：如果配置不存在，生成默认配置模板
%ctor {
    NSString *configPath = getConfigFile();
    NSFileManager *fm = [NSFileManager defaultManager];
    if (![fm fileExistsAtPath:configPath]) {
        // 默认模板，你可以随意加
        NSDictionary *defaultConfig = @{
            @"domains": @[
                @"test-ad-domain.com",
                @"example-track.cn"
            ]
        };
        NSData *jsonData = [NSJSONSerialization dataWithJSONObject:defaultConfig options:NSJSONWritingPrettyPrinted error:nil];
        [jsonData writeToFile:configPath atomically:YES];
    }
}
