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

// ─── Relaunch LC ──────────────────────────────────────────────
//
// Mirrors SideStore's "back to AppNest" approach:
//   SideStore/LiveContainerSupport/XPCClient.m: -relaunchLC
//   → [LCSharedUtils launchToGuestApp]
//
// Priority order matches launchToGuestApp exactly:
//   1. TrollStore  → apple-magnifier://enable-jit?bundle-id=…
//   2. StikJIT     → stikjit://enable-jit?bundle-id=…
//   3. SideStore   → sidestore://sidejit-enable?bid=…
//   4. Default     → LSApplicationWorkspace + exit(0)
//
// Cases 1–3 open a DIFFERENT app so UIKit+GuestHooks.hook_openURL does NOT
// intercept them (canAppOpenItself() returns NO for foreign schemes).
//
// Case 4 skips openURL entirely and uses LSApplicationWorkspace directly,
// because hook_openURL would see "livecontainer://" → canAppOpenItself YES →
// re-wrap as open-url?url=<base64> before the process exits, sending LC to
// the wrong screen on relaunch.
//
// We use exit(0) rather than raise(SIGKILL):
//   • exit(0) = clean termination → iOS does NOT record a crash report
//   • raise(SIGKILL) = signal 9 → iOS crash reporter fires, user sees crash
//     recovery UI, SpringBoard may not honour the openApplicationWithBundleID
//     request before the crash recovery dialog appears.
//
static void lceb_relaunchLC(void) {
    [g_lcDefaults synchronize];

    UIApplication *application = UIApplication.sharedApplication;
    // NSBundle.mainBundle at this point is the GUEST bundle (swapped by invokeAppMain).
    NSString *guestBundleId = NSBundle.mainBundle.bundleIdentifier;

    // ── Case 1: TrollStore ────────────────────────────────────────────────────
    if (!LCSharedUtils.certificatePassword) {
        NSString *tsPath = [NSString stringWithFormat:@"%@/../_TrollStore",
                            lcMainBundle.bundlePath];
        if (access(tsPath.UTF8String, F_OK) == 0) {
            NSURL *url = [NSURL URLWithString:
                [NSString stringWithFormat:@"apple-magnifier://enable-jit?bundle-id=%@",
                 guestBundleId]];
            if ([application canOpenURL:url]) {
                [application openURL:url options:@{} completionHandler:^(BOOL ok) {
                    exit(0);
                }];
                return;
            }
        }

        // ── Case 2: StikJIT ───────────────────────────────────────────────────
        NSURL *stikTest = [NSURL URLWithString:@"stikjit://"];
        if ([application canOpenURL:stikTest]) {
            NSURL *url = [NSURL URLWithString:
                [NSString stringWithFormat:@"stikjit://enable-jit?bundle-id=%@",
                 guestBundleId]];
            [application openURL:url options:@{} completionHandler:^(BOOL ok) {
                exit(0);
            }];
            return;
        }

        // ── Case 3: SideStore JIT ─────────────────────────────────────────────
        NSURL *ssTest = [NSURL URLWithString:@"sidestore://"];
        if ([application canOpenURL:ssTest]) {
            NSURL *url = [NSURL URLWithString:
                [NSString stringWithFormat:@"sidestore://sidejit-enable?bid=%@",
                 guestBundleId]];
            [application openURL:url options:@{} completionHandler:^(BOOL ok) {
                exit(0);
            }];
            return;
        }
    }

    // ── Case 4: Default — LSApplicationWorkspace bypasses all UIKit hooks ────
    // lcMainBundle is captured before invokeAppMain swaps mainBundle, so it
    // always points to the real LC bundle (not the guest app bundle).
    NSString *lcBundleID = lcMainBundle.bundleIdentifier;
    if (!lcBundleID) {
        lcBundleID = [NSString stringWithFormat:@"com.kdt.%@",
                      g_lcScheme ?: @"livecontainer"];
    }

    // Call via id cast — NSClassFromString returns opaque Class; the compiler
    // rejects direct class-method sends on it.
    Class lsClass = NSClassFromString(@"LSApplicationWorkspace");
    if (lsClass) {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-performSelector-leaks"
        id workspace = [(id)lsClass performSelector:NSSelectorFromString(@"defaultWorkspace")];
        if (workspace) {
            [workspace performSelector:NSSelectorFromString(@"openApplicationWithBundleID:")
                           withObject:lcBundleID];
        }
#pragma clang diagnostic pop
    }

    // Give SpringBoard ~400ms to register the open request before we exit.
    // exit(0) is a clean termination — no crash report, no crash recovery UI.
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.4 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        exit(0);
    });
}

