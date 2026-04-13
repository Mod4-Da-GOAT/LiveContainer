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
//
// This mirrors the approach used by SideStore's "back to AppNest" button
// (SideStore/LiveContainerSupport/XPCClient.m: -relaunchLC calls
// [LCSharedUtils launchToGuestApp]).
//
// [LCSharedUtils launchToGuestApp] handles three cases in order:
//   1. TrollStore    → apple-magnifier://enable-jit?bundle-id=…  (opens magnifier, not LC)
//   2. StikJIT       → stikjit://enable-jit?bundle-id=…          (opens StikJIT, not LC)
//   3. SideStore JIT → sidestore://sidejit-enable?bid=…          (opens SideStore, not LC)
//   4. Default       → livecontainer://livecontainer-relaunch (+ raise(SIGKILL))
//
// Cases 1–3 open OTHER apps so UIKit+GuestHooks.hook_openURL doesn't intercept them
// (canAppOpenItself() returns NO for schemes that aren't the LC scheme).
//
// Case 4 is the problem: hook_openURL sees "livecontainer://" → canAppOpenItself()
// returns YES → it wraps the URL as open-url?url=<base64> before kill fires →
// LC relaunches to the wrong screen.
//
// Fix for case 4: instead of openURL, use LSApplicationWorkspace directly.
// LSApplicationWorkspace.openApplicationWithBundleID: goes straight to SpringBoard,
// bypassing every UIKit hook installed by TweakLoader.
//
// We replicate launchToGuestApp's JIT-URL logic ourselves for cases 1–3
// (so we get the same TrollStore/StikJIT/SideStore behaviour), then use
// LSApplicationWorkspace + raise(SIGKILL) for the default case.
//
static void lceb_relaunchLC(void) {
    [g_lcDefaults synchronize];

    UIApplication *application = UIApplication.sharedApplication;

    // ── Case 1: TrollStore ────────────────────────────────────────────────────
    NSString *tsPath = [NSString stringWithFormat:@"%@/../_TrollStore",
                        lcMainBundle.bundlePath];
    if (!LCSharedUtils.certificatePassword &&
        access(tsPath.UTF8String, F_OK) == 0) {
        NSString *bundleId = NSBundle.mainBundle.bundleIdentifier; // guest bundle
        NSURL *url = [NSURL URLWithString:
                      [NSString stringWithFormat:@"apple-magnifier://enable-jit?bundle-id=%@",
                       bundleId]];
        if ([application canOpenURL:url]) {
            [application openURL:url options:@{} completionHandler:^(BOOL ok) {
                raise(SIGKILL);
                _exit(1);
            }];
            return;
        }
    }

    // ── Case 2: StikJIT ───────────────────────────────────────────────────────
    if (!LCSharedUtils.certificatePassword) {
        NSURL *stikTest = [NSURL URLWithString:@"stikjit://"];
        if ([application canOpenURL:stikTest]) {
            NSString *bundleId = NSBundle.mainBundle.bundleIdentifier;
            NSURL *url = [NSURL URLWithString:
                          [NSString stringWithFormat:@"stikjit://enable-jit?bundle-id=%@",
                           bundleId]];
            [application openURL:url options:@{} completionHandler:^(BOOL ok) {
                raise(SIGKILL);
                _exit(1);
            }];
            return;
        }
    }

    // ── Case 3: SideStore JIT ────────────────────────────────────────────────
    if (!LCSharedUtils.certificatePassword) {
        NSURL *ssTest = [NSURL URLWithString:@"sidestore://"];
        if ([application canOpenURL:ssTest]) {
            NSString *bundleId = NSBundle.mainBundle.bundleIdentifier;
            NSURL *url = [NSURL URLWithString:
                          [NSString stringWithFormat:@"sidestore://sidejit-enable?bid=%@",
                           bundleId]];
            [application openURL:url options:@{} completionHandler:^(BOOL ok) {
                raise(SIGKILL);
                _exit(1);
            }];
            return;
        }
    }

    // ── Case 4: Default — open LC via SpringBoard, bypass all UIKit hooks ────
    // We do NOT use openURL("livecontainer://livecontainer-relaunch") here because
    // UIKit+GuestHooks.hook_openURL intercepts it (canAppOpenItself returns YES for
    // the LC scheme) and re-wraps it as open-url?url=<base64> before the kill fires,
    // causing LC to relaunch to the wrong screen.
    //
    // LSApplicationWorkspace.openApplicationWithBundleID: goes straight to SpringBoard
    // and is not intercepted by any TweakLoader hook.
    NSString *lcBundleID = lcMainBundle.bundleIdentifier;
    if (!lcBundleID) {
        lcBundleID = [NSString stringWithFormat:@"com.kdt.%@",
                      g_lcScheme ?: @"livecontainer"];
    }

    [[LSApplicationWorkspace defaultWorkspace] openApplicationWithBundleID:lcBundleID];

    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.3 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        raise(SIGKILL);
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

    // Only attach to real app windows — not system overlay windows
    // (keyboard, permission dialogs, etc.) which have no rootViewController.
    // Tapping the button on such windows would crash when trying to present an alert.
    if (!window.rootViewController) return;
    if (![window.windowScene isKindOfClass:[UIWindowScene class]]) return;

    id stored = [g_lcDefaults objectForKey:@"LCShowExitButton"];
    BOOL showButton = stored ? [g_lcDefaults boolForKey:@"LCShowExitButton"] : NO;
    if (!showButton) return;

    // Remove any existing exit button before re-adding.
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
    UIWindow *win = self.window;
    if (!win) return;

    // Walk to the topmost non-dismissing presented VC.
    UIViewController *rootVC = win.rootViewController;
    if (!rootVC) return;

    NSInteger guard = 0;
    while (rootVC.presentedViewController
           && !rootVC.presentedViewController.isBeingDismissed
           && guard < 20) {
        rootVC = rootVC.presentedViewController;
        guard++;
    }

    if (rootVC.isBeingDismissed) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.3 * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{
            [self exitButtonTapped];
        });
        return;
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

