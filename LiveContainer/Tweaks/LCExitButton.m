//
//  LCExitButton.m
//  LiveContainer
//
//  Injects a floating exit button on top of the running guest app (normal mode only).
//  Pass isLiveProcess=YES to skip — multitask is handled by MultitaskAppWindow.swift.
//

#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <signal.h>
#import "../LCSharedUtils.h"

// ─────────────────────────────────────────────────────────────
// Relaunch LC without going through canOpenURL (which always
// returns NO from inside the guest because livecontainer:// is
// not in the guest app's LSApplicationQueriesSchemes).
// This mirrors what LCSharedUtils.launchToGuestApp does internally.
// ─────────────────────────────────────────────────────────────
static void lceb_relaunchLC(void) {
    // Get the LC URL scheme from CFBundleURLTypes — always valid because
    // this process IS LC (the guest runs inside LC's process in normal mode).
    NSArray *urlTypes = [NSBundle mainBundle].infoDictionary[@"CFBundleURLTypes"];
    NSString *scheme  = [urlTypes firstObject][@"CFBundleURLSchemes"][0] ?: @"livecontainer";
    NSString *urlStr  = [NSString stringWithFormat:@"%@://livecontainer-relaunch", scheme];
    NSURL    *url     = [NSURL URLWithString:urlStr];

    UIApplication *app = [NSClassFromString(@"UIApplication") sharedApplication];

    // Open twice (same as launchToGuestApp with tries=2) so the request is
    // queued by iOS even if the first delivery races with our SIGKILL.
    for (int i = 0; i < 2; i++) {
        [app openURL:url options:@{} completionHandler:nil];
    }

    // Give iOS a moment to queue the URL open, then terminate via SIGKILL.
    // iOS will process the pending open-URL request and launch a fresh LC.
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.1 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
#if defined(__arm64__)
        __asm__ __volatile__(
            "mov x0, #31\n"   // PT_DENY_ATTACH (matches LCSharedUtils exactly)
            "mov x16, #26\n"  // SYS_ptrace
            "svc #0x80\n"
        );
#endif
        raise(SIGKILL);
    });
}

// ─────────────────────────────────────────────────────────────
// Floating container — passes all touches through to the app
// except those that land on the exit button itself.
// ─────────────────────────────────────────────────────────────
@interface LCExitButtonView : UIView
+ (void)installInWindow:(UIWindow *)window;
@end

@implementation LCExitButtonView

+ (void)installInWindow:(UIWindow *)window {
    if (!window) return;

    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    id stored = [defaults objectForKey:@"LCShowExitButton"];
    BOOL showButton = stored ? [defaults boolForKey:@"LCShowExitButton"] : YES;
    if (!showButton) return;

    // Remove any existing instance
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

    BOOL onRight    = [defaults boolForKey:@"LCExitButtonPosition"];
    CGFloat size    = 44.0f;
    CGFloat safeTop = window.safeAreaInsets.top > 0 ? window.safeAreaInsets.top : 44.0f;
    CGFloat x       = onRight ? (winW - size - 12.0f) : 12.0f;
    CGFloat y       = safeTop + 8.0f;

    LCExitButtonView *v = [[LCExitButtonView alloc] initWithFrame:CGRectMake(x, y, size, size)];
    v.backgroundColor        = [UIColor clearColor];
    v.userInteractionEnabled = YES;
    v.layer.zPosition        = 9999.0f;

    UIButton *btn = [UIButton buttonWithType:UIButtonTypeCustom];
    btn.frame     = CGRectMake(0, 0, size, size);

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
        alertControllerWithTitle:@"Return to LiveContainer?"
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

// Transparent container: only the button subview is hittable, not the container itself
- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event {
    UIView *hit = [super hitTest:point withEvent:event];
    return (hit == self) ? nil : hit;
}

@end

// ─────────────────────────────────────────────────────────────
// UIWindow hooks
// ─────────────────────────────────────────────────────────────
static IMP orig_makeKeyAndVisible;
static void hook_makeKeyAndVisible(UIWindow *self, SEL _cmd) {
    ((void (*)(id, SEL))orig_makeKeyAndVisible)(self, _cmd);
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        [LCExitButtonView installInWindow:self];
    });
}

// Hook layoutSubviews: fires after bounds are final, so right-side x is always correct
static IMP orig_layoutSubviews;
static void hook_layoutSubviews(UIWindow *self, SEL _cmd) {
    ((void (*)(id, SEL))orig_layoutSubviews)(self, _cmd);
    if (!self.isKeyWindow) return;
    // Only re-position if a button already exists (don't install on every layout pass)
    for (UIView *sub in self.subviews) {
        if ([sub isKindOfClass:[LCExitButtonView class]]) {
            [LCExitButtonView installInWindow:self];
            break;
        }
    }
}

void LCExitButtonGuestHooksInit(BOOL isLiveProcess) {
    if (isLiveProcess) return;

    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    id stored = [defaults objectForKey:@"LCShowExitButton"];
    BOOL showButton = stored ? [defaults boolForKey:@"LCShowExitButton"] : YES;
    if (!showButton) return;

    Class cls = [UIWindow class];
    Method m1 = class_getInstanceMethod(cls, @selector(makeKeyAndVisible));
    orig_makeKeyAndVisible = method_setImplementation(m1, (IMP)hook_makeKeyAndVisible);
    Method m2 = class_getInstanceMethod(cls, @selector(layoutSubviews));
    orig_layoutSubviews    = method_setImplementation(m2, (IMP)hook_layoutSubviews);
}