// ─── Floating container view ───────────────────────────────────
@interface LCExitButtonView : UIView
+ (void)installInWindow:(UIWindow *)window;
@end

@implementation LCExitButtonView

+ (void)installInWindow:(UIWindow *)window {
    if (!window || !g_lcDefaults) return;

    // Only attach to real app windows. Transient system windows (keyboard,
    // permission prompts, crash reporters, etc.) have no rootViewController —
    // presentViewController: on nil crashes immediately.
    if (!window.rootViewController) return;
    if (![window.windowScene isKindOfClass:[UIWindowScene class]]) return;

    id stored = [g_lcDefaults objectForKey:@"LCShowExitButton"];
    BOOL showButton = stored ? [g_lcDefaults boolForKey:@"LCShowExitButton"] : NO;
    if (!showButton) return;

    // Remove any existing button before re-adding.
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

    LCExitButtonView *v = [[LCExitButtonView alloc]
                           initWithFrame:CGRectMake(x, y, size, size)];
    v.backgroundColor        = [UIColor clearColor];
    v.userInteractionEnabled = YES;
    v.layer.zPosition        = 9999.0f;

    UIButton *btn = [UIButton buttonWithType:UIButtonTypeCustom];
    btn.frame = CGRectMake(0, 0, size, size);
    if (@available(iOS 13.0, *)) {
        UIImageSymbolConfiguration *cfg = [UIImageSymbolConfiguration
            configurationWithPointSize:26 weight:UIImageSymbolWeightSemibold];
        [btn setImage:[UIImage systemImageNamed:@"xmark.circle.fill"
                               withConfiguration:cfg]
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

    // Find the topmost VC that is in the window hierarchy and not mid-dismissal.
    // Guard: a VC whose view.window is nil is not in the hierarchy — presenting
    // on it crashes immediately with "Trying to present on a view that is not in a window".
    UIViewController *rootVC = win.rootViewController;
    if (!rootVC || rootVC.view.window == nil) return;

    NSInteger guard = 0;
    while (rootVC.presentedViewController
           && !rootVC.presentedViewController.isBeingDismissed
           && guard < 20) {
        rootVC = rootVC.presentedViewController;
        guard++;
    }

    // If the resolved VC is being dismissed, retry shortly.
    if (rootVC.isBeingDismissed) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.3 * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{
            [self exitButtonTapped];
        });
        return;
    }

    // Final hierarchy check after the walk.
    if (rootVC.view.window == nil) return;

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
// UIWindowDidBecomeKeyNotification instead of swizzling UIWindow.makeKeyAndVisible.
//
// UIKit+GuestHooks swizzles makeKeyAndVisible via method_exchangeImplementations.
// Installing our own IMP first with method_setImplementation then having GuestHooks
// call method_exchangeImplementations corrupts both chains → crash on first tap.
// The notification fires after the window is fully set up, giving us the same
// trigger point with zero interaction with the existing swizzle chain.
//
// installInWindow: filters to windows with a rootViewController and a UIWindowScene,
// so we never attach to transient OS overlay windows.
static id g_windowObserver = nil;

// ─── Entry point ───────────────────────────────────────────────
// Called before NUDGuestHooksInit() so g_lcDefaults captures the real LC
// NSUserDefaults before it is redirected to the guest container.
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
            // Short delay so rootViewController and safeAreaInsets are fully set.
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW,
                                         (int64_t)(0.5 * NSEC_PER_SEC)),
                           dispatch_get_main_queue(), ^{
                [LCExitButtonView installInWindow:window];
            });
        }];
}
