//
//  LCExitButton.m
//  LiveContainer
//
//  Injects a floating exit button on top of the running guest app (normal mode only).
//  In multitask (LiveProcess) mode, pass isLiveProcess=YES to skip installation.
//

#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import "../LCSharedUtils.h"

// ─────────────────────────────────────────────────────────────
// Floating container — passes all touches through except the button
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

    // Use window.bounds for width — correct for this window's actual size.
    // If the window hasn't laid out yet, schedule a retry instead of guessing.
    CGFloat winW = window.bounds.size.width;
    if (winW <= 0) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.3 * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{
            [LCExitButtonView installInWindow:window];
        });
        return;
    }

    BOOL onRight   = [defaults boolForKey:@"LCExitButtonPosition"];
    CGFloat size   = 44.0f;
    CGFloat safeTop = window.safeAreaInsets.top > 0 ? window.safeAreaInsets.top : 44.0f;
    CGFloat x = onRight ? (winW - size - 12.0f) : 12.0f;
    CGFloat y = safeTop + 8.0f;

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

    [btn addTarget:v action:@selector(exitButtonTapped) forControlEvents:UIControlEventTouchUpInside];
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
            // Get the LC URL scheme via LCSharedUtils (already imported).
            // We cannot use the lcAppUrlScheme extern inside a block — use the API instead.
            // [LCSharedUtils lcUrlSchemes] returns @[@"livecontainer", @"livecontainer2", ...]
            // The actual scheme for this instance is its first CFBundleURLSchemes entry.
            NSArray<NSString *> *schemes = NSBundle.mainBundle.infoDictionary
                                               [@"CFBundleURLTypes"][0][@"CFBundleURLSchemes"];
            NSString *scheme = schemes.firstObject ?: @"livecontainer";
            NSString *urlStr = [NSString stringWithFormat:@"%@://livecontainer-relaunch", scheme];
            NSURL *url       = [NSURL URLWithString:urlStr];
            UIApplication *app = [NSClassFromString(@"UIApplication") sharedApplication];
            // Open without canOpenURL check — the guest's plist doesn't list our scheme
            // in LSApplicationQueriesSchemes, so canOpenURL always returns NO.
            // The open still succeeds on sideloaded apps.
            [app openURL:url options:@{} completionHandler:^(BOOL success) {
                // Whether or not the URL open succeeded, terminate this process.
                // iOS has already queued the LC relaunch request.
                exit(0);
            }];
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

// ─────────────────────────────────────────────────────────────
// UIWindow hooks — installed only in normal (non-multitask) mode
// ─────────────────────────────────────────────────────────────
static IMP orig_makeKeyAndVisible;
static void hook_makeKeyAndVisible(UIWindow *self, SEL _cmd) {
    ((void (*)(id, SEL))orig_makeKeyAndVisible)(self, _cmd);
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.4 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        [LCExitButtonView installInWindow:self];
    });
}

static IMP orig_setFrame;
static void hook_setFrame(UIWindow *self, SEL _cmd, CGRect frame) {
    ((void (*)(id, SEL, CGRect))orig_setFrame)(self, _cmd, frame);
    if (!self.isKeyWindow) return;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.15 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        [LCExitButtonView installInWindow:self];
    });
}

// ─────────────────────────────────────────────────────────────
// Entry point — isLiveProcess is passed from LCBootstrap where it is
// correctly set BEFORE overwriteMainCFBundle() changes NSBundle.mainBundle.
// ─────────────────────────────────────────────────────────────
void LCExitButtonGuestHooksInit(BOOL isLiveProcess) {
    if (isLiveProcess) return;  // Multitask handled by MultitaskAppWindow.swift

    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    id stored = [defaults objectForKey:@"LCShowExitButton"];
    BOOL showButton = stored ? [defaults boolForKey:@"LCShowExitButton"] : YES;
    if (!showButton) return;

    Class cls = [UIWindow class];
    Method m1 = class_getInstanceMethod(cls, @selector(makeKeyAndVisible));
    orig_makeKeyAndVisible = method_setImplementation(m1, (IMP)hook_makeKeyAndVisible);
    Method m2 = class_getInstanceMethod(cls, @selector(setFrame:));
    orig_setFrame = method_setImplementation(m2, (IMP)hook_setFrame);
}
