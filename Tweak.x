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
// 2. 通用日志写入模块
// ==========================================
static void writeLog(NSString *msg) {
    NSString *logPath = getLogFilePath();
    
    NSDateFormatter *formatter = [[NSDateFormatter alloc] init];
    [formatter setDateFormat:@"yyyy-MM-dd HH:mm:ss"];
    NSString *timeStr = [formatter stringFromDate:[NSDate date]];
    
    NSString *logMsg = [NSString stringWithFormat:@"[%@] %@\n", timeStr, msg];
    
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
// 3. 核心拦截器 (Plist 配置匹配)
// ==========================================
static NSURL* processURL(NSURL *originalURL) {
    if (!originalURL) return originalURL;
    NSString *urlStr = originalURL.absoluteString;
    if (urlStr.length == 0) return originalURL;
    
    NSDictionary *config = [NSDictionary dictionaryWithContentsOfFile:getConfigPlistPath()];
    if (config) {
        NSArray *domains = config[@"TargetDomains"];
        BOOL enableLogging = [config[@"EnableLogging"] boolValue]; 
        
        if ([domains isKindOfClass:[NSArray class]]) {
            for (NSString *domain in domains) {
                if (domain.length > 0 && [urlStr containsString:domain]) {
                    if (enableLogging) {
                        writeLog([NSString stringWithFormat:@"域名拦截: %@", urlStr]);
                    }
                    return [NSURL URLWithString:@"http://127.0.0.1/blackhole_dynamic_plist"];
                }
            }
        }
    }
    return originalURL;
}

// ==========================================
// 4. 插件初始化：自动生成默认 Plist
// ==========================================
%ctor {
    NSString *plistPath = getConfigPlistPath();
    if (![[NSFileManager defaultManager] fileExistsAtPath:plistPath]) {
        NSDictionary *defaultConfig = @{
            @"EnableLogging": @(YES),
            @"TargetDomains": @[
                @"ddk_transporterinfo_updateCoordinator_v1"
            ]
        };
        [defaultConfig writeToFile:plistPath atomically:YES];
    }
}

// ==========================================
// 5. 网络请求 Hook 层 (基于 URL 拦截)
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

// ==========================================
// 6. JSON 数据篡改层 (解除越狱封杀令)
// ==========================================
%hook NSJSONSerialization

+ (id)JSONObjectWithData:(NSData *)data options:(NSJSONReadingOptions)opt error:(NSError **)error {
    id result = %orig(data, opt, error);

    // 层层校验，防止崩溃
    if (![result isKindOfClass:[NSDictionary class]]) return result;
    NSDictionary *dict = (NSDictionary *)result;
    
    NSDictionary *content = dict[@"content"];
    if (![content isKindOfClass:[NSDictionary class]]) return result;

    NSArray *resultArray = content[@"result"];
    if (![resultArray isKindOfClass:[NSArray class]]) return result;

    // 扫描是否包含越狱风控下发指令
    BOOL hitTarget = NO;
    for (NSDictionary *item in resultArray) {
        if ([item isKindOfClass:[NSDictionary class]]) {
            NSString *name = item[@"paramName"];
            if ([name isEqualToString:@"ForbiddenJailBroken"] || [name isEqualToString:@"forceUnRoot"]) {
                hitTarget = YES;
                break;
            }
        }
    }

    // 开始做手术篡改
    if (hitTarget) {
        NSDictionary *config = [NSDictionary dictionaryWithContentsOfFile:getConfigPlistPath()];
        BOOL enableLogging = [config[@"EnableLogging"] boolValue];

        @try {
            NSMutableDictionary *mutDict = [dict mutableCopy];
            NSMutableDictionary *mutContent = [content mutableCopy];
            NSMutableArray *mutArray = [NSMutableArray array];
            
            int modifiedCount = 0;

            for (NSDictionary *item in resultArray) {
                if ([item isKindOfClass:[NSDictionary class]]) {
                    NSMutableDictionary *mutItem = [item mutableCopy];
                    NSString *name = mutItem[@"paramName"];

                    if ([name isEqualToString:@"ForbiddenJailBroken"]) {
                        mutItem[@"paramValue"] = @"0"; 
                        modifiedCount++;
                    } else if ([name isEqualToString:@"forceUnRoot"]) {
                        mutItem[@"paramValue"] = @"0";
                        modifiedCount++;
                    } else if ([name isEqualToString:@"DDJailBrokenMonterAppName"]) {
                        mutItem[@"paramValue"] = @"com.fake.app.nothing";
                        modifiedCount++;
                    }
                    [mutArray addObject:mutItem];
                } else {
                    [mutArray addObject:item];
                }
            }

            mutContent[@"result"] = mutArray;
            mutDict[@"content"] = mutContent;

            if (enableLogging) {
                writeLog([NSString stringWithFormat:@"✅ JSON篡改成功: 抹除了 %d 个越狱封杀指令", modifiedCount]);
            }
            return mutDict;

        } @catch (NSException *exception) {
            // 如果篡改过程发生字典/数组类型越界等错误，记录失败日志并原样返回
            if (enableLogging) {
                writeLog([NSString stringWithFormat:@"❌ JSON篡改失败: 发生异常 %@", exception.reason]);
            }
            return result;
        }
    }

    return result;
}

%end
