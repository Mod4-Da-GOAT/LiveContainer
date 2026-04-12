//
//  LCExitButton.m
//  LiveContainer
//
//  Injects a floating exit button on top of the running guest app (normal mode only).
//  Pass isLiveProcess=YES or isSideStore=YES to skip.
//  Multitask mode is handled separately by MultitaskAppWindow.swift.
//

#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <signal.h>
#import "../LCSharedUtils.h"

// Captured at init time, before bundle/defaults swap
extern NSString       *lcAppUrlScheme;
extern NSUserDefaults *lcUserDefaults;
extern NSBundle       *lcMainBundle;   // LC's real bundle, set by LCBootstrap before invokeAppMain
static NSString       *g_lcScheme   = nil;
static NSUserDefaults *g_lcDefaults = nil;

@interface LSApplicationWorkspace : NSObject
+ (instancetype)defaultWorkspace;
- (BOOL)openApplicationWithBundleID:(NSString *)bundleID;
@end

// ─── Relaunch LC ──────────────────────────────────────────────
// In single-app mode the guest runs inside the LC process.
// We must NOT use UIApplication.openURL("livecontainer://livecontainer-relaunch") —
// UIKit+GuestHooks.hook_openURL intercepts it, and because canAppOpenItself()
// returns YES (this IS the LC process), the hook re-wraps it as
// "livecontainer://open-url?url=<base64>" before SIGKILL fires. LC then
// relaunches receiving a mangled open-url instead of showing its own UI → crash.
//
// Fix: open LC via LSApplicationWorkspace.openApplicationWithBundleID: which is
// not hooked by TweakLoader and goes straight to SpringBoard.
// "selected" was cleared by LCBootstrap before invokeAppMain; synchronize() ensures
// that write is on disk before the process is killed.
static void lceb_relaunchLC(void) {
    // Flush the cleared "selected" key to disk before we die.
    // We call synchronize() synchronously here (on the main thread) so the write
    // is guaranteed to be committed before the dispatch_after block fires the kill.
    // A second synchronize() inside the block is NOT needed and was previously
    // causing a use-after-free if g_lcDefaults had been deallocated during teardown.
    [g_lcDefaults synchronize];

    // Use the real LC bundle ID from lcMainBundle (set by LCBootstrap before
    // invokeAppMain, so it reflects the actual LC bundle, not the guest).
    NSString *lcBundleID = lcMainBundle.bundleIdentifier;
    if (!lcBundleID) {
        lcBundleID = [NSString stringWithFormat:@"com.kdt.%@",
                      g_lcScheme ?: @"livecontainer"];
    }

    // Open LC directly via SpringBoard, bypassing all UIKit/TweakLoader hooks.
    [[LSApplicationWorkspace defaultWorkspace] openApplicationWithBundleID:lcBundleID];

    // Give SpringBoard ~300 ms to register the open request before we kill.
    //
    // We use a raw SIGKILL syscall rather than raise(SIGKILL) or exit() because:
    //   • exit() runs C runtime teardown (atexit, ObjC destructors) whose
    //     hooked function pointers may already be invalid, causing a crash the
    //     OS records instead of clean termination → SpringBoard may block relaunch.
    //   • raise(SIGKILL) goes through the signal() infrastructure which can be
    //     intercepted by some crash reporters injected by TweakLoader.
    //   • The direct svc #0x80 SYS_kill below is uninterceptable and matches
    //     exactly what the original LCExitButton code intended.
    //
    // There is NO fallback raise(SIGKILL) after the dispatch_after block —
    // that was the previous bug: the raise() fired immediately (before the
    // 300ms delay), killing the process before SpringBoard could register the
    // open request, so the relaunch never happened.
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.3 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        __asm__ __volatile__ (
            "mov x0, #31\n"   // SIGKILL = 31
            "mov x16, #26\n"  // SYS_kill
            "svc #0x80\n"
        );
        // The line below is logically unreachable — the svc kills the process.
        // It exists only to silence static-analysis warnings about missing kills.
        _exit(1);
    });
}

// ─── Floating container view ───────────────────────────────────
@interface LCExitButtonView : UIView
+ (void)installInWindow:(UIWindow *)window;
@end

@implementation LCExitButtonView

