//
//  LCExitButton.m
//  LiveContainer
//
//  Injects a floating exit button on top of the running guest app (normal mode only).
//  In multitask (LiveProcess) mode this file does nothing — MultitaskAppWindow.swift
//  handles the exit button for that case.
//

#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import "../LCSharedUtils.h"

// ─────────────────────────────────────────────────────────────
// Returns YES when running as LiveProcess (multitask extension).
// In that case we skip installing the ObjC button entirely.
// ─────────────────────────────────────────────────────────────
static BOOL lceb_isLiveProcess(void) {
    NSString *bundlePath = [NSBundle mainBundle].bundlePath;
    return [bundlePath containsString:@"LiveProcess.appex"];
}

// ─────────────────────────────────────────────────────────────
// Floating container view
// ─────────────────────────────────────────────────────────────
@interface LCExitButtonView : UIView
+ (void)installInWindow:(UIWindow *)window;
@end

@implementation LCExitButtonView

+ (void)installInWindow:(UIWindow *)window {
    if (!window) return;
    // Never install in multitask/LiveProcess mode — handled by SwiftUI
    if (lceb_isLiveProcess()) return;

    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    id stored = [defaults objectForKey:@"LCShowExitButton"];
    BOOL showButton = stored ? [defaults boolForKey:@"LCShowExitButton"] : YES;
    if (!showButton) return;

    // Remove any existing instance first
    for (UIView *sub in [window.subviews copy]) {
        if ([sub isKindOfClass:[LCExitButtonView class]]) {
            [sub removeFromSuperview];
        }
    }

    BOOL onRight = [defaults boolForKey:@"LCExitButtonPosition"];
    CGFloat btnSize = 44.0f;

    // Use screen bounds for width so right-side position is always correct
    // even when the window frame hasn't been fully laid out yet
    CGFloat screenWidth = [UIScreen mainScreen].bounds.size.width;
    CGFloat safeTop = window.safeAreaInsets.top > 0 ? window.safeAreaInsets.top : 44.0f;
    CGFloat x = onRight ? (screenWidth - btnSize - 12.0f) : 12.0f;
    CGFloat y = safeTop + 8.0f;

    LCExitButtonView *container = [[LCExitButtonView alloc]
        initWithFrame:CGRectMake(x, y, btnSize, btnSize)];
    container.backgroundColor        = [UIColor clearColor];
    container.userInteractionEnabled = YES;
    container.layer.zPosition        = 9999.0f;

    UIButton *btn = [UIButton buttonWithType:UIButtonTypeCustom];
    btn.frame = CGRectMake(0, 0, btnSize, btnSize);

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

    [btn addTarget:container
            action:@selector(exitButtonTapped)
  forControlEvents:UIControlEventTouchUpInside];
    [container addSubview:btn];
    [window addSubview:container];
    [window bringSubviewToFront:container];
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

    __weak typeof(self) weakSelf = self;
    [alert addAction:[UIAlertAction
        actionWithTitle:@"Leave App"
        style:UIAlertActionStyleDestructive
        handler:^(UIAlertAction *_) {
            (void)weakSelf; // silence unused warning
            // Open the LC relaunch URL scheme, then exit.
            // "selected" was already cleared by LCBootstrap before invokeAppMain,
            // so LC will start fresh showing its app list.
            NSArray<NSString*> *schemes = [LCSharedUtils lcUrlSchemes];
            NSString *scheme = schemes.firstObject ?: @"livecontainer";
            NSString *urlStr = [NSString stringWithFormat:@"%@://livecontainer-relaunch", scheme];
            NSURL *url = [NSURL URLWithString:urlStr];
            UIApplication *app = [NSClassFromString(@"UIApplication") sharedApplication];
            if ([app canOpenURL:url]) {
                [app openURL:url options:@{} completionHandler:^(BOOL success) {
                    exit(0);
                }];
            } else {
                // URL scheme not available — just exit, iOS will handle returning to LC
                exit(0);
            }
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
// UIWindow hooks
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
// Entry point
// ─────────────────────────────────────────────────────────────
void LCExitButtonGuestHooksInit(void) {
    // Skip entirely in LiveProcess / multitask mode
    if (lceb_isLiveProcess()) return;

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
