#import <Foundation/Foundation.h>
#import <objc/runtime.h>


@interface DadaBlockManager : NSObject

@property(nonatomic,strong) NSMutableArray *domains;

+ (instancetype)shared;

- (BOOL)isBlocked:(NSString *)host;

- (void)writeLog:(NSString *)text;

@end



@implementation DadaBlockManager


+ (instancetype)shared
{
    static DadaBlockManager *manager;

    static dispatch_once_t onceToken;

    dispatch_once(&onceToken, ^{
        manager = [[self alloc] init];
        [manager loadConfig];
    });

    return manager;
}



#pragma mark - 路径


- (NSString *)basePath
{
    NSString *path =
    [NSHomeDirectory()
     stringByAppendingPathComponent:
     @"Documents/DadaBlock"];


    if (![[NSFileManager defaultManager]
          fileExistsAtPath:path])
    {

        [[NSFileManager defaultManager]
         createDirectoryAtPath:path
         withIntermediateDirectories:YES
         attributes:nil
         error:nil];
    }


    return path;
}



- (NSString *)configPath
{
    return [[self basePath]
            stringByAppendingPathComponent:
            @"BlockConfig.plist"];
}



- (NSString *)logPath
{
    return [[self basePath]
            stringByAppendingPathComponent:
            @"BlockLog.txt"];
}



#pragma mark - 加载配置


- (void)loadConfig
{

    NSString *path = [self configPath];


    if (![[NSFileManager defaultManager]
          fileExistsAtPath:path])
    {


        NSDictionary *defaultConfig =
        @{
          @"Enable":@YES,

          @"Log":@YES,


          @"Domains":
              @[
                @"color.imdada.cn",

                @"config.imdada.cn",

                @"log-dada.imdada.cn",

                @"saturn.jd.com",

                @"blackhole.m.jd.com"
              ]
          };



        [defaultConfig writeToFile:path
                         atomically:YES];

    }



    NSDictionary *config =
    [NSDictionary dictionaryWithContentsOfFile:path];



    if ([config[@"Enable"] boolValue])
    {

        self.domains =
        [config[@"Domains"] mutableCopy];

    }
    else
    {

        self.domains =
        [NSMutableArray array];

    }



    NSLog(@"[DadaBlock] Loaded domains:%@",self.domains);

}



#pragma mark - 判断


- (BOOL)isBlocked:(NSString *)host
{

    if(host.length==0)
        return NO;



    for(NSString *domain in self.domains)
    {

        if([host.lowercaseString
            containsString:
            domain.lowercaseString])
        {

            return YES;

        }

    }


    return NO;

}



#pragma mark - 日志


- (void)writeLog:(NSString *)text
{

    NSString *old =
    [NSString stringWithContentsOfFile:
     [self logPath]
     encoding:NSUTF8StringEncoding
     error:nil];


    if(old==nil)
        old = @"";



    NSString *time =
    [NSDate date].description;



    NSString *new =
    [NSString stringWithFormat:
     @"%@\n[%@]\n%@\n",
     old,
     time,
     text];



    [new writeToFile:
     [self logPath]
     atomically:YES
     encoding:NSUTF8StringEncoding
     error:nil];

}



@end





#pragma mark -
#pragma mark NSURLSession Hook


%hook NSURLSession


- (NSURLSessionDataTask *)
dataTaskWithRequest:(NSURLRequest *)request
completionHandler:(void (^)(NSData *,
NSURLResponse *,
NSError *))completionHandler
{


    NSString *host =
    request.URL.host;



    if([[DadaBlockManager shared]
        isBlocked:host])
    {


        NSLog(@"[DadaBlock] BLOCK %@",host);



        [[DadaBlockManager shared]
         writeLog:
         [NSString stringWithFormat:
          @"BLOCK NSURLSession\nHOST:%@",
          host]];



        NSError *error =
        [NSError errorWithDomain:
         @"DadaBlock"
         code:-1
         userInfo:
         @{
          NSLocalizedDescriptionKey:
          @"Blocked"
         }];



        if(completionHandler)
        {
            completionHandler(nil,nil,error);
        }


        return nil;

    }



    return %orig;

}



%end





#pragma mark -
#pragma mark HTTPDNS记录


%hook NSURLSession



- (NSURLSessionDataTask *)
dataTaskWithURL:(NSURL *)url
completionHandler:(void (^)(NSData *,
NSURLResponse *,
NSError *))completionHandler
{


    if([url.host containsString:@"dns.jd.com"])
    {

        NSLog(@"[DadaBlock] HTTPDNS:%@",url.absoluteString);



        [[DadaBlockManager shared]
         writeLog:
         [NSString stringWithFormat:
          @"HTTPDNS REQUEST\n%@",
          url.absoluteString]];

    }



    return %orig;

}



%end






#pragma mark -
#pragma mark 启动


%ctor
{

    NSLog(@"=================");
    NSLog(@"DadaBlock Loaded");
    NSLog(@"Home:%@",NSHomeDirectory());
    NSLog(@"=================");



    [DadaBlockManager shared];

}