+ (void)installInWindow:(UIWindow *)window {
    if (!window || !g_lcDefaults) return;

    id stored = [g_lcDefaults objectForKey:@"LCShowExitButton"];
    // Default is NO — user must explicitly enable in LC settings.
    BOOL showButton = stored ? [g_lcDefaults boolForKey:@"LCShowExitButton"] : NO;
    if (!showButton) return;

    // Remove existing
    for (UIView *sub in [window.subviews copy]) {
        if ([sub isKindOfClass:[LCExitButtonView class]]) {
            [sub removeFromSuperview];
        }
    }

    CGFloat winW = window.bounds.size.width;
    if (winW <= 0) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.3 * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{
            [LCExitButtonView installInWindow:window];
        });
        return;
    }

    BOOL onRight    = [g_lcDefaults boolForKey:@"LCExitButtonPosition"];
    CGFloat size    = 44.0f;
    CGFloat safeTop = window.safeAreaInsets.top > 0 ? window.safeAreaInsets.top : 44.0f;
    CGFloat x       = onRight ? (winW - size - 12.0f) : 12.0f;
    CGFloat y       = safeTop + 8.0f;

    LCExitButtonView *v = [[LCExitButtonView alloc] initWithFrame:CGRectMake(x, y, size, size)];
    v.backgroundColor        = [UIColor clearColor];
    v.userInteractionEnabled = YES;
    v.layer.zPosition        = 9999.0f;

    UIButton *btn = [UIButton buttonWithType:UIButtonTypeCustom];
    btn.frame = CGRectMake(0, 0, size, size);
    if (@available(iOS 13.0, *)) {
        UIImageSymbolConfiguration *cfg = [UIImageSymbolConfiguration
            configurationWithPointSize:26 weight:UIImageSymbolWeightSemibold];
        [btn setImage:[UIImage systemImageNamed:@"xmark.circle.fill" withConfiguration:cfg]
             forState:UIControlStateNormal];
        btn.tintColor = [UIColor whiteColor];
    } else {
        [btn setTitle:@"✕" forState:UIControlStateNormal];
        [btn setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
        btn.titleLabel.font = [UIFont boldSystemFontOfSize:20];
    }
    btn.layer.shadowColor   = [UIColor blackColor].CGColor;
    btn.layer.shadowOffset  = CGSizeMake(0, 2);
    btn.layer.shadowRadius  = 4.0f;
    btn.layer.shadowOpacity = 0.55f;

    [btn addTarget:v action:@selector(exitButtonTapped)
  forControlEvents:UIControlEventTouchUpInside];
    [v addSubview:btn];
    [window addSubview:v];
    [window bringSubviewToFront:v];
}

- (void)exitButtonTapped {
    UIViewController *rootVC = self.window.rootViewController;
    while (rootVC.presentedViewController) {
        rootVC = rootVC.presentedViewController;
    }

    UIAlertController *alert = [UIAlertController
        alertControllerWithTitle:@"Return to AppNest?"
        message:@"Any unsaved data in the running app may be lost."
        preferredStyle:UIAlertControllerStyleAlert];

    [alert addAction:[UIAlertAction
        actionWithTitle:@"Leave App"
        style:UIAlertActionStyleDestructive
        handler:^(UIAlertAction *_) {
            lceb_relaunchLC();
        }]];
    [alert addAction:[UIAlertAction
        actionWithTitle:@"Cancel"
        style:UIAlertActionStyleCancel
        handler:nil]];

    [rootVC presentViewController:alert animated:YES completion:nil];
}

- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event {
    UIView *hit = [super hitTest:point withEvent:event];
    return (hit == self) ? nil : hit;
}

@end

// ─── UIWindow hooks ────────────────────────────────────────────
static IMP orig_makeKeyAndVisible;
static void hook_makeKeyAndVisible(UIWindow *self, SEL _cmd) {
    ((void (*)(id, SEL))orig_makeKeyAndVisible)(self, _cmd);
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        [LCExitButtonView installInWindow:self];
    });
}

static IMP orig_layoutSubviews;
static void hook_layoutSubviews(UIWindow *self, SEL _cmd) {
    ((void (*)(id, SEL))orig_layoutSubviews)(self, _cmd);
    if (!self.isKeyWindow) return;
    for (UIView *sub in self.subviews) {
        if ([sub isKindOfClass:[LCExitButtonView class]]) {
            [LCExitButtonView installInWindow:self];
            break;
        }
    }
}

// ─── Entry point ───────────────────────────────────────────────
// MUST be called before NUDGuestHooksInit() so lcUserDefaults is
// still the real LC defaults (not yet redirected to guest container).
// isSideStore must be passed in — it is set by LiveContainerMain before
// invokeAppMain is called, so it is known at this call site.
void LCExitButtonGuestHooksInit(BOOL isLiveProcess, BOOL isSideStore) {
    // Skip for LiveProcess (multitask) and for built-in SideStore —
    // SideStore has its own back-to-LiveContainer button.
    if (isLiveProcess || isSideStore) return;

    g_lcScheme   = [lcAppUrlScheme copy];
    g_lcDefaults = lcUserDefaults;

    id stored = [g_lcDefaults objectForKey:@"LCShowExitButton"];
    // Default is NO — user must explicitly enable.
    BOOL showButton = stored ? [g_lcDefaults boolForKey:@"LCShowExitButton"] : NO;
    if (!showButton) return;

    Class cls = [UIWindow class];
    Method m1 = class_getInstanceMethod(cls, @selector(makeKeyAndVisible));
    orig_makeKeyAndVisible = method_setImplementation(m1, (IMP)hook_makeKeyAndVisible);
    Method m2 = class_getInstanceMethod(cls, @selector(layoutSubviews));
    orig_layoutSubviews    = method_setImplementation(m2, (IMP)hook_layoutSubviews);
}
