#import <Foundation/Foundation.h>
#import <objc/runtime.h>

#ifdef __cplusplus
extern "C" {
#endif

static inline void swizzle(Class cls, SEL originalAction, SEL swizzledAction) {
    Method origMethod = class_getInstanceMethod(cls, originalAction);
    Method swizMethod = class_getInstanceMethod(cls, swizzledAction);
    if (origMethod && swizMethod) {
        method_exchangeImplementations(origMethod, swizMethod);
    }
}

static inline void swizzleClassMethod(Class cls, SEL originalAction, SEL swizzledAction) {
    Method origMethod = class_getClassMethod(cls, originalAction);
    Method swizMethod = class_getClassMethod(cls, swizzledAction);
    if (origMethod && swizMethod) {
        method_exchangeImplementations(origMethod, swizMethod);
    }
}

#ifdef __cplusplus
}
#endif

// Exported from the main executable
@interface NSUserDefaults(LiveContainer)
+ (instancetype)lcUserDefaults;
+ (instancetype)lcSharedDefaults;
+ (NSString *)lcAppGroupPath;
+ (NSString *)lcAppUrlScheme;
+ (NSBundle *)lcMainBundle;
+ (NSDictionary *)guestAppInfo;
+ (NSDictionary *)guestContainerInfo;
+ (bool)isLiveProcess;
+ (bool)isSharedApp;
+ (NSString*)lcGuestAppId;
+ (bool)isSideStore;
+ (bool)sideStoreExist;
@end