// ─── Notification-based window observer ───────────────────────
// We observe UIWindowDidBecomeKeyNotification instead of swizzling
// makeKeyAndVisible / layoutSubviews on UIWindow.
//
// UIKit+GuestHooks already swizzles makeKeyAndVisible via
// method_exchangeImplementations. Installing a second hook with
// method_setImplementation first corrupts both chains and causes an
// infinite call loop that crashes on the first button tap. The notification
// fires after the window is fully up — same effect, no swizzle conflict.
//
// installInWindow: filters to real app windows (rootViewController present,
// windowScene is UIWindowScene) so we never attach to transient OS windows.
static id g_windowObserver = nil;

// ─── Entry point ───────────────────────────────────────────────
// Must be called before NUDGuestHooksInit() so g_lcDefaults captures
// lcUserDefaults before it is redirected to the guest container.
void LCExitButtonGuestHooksInit(BOOL isLiveProcess, BOOL isSideStore) {
    if (isLiveProcess || isSideStore) return;

    g_lcScheme   = [lcAppUrlScheme copy];
    g_lcDefaults = lcUserDefaults;

    id stored = [g_lcDefaults objectForKey:@"LCShowExitButton"];
    BOOL showButton = stored ? [g_lcDefaults boolForKey:@"LCShowExitButton"] : NO;
    if (!showButton) return;

    g_windowObserver = [[NSNotificationCenter defaultCenter]
        addObserverForName:UIWindowDidBecomeKeyNotification
        object:nil
        queue:[NSOperationQueue mainQueue]
        usingBlock:^(NSNotification *note) {
            UIWindow *window = note.object;
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)),
                           dispatch_get_main_queue(), ^{
                [LCExitButtonView installInWindow:window];
            });
        }];
}
