//
//  LCExitButton.m
//  LiveContainer
//
//  Injects a floating exit button on top of the running guest app (normal mode only).
//  Pass isLiveProcess=YES to skip (multitask handled by MultitaskAppWindow.swift).
//

#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import "../LCSharedUtils.h"

// ─────────────────────────────────────────────────────────────
// Floating container — transparent to all touches except the button
// ─────────────────────────────────────────────────────────────
@interface LCExitButtonView : UIView
@property (nonatomic, assign) BOOL onRight;
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
        // Window not laid out yet — retry after a short delay
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
    v.onRight                = onRight;

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
            // Use LCSharedUtils.launchToGuestApp — the proven LC relaunch mechanism.
            // It opens the LC URL scheme twice then raises SIGKILL, which iOS
            // handles by launching a fresh LC instance. The process termination
            // will look like a crash in debuggers but is correct and intentional.
            [LCSharedUtils launchToGuestApp];
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
// Hooks — set BEFORE the guest app's libraries initialise
// ─────────────────────────────────────────────────────────────
static IMP orig_makeKeyAndVisible;
static void hook_makeKeyAndVisible(UIWindow *self, SEL _cmd) {
    ((void (*)(id, SEL))orig_makeKeyAndVisible)(self, _cmd);
    // Install after the runloop has had a chance to lay out the window
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        [LCExitButtonView installInWindow:self];
    });
}

static IMP orig_layoutSubviews;
static void hook_layoutSubviews(UIWindow *self, SEL _cmd) {
    ((void (*)(id, SEL))orig_layoutSubviews)(self, _cmd);
    if (!self.isKeyWindow) return;
    // Re-install whenever the window re-lays out (rotation, size change)
    // Only if there is already an exit button present (avoids double-install on first layout)
    BOOL hasButton = NO;
    for (UIView *sub in self.subviews) {
        if ([sub isKindOfClass:[LCExitButtonView class]]) { hasButton = YES; break; }
    }
    if (hasButton) {
        [LCExitButtonView installInWindow:self];
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

    // Hook layoutSubviews instead of setFrame: — fires AFTER bounds are final
    Method m2 = class_getInstanceMethod(cls, @selector(layoutSubviews));
    orig_layoutSubviews = method_setImplementation(m2, (IMP)hook_layoutSubviews);
}
