#import <CoreServices/CoreServices.h>
#import <Foundation/Foundation.h>
#import "fstree.h"

#include <getopt.h>

typedef enum
{
    ADD_FLAG = 1,
    MODIFY_FLAG = 2,
    DELETE_FLAG = 4
} watch_flags;

@interface ExecutionContext : NSObject<FileSystemChangesListener>
{
}

@property (retain) FSTree *tree;
@property (retain) NSMutableArray *addScripts;
@property (retain) NSMutableArray *modScripts;
@property (retain) NSMutableArray *delScripts;

- (void) addExecutable:(NSString *)executable flags:(NSUInteger)flags;

@end

@implementation ExecutionContext
@synthesize tree, addScripts, delScripts, modScripts;

+(void) launch:(NSString *)cmd args:(NSArray *)args
{
    NSTask *task = [[[NSTask alloc] init] autorelease];
    [task setLaunchPath: cmd];
    [task setArguments: args];
    [task launch];
}

- (id) init
{
    self = [super init];
    if (self)
    {
        self.tree = [[[FSTree alloc] initWithListener:self] autorelease];
        self.addScripts = [NSMutableArray array];
        self.modScripts = [NSMutableArray array];
        self.delScripts = [NSMutableArray array];
    }
    return self;
}

- (void) dealloc
{
    self.tree = nil;
    self.addScripts = nil;
    self.delScripts = nil;
    self.modScripts = nil;
    [super dealloc];
}

- (void) addPath:(NSString *)path
{
    [self.tree addPath:path];
}

- (NSArray *) paths
{
    return [self.tree paths];
}

- (void) execute:(NSString *)path executables:(NSArray*)executables
{
    for (NSString *executable in executables)
    {
        [ExecutionContext launch:executable args:[NSArray arrayWithObject:path]];
    }
}

- (void) fileAdded:(NSString *)path
{
    printf("A %s\n", [path UTF8String]);
    [self execute:path executables:addScripts];
}

- (void) fileModified:(NSString *)path
{
    printf("M %s\n", [path UTF8String]);
    [self execute:path executables:modScripts];
}

- (void) fileDeleted:(NSString *)path
{
    printf("D %s\n", [path UTF8String]);
    [self execute:path executables:delScripts];
}

- (void) addExecutable:(NSString *)executable flags:(NSUInteger)flags
{
    if (flags & ADD_FLAG) [addScripts addObject:executable];
    if (flags & MODIFY_FLAG) [modScripts addObject:executable];
    if (flags & DELETE_FLAG) [delScripts addObject:executable];
}
@end

void iFSEventStreamCallback(
    ConstFSEventStreamRef streamRef,
    void *clientCallBackInfo,
    size_t numEvents,
    void *eventPaths,
    const FSEventStreamEventFlags eventFlags[],
    const FSEventStreamEventId eventIds[])
{
    const char *const *paths = (const char *const *)eventPaths;
    ExecutionContext *ec = (ExecutionContext *)clientCallBackInfo;
    FSTree *tree = ec.tree;
    for (unsigned i = 0; i<numEvents; ++i)
    {
        NSString *path = [NSString stringWithUTF8String:paths[i]];
        [tree updatePath:path];
    }
}

int run(ExecutionContext *ec)
{
    FSEventStreamContext context = {
        0,
        ec,
        (CFAllocatorRetainCallBack)CFRetain,
        (CFAllocatorReleaseCallBack)CFRelease,
        (CFAllocatorCopyDescriptionCallBack)CFCopyDescription
    };

    FSEventStreamRef ref = FSEventStreamCreate(
        kCFAllocatorDefault,
        iFSEventStreamCallback,
        &context,
        (CFArrayRef)ec.tree.paths,
        kFSEventStreamEventIdSinceNow,
        .1,
        kFSEventStreamCreateFlagNoDefer
    );

    FSEventStreamScheduleWithRunLoop(
        ref,
        CFRunLoopGetCurrent(),
        kCFRunLoopDefaultMode
    );

    FSEventStreamStart(ref);

    CFRunLoopRun();

    FSEventStreamStop(ref);
    FSEventStreamInvalidate(ref);
    FSEventStreamRelease(ref);
    return EXIT_SUCCESS;
}

int main(int argc, char *const *argv)
{
    NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
    ExecutionContext *ec = [[[ExecutionContext alloc] init] autorelease];

    NSUInteger flags = 0;
    static struct option longOpts[] = {
        { "add", no_argument, NULL, 'a' },
        { "delete", no_argument, NULL, 'd' },
        { "modify", no_argument, NULL, 'm' },
        { "exec", required_argument, NULL, 'e' },
        { NULL, 0, NULL, 0 }
    };

    const char *optString = "adme:h?";
    int longIndex;
    int res;
    int status = 1;
    do
    {
        res = getopt_long_only(argc, argv, optString, longOpts, &longIndex);
        switch(res)
        {
        case 'a':
            flags |= ADD_FLAG;
            break;
        case 'm':
            flags |= MODIFY_FLAG;
            break;
        case 'd':
            flags |= DELETE_FLAG;
            break;
        case 'e':
            if (!flags) flags = ADD_FLAG | MODIFY_FLAG | DELETE_FLAG;
            [ec addExecutable:[NSString stringWithUTF8String:optarg] flags:flags];
            flags = 0;
            break;
        case 'h':
        case '?':
            status = 0;
            break;
        case 0: // long arg
        case -1:
        default:
            break;
        }
    } while(res != -1);

    // Paths to scan
    char *const *rav = argv + optind;
    int rac = argc-optind;
    if (rac == 0)
    {
        [ec addPath:@"."];
    }
    for (int i = 0; i<rac; ++i)
    {
        [ec addPath:[NSString stringWithUTF8String:rav[i]]];
    }

    int ret = status? run(ec) : 1;

    [pool drain];
    return ret;
}
