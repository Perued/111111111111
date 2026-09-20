#import <Foundation/Foundation.h>

// ==========================================
// 1. 获取沙盒路径 (配置文件与日志文件)
// ==========================================
static NSString *getConfigPlistPath() {
    NSString *docDir = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES).firstObject;
    return [docDir stringByAppendingPathComponent:@"InterceptConfig.plist"];
}

static NSString *getLogFilePath() {
    NSString *docDir = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES).firstObject;
    return [docDir stringByAppendingPathComponent:@"InterceptLog.txt"];
}

// ==========================================
// 2. 日志写入模块
// ==========================================
static void writeToLogFile(NSString *urlStr) {
    NSString *logPath = getLogFilePath();
    
    NSDateFormatter *formatter = [[NSDateFormatter alloc] init];
    [formatter setDateFormat:@"yyyy-MM-dd HH:mm:ss"];
    NSString *timeStr = [formatter stringFromDate:[NSDate date]];
    
    NSString *logMsg = [NSString stringWithFormat:@"[%@] 拦截触发: %@\n", timeStr, urlStr];
    
    if (![[NSFileManager defaultManager] fileExistsAtPath:logPath]) {
        [logMsg writeToFile:logPath atomically:YES encoding:NSUTF8StringEncoding error:nil];
    } else {
        NSFileHandle *handle = [NSFileHandle fileHandleForWritingAtPath:logPath];
        [handle seekToEndOfFile];
        [handle writeData:[logMsg dataUsingEncoding:NSUTF8StringEncoding]];
        [handle closeFile];
    }
}

// ==========================================
// 3. 核心拦截器 (仅保留 Plist 配置匹配)
// ==========================================
static NSURL* processURL(NSURL *originalURL) {
    if (!originalURL) return originalURL;
    NSString *urlStr = originalURL.absoluteString;
    if (urlStr.length == 0) return originalURL;
    
    // 读取 Plist 配置文件
    NSDictionary *config = [NSDictionary dictionaryWithContentsOfFile:getConfigPlistPath()];
    if (config) {
        NSArray *domains = config[@"TargetDomains"];
        BOOL enableLogging = [config[@"EnableLogging"] boolValue]; // 读取日志开关
        
        if ([domains isKindOfClass:[NSArray class]]) {
            for (NSString *domain in domains) {
                // 如果当前 URL 包含了 Plist 中配置的任意域名/关键字
                if (domain.length > 0 && [urlStr containsString:domain]) {
                    // 如果开关开启，则记录日志
                    if (enableLogging) {
                        writeToLogFile(urlStr);
                    }
                    // 命中拦截，导向黑洞
                    return [NSURL URLWithString:@"http://127.0.0.1/blackhole_dynamic_plist"];
                }
            }
        }
    }
    
    // 未命中拦截列表，放行原请求
    return originalURL;
}

// ==========================================
// 4. 插件初始化：自动生成默认 Plist
// ==========================================
%ctor {
    NSString *plistPath = getConfigPlistPath();
    if (![[NSFileManager defaultManager] fileExistsAtPath:plistPath]) {
        NSDictionary *defaultConfig = @{
            @"EnableLogging": @(YES),  // 默认打开日志记录
            @"TargetDomains": @[
                @"test-ad-domain.com",
                @"example-track.cn"
            ]
        };
        [defaultConfig writeToFile:plistPath atomically:YES];
    }
}

// ==========================================
// 5. 网络请求 Hook 层
// ==========================================

%hook NSMutableURLRequest
- (void)setURL:(NSURL *)URL {
    %orig(processURL(URL));
}
%end

%hook NSURLRequest
+ (instancetype)requestWithURL:(NSURL *)URL {
    return %orig(processURL(URL));
}
- (instancetype)initWithURL:(NSURL *)URL {
    return %orig(processURL(URL));
}
- (instancetype)initWithURL:(NSURL *)URL cachePolicy:(NSURLRequestCachePolicy)cachePolicy timeoutInterval:(NSTimeInterval)timeoutInterval {
    return %orig(processURL(URL), cachePolicy, timeoutInterval);
}
%end
