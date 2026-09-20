#import <Foundation/Foundation.h>

// ==========================================
// 1. 文件路径获取
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
    
    NSString *logMsg = [NSString stringWithFormat:@"[%@] 动态拦截: %@\n", timeStr, urlStr];
    
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
// 3. 集中式 URL 处理器 (所有拦截逻辑都在这里)
// ==========================================
static NSURL* processAndCleanURL(NSURL *originalURL) {
    if (!originalURL) return originalURL;
    NSString *urlStr = originalURL.absoluteString;
    if (urlStr.length == 0) return originalURL;
    
    // 【第一关：读取 Plist，动态拦截特定域名】
    NSDictionary *config = [NSDictionary dictionaryWithContentsOfFile:getConfigPlistPath()];
    if (config) {
        NSArray *domains = config[@"TargetDomains"];
        BOOL enableLogging = [config[@"EnableLogging"] boolValue]; // 读取日志开关
        
        if ([domains isKindOfClass:[NSArray class]]) {
            for (NSString *domain in domains) {
                if (domain.length > 0 && [urlStr containsString:domain]) {
                    // 如果开启了日志记录，才写入日志
                    if (enableLogging) {
                        writeToLogFile(urlStr);
                    }
                    return [NSURL URLWithString:@"http://127.0.0.1/blackhole_dynamic_plist"];
                }
            }
        }
    }
    


// ==========================================
// 4. 插件初始化：如果配置不存在，自动生成 Plist
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
// 5. Hooks: 极简拦截器 (直接调用上方处理器)
// ==========================================

%hook NSMutableURLRequest
- (void)setURL:(NSURL *)URL {
    %orig(processAndCleanURL(URL));
}
%end

%hook NSURLRequest
+ (instancetype)requestWithURL:(NSURL *)URL {
    return %orig(processAndCleanURL(URL));
}
- (instancetype)initWithURL:(NSURL *)URL {
    return %orig(processAndCleanURL(URL));
}
- (instancetype)initWithURL:(NSURL *)URL cachePolicy:(NSURLRequestCachePolicy)cachePolicy timeoutInterval:(NSTimeInterval)timeoutInterval {
    return %orig(processAndCleanURL(URL), cachePolicy, timeoutInterval);
}
%end

