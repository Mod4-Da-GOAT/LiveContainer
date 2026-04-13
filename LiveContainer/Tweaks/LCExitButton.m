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
//   SideStore/LiveContainerSupport/XPCClient.m -relaunchLC
//   → [LCSharedUtils launchToGuestApp]
//
// launchToGuestApp tries three JIT-enabler paths first (TrollStore, StikJIT,
// SideStore), then falls back to opening livecontainer-relaunch via UIKit.
//
// We replicate that same priority order, but for the default path we use
// LSApplicationWorkspace instead of openURL because UIKit+GuestHooks.hook_openURL
// intercepts the livecontainer:// scheme (canAppOpenItself returns YES) and
// re-wraps it as open-url?url=<base64> before SIGKILL fires, causing LC to
// relaunch to the wrong screen.  LSApplicationWorkspace.openApplicationWithBundleID:
// goes straight to SpringBoard and is not hooked by TweakLoader.
//
static void lceb_relaunchLC(void) {
    [g_lcDefaults synchronize];

    UIApplication *app = UIApplication.sharedApplication;
    // NSBundle.mainBundle at this point is the GUEST bundle (after overwriteMainNSBundle).
    NSString *guestBundleId = NSBundle.mainBundle.bundleIdentifier;

    // ── Case 1: TrollStore ────────────────────────────────────────────────────
    if (!LCSharedUtils.certificatePassword) {
        NSString *tsPath = [NSString stringWithFormat:@"%@/../_TrollStore",
                            lcMainBundle.bundlePath];
        if (access(tsPath.UTF8String, F_OK) == 0) {
            NSURL *url = [NSURL URLWithString:
                [NSString stringWithFormat:@"apple-magnifier://enable-jit?bundle-id=%@",
                 guestBundleId]];
            if ([app canOpenURL:url]) {
                [app openURL:url options:@{} completionHandler:^(BOOL ok) {
                    raise(SIGKILL);
                    _exit(1);
                }];
                return;
            }
        }

        // ── Case 2: StikJIT ───────────────────────────────────────────────────
        NSURL *stikTest = [NSURL URLWithString:@"stikjit://"];
        if ([app canOpenURL:stikTest]) {
            NSURL *url = [NSURL URLWithString:
                [NSString stringWithFormat:@"stikjit://enable-jit?bundle-id=%@",
                 guestBundleId]];
            [app openURL:url options:@{} completionHandler:^(BOOL ok) {
                raise(SIGKILL);
                _exit(1);
            }];
            return;
        }

        // ── Case 3: SideStore JIT ─────────────────────────────────────────────
        NSURL *ssTest = [NSURL URLWithString:@"sidestore://"];
        if ([app canOpenURL:ssTest]) {
            NSURL *url = [NSURL URLWithString:
                [NSString stringWithFormat:@"sidestore://sidejit-enable?bid=%@",
                 guestBundleId]];
            [app openURL:url options:@{} completionHandler:^(BOOL ok) {
                raise(SIGKILL);
                _exit(1);
            }];
            return;
        }
    }

    // ── Case 4: Default — LSApplicationWorkspace, bypasses all UIKit hooks ───
    // Build the LC bundle ID from lcMainBundle (captured before invokeAppMain
    // swapped mainBundle, so it always points to the real LC bundle).
    NSString *lcBundleID = lcMainBundle.bundleIdentifier;
    if (!lcBundleID) {
        lcBundleID = [NSString stringWithFormat:@"com.kdt.%@",
                      g_lcScheme ?: @"livecontainer"];
    }

    // Use the class via id to avoid "no known class method" compiler error.
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

    // Give SpringBoard ~300 ms to register the open request, then kill.
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
    // (keyboard, permission prompts, etc.) which have no rootViewController.
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

    // Walk to the topmost non-dismissing presented VC.
    UIViewController *rootVC = win.rootViewController;
    if (!rootVC) return;

    // Guard: the root VC must actually be in the window hierarchy.
    // Presenting on a VC whose view.window is nil causes an immediate crash.
    if (rootVC.view.window == nil) return;

    NSInteger guard = 0;
    while (rootVC.presentedViewController
           && !rootVC.presentedViewController.isBeingDismissed
           && guard < 20) {
        rootVC = rootVC.presentedViewController;
        guard++;
    }

    // If the topmost VC is being dismissed, retry shortly.
    if (rootVC.isBeingDismissed) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.3 * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{
            [self exitButtonTapped];
        });
        return;
    }

    // Final guard: the resolved VC must also be in the window hierarchy.
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
// We observe UIWindowDidBecomeKeyNotification instead of swizzling
// UIWindow.makeKeyAndVisible.  UIKit+GuestHooks swizzles that same selector
// via method_exchangeImplementations; installing our own hook with
// method_setImplementation first corrupts both chains → crash on tap.
// The notification fires after the window is fully presented, so we get the
// same trigger with zero swizzle interaction.
// installInWindow: filters to real app windows (rootViewController present,
// windowScene is UIWindowScene) so we never attach to transient OS windows.
static id g_windowObserver = nil;

// ─── Entry point ───────────────────────────────────────────────
// Called before NUDGuestHooksInit() so g_lcDefaults captures lcUserDefaults
// before it is redirected to the guest container.
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
            // Short delay so rootViewController and safeAreaInsets are populated.
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW,
                                         (int64_t)(0.5 * NSEC_PER_SEC)),
                           dispatch_get_main_queue(), ^{
                [LCExitButtonView installInWindow:window];
            });
        }];
}
