//
//  LCExitButton.m
//  LiveContainer
//
//  Injects a floating exit button on top of the running guest app.
//  The button appears in the guest app's key window and lets the user
//  return to LiveContainer without using the app switcher.
//

#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import "../LCSharedUtils.h"

// Forward declare LCSharedUtils so we can call it from ObjC
@interface LCSharedUtils : NSObject
+ (BOOL)launchToGuestApp;
@end

// ─────────────────────────────────────────────
// The floating exit button view
// ─────────────────────────────────────────────
@interface LCExitButtonView : UIView
@property (nonatomic, strong) UIButton *button;
@property (nonatomic, strong) UIAlertController *pendingAlert;
+ (void)installInWindow:(UIWindow *)window;
@end

@implementation LCExitButtonView

+ (void)installInWindow:(UIWindow *)window {
    if (!window) return;

    // Read prefs from standard UserDefaults (which IS LC's UserDefaults in the guest process)
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    BOOL showButton = [defaults boolForKey:@"LCShowExitButton"];
    // Default to YES if not explicitly set to NO
    if (![defaults objectForKey:@"LCShowExitButton"]) {
        showButton = YES;
    }
    if (!showButton) return;

    // Remove any existing exit button
    for (UIView *subview in window.subviews) {
        if ([subview isKindOfClass:[LCExitButtonView class]]) {
            [subview removeFromSuperview];
        }
    }

    LCExitButtonView *container = [[LCExitButtonView alloc] initWithFrame:CGRectZero];
    container.backgroundColor = [UIColor clearColor];
    container.userInteractionEnabled = YES;
    // Don't intercept touches outside the button
    container.isAccessibilityElement = NO;

    UIButton *btn = [UIButton buttonWithType:UIButtonTypeCustom];
    UIImageSymbolConfiguration *config = [UIImageSymbolConfiguration configurationWithPointSize:26 weight:UIImageSymbolWeightSemibold];
    UIImage *icon = [UIImage systemImageNamed:@"xmark.circle.fill" withConfiguration:config];
    [btn setImage:icon forState:UIControlStateNormal];
    btn.tintColor = [UIColor whiteColor];

    // Dark circular shadow background so it's visible on any app
    btn.layer.shadowColor = [UIColor blackColor].CGColor;
    btn.layer.shadowOffset = CGSizeMake(0, 2);
    btn.layer.shadowRadius = 4;
    btn.layer.shadowOpacity = 0.5;

    [btn addTarget:container action:@selector(exitButtonTapped) forControlEvents:UIControlEventTouchUpInside];
    container.button = btn;
    [container addSubview:btn];

    // Size and position
    CGFloat btnSize = 44;
    BOOL onRight = [defaults boolForKey:@"LCExitButtonPosition"]; // false=left, true=right
    CGFloat safeTop = window.safeAreaInsets.top > 0 ? window.safeAreaInsets.top : 44;
    CGFloat x = onRight
        ? window.bounds.size.width - btnSize - 12
        : 12;
    CGFloat y = safeTop + 8;

    container.frame = CGRectMake(x, y, btnSize, btnSize);
    btn.frame = CGRectMake(0, 0, btnSize, btnSize);

    // Keep it on top — use a very high zPosition
    container.layer.zPosition = 9999;
    [window addSubview:container];
    [window bringSubviewToFront:container];
}

- (void)exitButtonTapped {
    UIWindow *window = self.window;
    UIViewController *rootVC = window.rootViewController;
    // Walk to topmost presented VC
    while (rootVC.presentedViewController) {
        rootVC = rootVC.presentedViewController;
    }

    UIAlertController *alert = [UIAlertController
        alertControllerWithTitle:NSLocalizedString(@"lc.appList.exitAppConfirmTitle", @"Return to LiveContainer?")
        message:NSLocalizedString(@"lc.appList.exitAppConfirmMessage", @"Any unsaved data in the running app may be lost.")
        preferredStyle:UIAlertControllerStyleAlert];

    [alert addAction:[UIAlertAction
        actionWithTitle:NSLocalizedString(@"lc.appList.exitAppConfirmLeave", @"Leave App")
        style:UIAlertActionStyleDestructive
        handler:^(UIAlertAction *action) {
            // launchToGuestApp() with "selected" cleared → relaunches as LiveContainer
            [LCSharedUtils launchToGuestApp];
        }]];

    [alert addAction:[UIAlertAction
        actionWithTitle:NSLocalizedString(@"lc.common.cancel", @"Cancel")
        style:UIAlertActionStyleCancel
        handler:nil]];

    [rootVC presentViewController:alert animated:YES completion:nil];
}

// Only hit-test within our button frame, pass everything else through
- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event {
    UIView *hit = [super hitTest:point withEvent:event];
    if (hit == self) return nil; // transparent container
    return hit;
}

@end

// ─────────────────────────────────────────────
// Hook UIWindow -makeKeyAndVisible to install the button
// when the guest app's window is shown
// ─────────────────────────────────────────────
static IMP original_makeKeyAndVisible;
static void hook_makeKeyAndVisible(UIWindow *self, SEL _cmd) {
    // Call original
    ((void(*)(id,SEL))original_makeKeyAndVisible)(self, _cmd);
    // Install button after a brief delay so the window is fully set up
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.3 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        [LCExitButtonView installInWindow:self];
    });
}

// Re-install if window bounds change (rotation, split-screen resize)
static IMP original_setFrame;
static void hook_setFrame(UIWindow *self, SEL _cmd, CGRect frame) {
    ((void(*)(id,SEL,CGRect))original_setFrame)(self, _cmd, frame);
    if (!self.isKeyWindow) return;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.1 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        [LCExitButtonView installInWindow:self];
    });
}

void LCExitButtonGuestHooksInit(void) {
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    BOOL showButton = [defaults boolForKey:@"LCShowExitButton"];
    if (![defaults objectForKey:@"LCShowExitButton"]) showButton = YES;
    if (!showButton) return;

    Class windowClass = [UIWindow class];

    // Hook makeKeyAndVisible
    Method m1 = class_getInstanceMethod(windowClass, @selector(makeKeyAndVisible));
    original_makeKeyAndVisible = method_setImplementation(m1, (IMP)hook_makeKeyAndVisible);

    // Hook setFrame: to re-position button on rotation
    Method m2 = class_getInstanceMethod(windowClass, @selector(setFrame:));
    original_setFrame = method_setImplementation(m2, (IMP)hook_setFrame);
}
