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
// We open LC directly via LSApplicationWorkspace (not openURL) because
// hook_openURL in UIKit+GuestHooks intercepts livecontainer:// URLs and
// re-wraps them as open-url?url=<base64> before any kill fires, causing
// LC to relaunch to the wrong screen.
// LSApplicationWorkspace goes straight to SpringBoard, bypassing all hooks.
static void lceb_relaunchLC(void) {
    // Flush the cleared "selected" key to disk before we die.
    [g_lcDefaults synchronize];

    NSString *lcBundleID = lcMainBundle.bundleIdentifier;
    if (!lcBundleID) {
        lcBundleID = [NSString stringWithFormat:@"com.kdt.%@",
                      g_lcScheme ?: @"livecontainer"];
    }

    // Open LC directly via SpringBoard, bypassing all UIKit/TweakLoader hooks.
    [[LSApplicationWorkspace defaultWorkspace] openApplicationWithBundleID:lcBundleID];

    // Give SpringBoard ~300ms to register the open request, then terminate.
    // We use raise(SIGKILL) — Darwin SIGKILL = 9, which is clean and uninterceptable.
    // Previous code used inline asm "mov x0,#31 / mov x16,#26 / svc #0x80" which is
    // wrong on Darwin/XNU: syscall 26 = recvfrom (not kill), and signal 31 = SIGUSR2
    // (not SIGKILL). The process only died because _exit(1) was the fallback.
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.3 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        raise(SIGKILL);
        _exit(1); // unreachable, silences static analysis
    });
}

// ─── Floating container view ───────────────────────────────────
@interface LCExitButtonView : UIView
+ (void)installInWindow:(UIWindow *)window;
@end

@implementation LCExitButtonView

+ (void)installInWindow:(UIWindow *)window {
    if (!window || !g_lcDefaults) return;

    // Only attach to real app windows that have a rootViewController and belong
    // to a UIWindowScene. Transient system windows (keyboard, permission prompts,
    // crash reporters, etc.) have no rootViewController — calling
    // presentViewController: on nil crashes the process.
    if (!window.rootViewController) return;
    if (![window.windowScene isKindOfClass:[UIWindowScene class]]) return;

    id stored = [g_lcDefaults objectForKey:@"LCShowExitButton"];
    // Default is NO — user must explicitly enable in LC settings.
    BOOL showButton = stored ? [g_lcDefaults boolForKey:@"LCShowExitButton"] : NO;
    if (!showButton) return;

    // Remove any existing exit button in this window before re-adding.
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
    // self.window can be nil if the view was removed between tap and handler firing.
    UIWindow *win = self.window;
    if (!win) return;

    // Walk to the topmost presented VC. Guard against cycles and against
    // VCs that are mid-dismissal (presentViewController: on those crashes).
    UIViewController *rootVC = win.rootViewController;
    if (!rootVC) return;

    NSInteger guard = 0;
    while (rootVC.presentedViewController && !rootVC.presentedViewController.isBeingDismissed && guard < 20) {
        rootVC = rootVC.presentedViewController;
        guard++;
    }

    // If the topmost VC is itself being dismissed, retry shortly.
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
// makeKeyAndVisible or layoutSubviews on UIWindow.
//
// Swizzling makeKeyAndVisible conflicts with UIKit+GuestHooks which also
// swizzles the same selector via method_exchangeImplementations. Using
// method_setImplementation first and then having GuestHooks call
// method_exchangeImplementations corrupts both hook chains, producing an
// infinite call loop that crashes on the first button tap.
//
// The notification fires AFTER the window is fully presented, giving us a
// safe moment to add the button without touching the swizzle chain at all.
// installInWindow: filters out system/overlay windows (no rootViewController
// or no UIWindowScene) so we never attach to transient OS windows.
static id g_windowObserver = nil;

// ─── Entry point ───────────────────────────────────────────────
// MUST be called before NUDGuestHooksInit() so g_lcDefaults captures
// lcUserDefaults before it is redirected to the guest container.
void LCExitButtonGuestHooksInit(BOOL isLiveProcess, BOOL isSideStore) {
    // Skip for LiveProcess (multitask) and built-in SideStore.
    if (isLiveProcess || isSideStore) return;

    g_lcScheme   = [lcAppUrlScheme copy];
    g_lcDefaults = lcUserDefaults;

    id stored = [g_lcDefaults objectForKey:@"LCShowExitButton"];
    BOOL showButton = stored ? [g_lcDefaults boolForKey:@"LCShowExitButton"] : NO;
    if (!showButton) return;

    // Register for window-became-key events. Each time any window becomes key
    // we attempt to install the exit button; installInWindow: handles filtering
    // (wrong window type, button already present, etc.) idempotently.
    g_windowObserver = [[NSNotificationCenter defaultCenter]
        addObserverForName:UIWindowDidBecomeKeyNotification
        object:nil
        queue:[NSOperationQueue mainQueue]
        usingBlock:^(NSNotification *note) {
            UIWindow *window = note.object;
            // Delay slightly so the window's rootViewController and safe-area
            // insets are fully populated before we try to read them.
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)),
                           dispatch_get_main_queue(), ^{
                [LCExitButtonView installInWindow:window];
            });
        }];
}
