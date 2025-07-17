@import Foundation;
#import "utils.h"
#import "LCSharedUtils.h"
#import "Tweaks.h"

static BOOL readOnlyBundle = NO;
static BOOL isolateAppGroup = NO;

static BOOL isPathInMainBundle(NSString *path) {
    NSString *mainBundlePath = NSBundle.mainBundle.bundlePath;
    return [path hasPrefix:mainBundlePath];
}

@implementation NSFileManager(LiveContainerHooks)

- (BOOL)hook_createFileAtPath:(NSString *)path contents:(NSData *)data attributes:(NSDictionary<NSFileAttributeKey,id> *)attr {
    if (readOnlyBundle && isPathInMainBundle(path)) {
        NSLog(@"[LC] Denying write to main bundle: %@", path);
        return NO;
    }
    return [self hook_createFileAtPath:path contents:data attributes:attr];
}

- (BOOL)hook_removeItemAtPath:(NSString *)path error:(NSError **)error {
    if (readOnlyBundle && isPathInMainBundle(path)) {
        NSLog(@"[LC] Denying item removal in main bundle: %@", path);
        if (error) {
            *error = [NSError errorWithDomain:NSPOSIXErrorDomain code:EPERM userInfo:@{NSLocalizedDescriptionKey: @"Operation not permitted"}];
        }
        return NO;
    }
    return [self hook_removeItemAtPath:path error:error];
}

- (BOOL)hook_moveItemAtPath:(NSString *)srcPath toPath:(NSString *)dstPath error:(NSError **)error {
    if (readOnlyBundle && (isPathInMainBundle(srcPath) || isPathInMainBundle(dstPath))) {
        NSLog(@"[LC] Denying item move in main bundle: %@ -> %@", srcPath, dstPath);
        if (error) {
            *error = [NSError errorWithDomain:NSPOSIXErrorDomain code:EPERM userInfo:@{NSLocalizedDescriptionKey: @"Operation not permitted"}];
        }
        return NO;
    }
    return [self hook_moveItemAtPath:srcPath toPath:dstPath error:error];
}

- (BOOL)hook_createDirectoryAtPath:(NSString *)path withIntermediateDirectories:(BOOL)createIntermediates attributes:(NSDictionary<NSFileAttributeKey,id> *)attributes error:(NSError **)error {
    if (readOnlyBundle && isPathInMainBundle(path)) {
        NSLog(@"[LC] Denying directory creation in main bundle: %@", path);
        if (error) {
            *error = [NSError errorWithDomain:NSPOSIXErrorDomain code:EPERM userInfo:@{NSLocalizedDescriptionKey: @"Operation not permitted"}];
        }
        return NO;
    }
    return [self hook_createDirectoryAtPath:path withIntermediateDirectories:createIntermediates attributes:attributes error:error];
}

- (BOOL)hook_setAttributes:(NSDictionary<NSFileAttributeKey,id> *)attributes ofItemAtPath:(NSString *)path error:(NSError **)error {
    if (readOnlyBundle && isPathInMainBundle(path)) {
        NSLog(@"[LC] Denying attribute change in main bundle: %@", path);
        if (error) {
            *error = [NSError errorWithDomain:NSPOSIXErrorDomain code:EPERM userInfo:@{NSLocalizedDescriptionKey: @"Operation not permitted"}];
        }
        return NO;
    }
    return [self hook_setAttributes:attributes ofItemAtPath:path error:error];
}

- (nullable NSURL *)hook_containerURLForSecurityApplicationGroupIdentifier:(NSString *)groupIdentifier {
    if([groupIdentifier isEqualToString:[NSClassFromString(@"LCSharedUtils") appGroupID]]) {
        return [NSURL fileURLWithPath: NSUserDefaults.lcAppGroupPath];
    }
    NSURL *result;
    if(isolateAppGroup) {
        result = [NSURL fileURLWithPath:[NSString stringWithFormat:@"%s/LCAppGroup/%@", getenv("HOME"), groupIdentifier]];
    } else if (NSUserDefaults.lcAppGroupPath){
        result = [NSURL fileURLWithPath:[NSString stringWithFormat:@"%@/LiveContainer/Data/AppGroup/%@", NSUserDefaults.lcAppGroupPath, groupIdentifier]];
    } else {
        result = [NSURL fileURLWithPath:[NSString stringWithFormat:@"%s/Documents/Data/AppGroup/%@", getenv("LC_HOME_PATH"), groupIdentifier]];
    }
    [NSFileManager.defaultManager createDirectoryAtURL:result withIntermediateDirectories:YES attributes:nil error:nil];
    return result;
}

@end

void NSFMGuestHooksInit(void) {
    NSString* containerInfoPath = [[NSString stringWithUTF8String:getenv("HOME")] stringByAppendingPathComponent:@"LCContainerInfo.plist"];
    NSDictionary* infoDict = [NSDictionary dictionaryWithContentsOfFile:containerInfoPath];
    isolateAppGroup = [infoDict[@"isolateAppGroup"] boolValue];
    readOnlyBundle = [infoDict[@"readOnlyBundle"] boolValue];

    swizzle(NSFileManager.class, @selector(containerURLForSecurityApplicationGroupIdentifier:), @selector(hook_containerURLForSecurityApplicationGroupIdentifier:));

    if (readOnlyBundle) {
        swizzle(NSFileManager.class, @selector(createFileAtPath:contents:attributes:), @selector(hook_createFileAtPath:contents:attributes:));
        swizzle(NSFileManager.class, @selector(removeItemAtPath:error:), @selector(hook_removeItemAtPath:error:));
        swizzle(NSFileManager.class, @selector(moveItemAtPath:toPath:error:), @selector(hook_moveItemAtPath:toPath:error:));
        swizzle(NSFileManager.class, @selector(createDirectoryAtPath:withIntermediateDirectories:attributes:error:), @selector(hook_createDirectoryAtPath:withIntermediateDirectories:attributes:error:));
        swizzle(NSFileManager.class, @selector(setAttributes:ofItemAtPath:error:), @selector(hook_setAttributes:ofItemAtPath:error:));
    }
}
