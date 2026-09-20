#import <Foundation/Foundation.h>
#import <objc/runtime.h>


#pragma mark -
#pragma mark 配置管理


@interface DadaBlockManager : NSObject

@property(nonatomic,strong) NSMutableArray *domains;

+ (instancetype)shared;
- (BOOL)isBlocked:(NSString *)host;
- (void)writeLog:(NSString *)text;

@end


@implementation DadaBlockManager


+ (instancetype)shared {

    static DadaBlockManager *m;
    static dispatch_once_t once;

    dispatch_once(&once,^{
        m=[DadaBlockManager new];
        [m loadConfig];
    });

    return m;
}


- (NSString *)configPath {

    NSString *dir =
    [NSHomeDirectory()
     stringByAppendingPathComponent:
     @"Documents/DadaBlock"];

    if(![[NSFileManager defaultManager]
         fileExistsAtPath:dir]){

        [[NSFileManager defaultManager]
         createDirectoryAtPath:dir
         withIntermediateDirectories:YES
         attributes:nil
         error:nil];
    }


    return [dir stringByAppendingPathComponent:
            @"BlockDomains.json"];
}



- (NSString *)logPath {

    NSString *dir =
    [NSHomeDirectory()
     stringByAppendingPathComponent:
     @"Documents/DadaBlock"];

    return [dir stringByAppendingPathComponent:
            @"BlockLog.txt"];
}




-(void)loadConfig {


    NSString *path=[self configPath];


    if(![[NSFileManager defaultManager]
        fileExistsAtPath:path]){


        NSDictionary *defaultConfig=@{
            @"enable":@YES,
            @"domains":@[
                @"color.imdada.cn",
                @"config.imdada.cn",
                @"log-dada.imdada.cn",
                @"saturn.jd.com",
                @"blackhole.m.jd.com"
            ]
        };


        NSData *data=
        [NSJSONSerialization
         dataWithJSONObject:defaultConfig
         options:NSJSONWritingPrettyPrinted
         error:nil];


        [data writeToFile:path atomically:YES];

    }



    NSData *data=
    [NSData dataWithContentsOfFile:path];


    NSDictionary *json=
    [NSJSONSerialization
     JSONObjectWithData:data
     options:0
     error:nil];


    self.domains=
    [json[@"domains"] mutableCopy];


    NSLog(@"[DadaBlock] domains=%@",self.domains);
}



-(BOOL)isBlocked:(NSString *)host {


    if(host.length==0)
        return NO;


    for(NSString *domain in self.domains){


        if([host.lowercaseString
            containsString:
            domain.lowercaseString]){


            return YES;
        }
    }


    return NO;
}



-(void)writeLog:(NSString *)text {


    NSString *old=
    [NSString stringWithContentsOfFile:
     [self logPath]
     encoding:NSUTF8StringEncoding];


    NSString *new=
    [NSString stringWithFormat:@"%@\n%@",
     old ?: @"",
     text];


    [new writeToFile:
     [self logPath]
     atomically:YES
     encoding:NSUTF8StringEncoding
     error:nil];

}


@end



#pragma mark -
#pragma mark NSURLSession


%hook NSURLSession


- (NSURLSessionDataTask *)
dataTaskWithRequest:(NSURLRequest *)request
completionHandler:(void (^)(NSData *,
NSURLResponse *,
NSError *))completionHandler
{


    NSString *host=request.URL.host;


    if([[DadaBlockManager shared]
        isBlocked:host]){


        NSLog(@"[DadaBlock] BLOCK %@",host);


        [[DadaBlockManager shared]
         writeLog:
         [NSString stringWithFormat:
          @"BLOCK NSURLSession %@",
          host]];


        NSError *err=
        [NSError errorWithDomain:
         @"DadaBlock"
         code:-999
         userInfo:@{
            NSLocalizedDescriptionKey:
            @"Blocked by DadaBlock"
         }];


        if(completionHandler){

            completionHandler(nil,nil,err);
        }


        return nil;

    }



    return %orig;

}


%end



#pragma mark -
#pragma mark HTTPDNS拦截


%hook NSURLSession


- (NSURLSessionDataTask *)
dataTaskWithURL:(NSURL *)url
completionHandler:(void (^)(NSData *,
NSURLResponse *,
NSError *))completionHandler{


    if([url.host containsString:@"dns.jd.com"]){


        NSLog(@"[DadaBlock] HTTPDNS %@",url);


        [[DadaBlockManager shared]
         writeLog:
         [NSString stringWithFormat:
          @"HTTPDNS %@",
          url]];

    }


    return %orig;

}


%end



#pragma mark -
#pragma mark 注入启动


%ctor {


    NSLog(@"=================");
    NSLog(@"DadaBlock Loaded");
    NSLog(@"Home=%@",NSHomeDirectory());
    NSLog(@"=================");


    [DadaBlockManager shared];

}
