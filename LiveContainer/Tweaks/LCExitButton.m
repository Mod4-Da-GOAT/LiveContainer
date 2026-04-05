//
//  LCExitButton.m
//  LiveContainer
//
//  Injects a floating exit button on top of the running guest app (normal mode only).
//  Pass isLiveProcess=YES to skip; multitask is handled by MultitaskAppWindow.swift.
//

#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <signal.h>
#import "../LCSharedUtils.h"

// ─── Externs from LCBootstrap.m ──────────────────────────────
// These are captured at LCExitButtonGuestHooksInit() time, BEFORE
// overwriteMainCFBundle() changes NSBundle.mainBundle to the guest app
// and BEFORE NUDGuestHooksInit() redirects standardUserDefaults.
extern NSString       *lcAppUrlScheme;
extern NSUserDefaults *lcUserDefaults;

// Saved at init time so they remain valid after the bundle/defaults swap.
static NSString       *g_lcScheme     = nil;
static NSUserDefaults *g_lcDefaults   = nil;

// ─── Relaunch LC ─────────────────────────────────────────────
// Opens the LC URL scheme directly (bypassing canOpenURL which always
// returns NO from inside the guest because livecontainer:// is not in
// the guest app's LSApplicationQueriesSchemes) then kills this process.
// iOS processes the queued open request and launches a fresh LC instance.
static void lceb_relaunchLC(void) {
    NSString *scheme = g_lcScheme ?: @"livecontainer";
    NSURL    *url    = [NSURL URLWithString:
                        [NSString stringWithFormat:@"%@://livecontainer-relaunch", scheme]];
    UIApplication *app = [NSClassFromString(@"UIApplication") sharedApplication];

    // Two opens, same as launchToGuestApp(tries=2)
    [app openURL:url options:@{} completionHandler:nil];
    [app openURL:url options:@{} completionHandler:nil];

    // Short delay so iOS can queue the request, then kill this process
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.1 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
#if defined(__arm64__)
        __asm__ __volatile__(
            "mov x0, #31\n"
            "mov x16, #26\n"
            "svc #0x80\n"
        );
#endif
        raise(SIGKILL);
    });
}

// ─── Floating overlay view ────────────────────────────────────
@interface LCExitButtonView : UIView
+ (void)installInWindow:(UIWindow *)window;
@end

@implementation LCExitButtonView

+ (void)installInWindow:(UIWindow *)window {
    if (!window || !g_lcDefaults) return;

    // Read prefs from the REAL LC UserDefaults (g_lcDefaults),
    // not from standardUserDefaults which is redirected to the guest container.
    id stored = [g_lcDefaults objectForKey:@"LCShowExitButton"];
    BOOL showButton = stored ? [g_lcDefaults boolForKey:@"LCShowExitButton"] : YES;
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

- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event {
    UIView *hit = [super hitTest:point withEvent:event];
    return (hit == self) ? nil : hit;
}

@end

// ─── UIWindow hooks ───────────────────────────────────────────
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

// ─── Entry point ──────────────────────────────────────────────
// Called from LCBootstrap BEFORE overwriteMainCFBundle() and
// BEFORE NUDGuestHooksInit() so that both globals are still valid.
void LCExitButtonGuestHooksInit(BOOL isLiveProcess) {
    if (isLiveProcess) return;

    // Capture LC's scheme and defaults NOW — before the guest bundle/defaults swap
    g_lcScheme   = [lcAppUrlScheme copy];
    g_lcDefaults = lcUserDefaults;

    // Check the real LC prefs before deciding whether to install hooks
    id stored = [g_lcDefaults objectForKey:@"LCShowExitButton"];
    BOOL showButton = stored ? [g_lcDefaults boolForKey:@"LCShowExitButton"] : YES;
    if (!showButton) return;

    Class cls = [UIWindow class];
    Method m1 = class_getInstanceMethod(cls, @selector(makeKeyAndVisible));
    orig_makeKeyAndVisible = method_setImplementation(m1, (IMP)hook_makeKeyAndVisible);
    Method m2 = class_getInstanceMethod(cls, @selector(layoutSubviews));
    orig_layoutSubviews    = method_setImplementation(m2, (IMP)hook_layoutSubviews);
}
