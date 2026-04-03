//
//  LCExitButton.m
//  LiveContainer
//
//  Injects a floating exit button on top of the running guest app.
//  The button appears in the guest app's key window, letting the user
//  return to LiveContainer without using the app switcher.
//

#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import "../LCSharedUtils.h"

// ─────────────────────────────────────────────────────────────
// Floating container view — transparent to all touches except
// those that land directly on the exit button.
// ─────────────────────────────────────────────────────────────
@interface LCExitButtonView : UIView
+ (void)installInWindow:(UIWindow *)window;
@end

@implementation LCExitButtonView

+ (void)installInWindow:(UIWindow *)window {
    if (!window) return;

    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    // Default to enabled if the key has never been written
    id stored = [defaults objectForKey:@"LCShowExitButton"];
    BOOL showButton = stored ? [defaults boolForKey:@"LCShowExitButton"] : YES;
    if (!showButton) return;

    // Remove any stale instance before adding a fresh one
    for (UIView *sub in [window.subviews copy]) {
        if ([sub isKindOfClass:[LCExitButtonView class]]) {
            [sub removeFromSuperview];
        }
    }

    BOOL onRight = [defaults boolForKey:@"LCExitButtonPosition"];
    CGFloat btnSize  = 44.0f;
    CGFloat safeTop  = window.safeAreaInsets.top > 0 ? window.safeAreaInsets.top : 44.0f;
    CGFloat x = onRight ? (window.bounds.size.width - btnSize - 12.0f) : 12.0f;
    CGFloat y = safeTop + 8.0f;

    LCExitButtonView *container = [[LCExitButtonView alloc]
        initWithFrame:CGRectMake(x, y, btnSize, btnSize)];
    container.backgroundColor     = [UIColor clearColor];
    container.userInteractionEnabled = YES;
    container.layer.zPosition     = 9999.0f;

    UIButton *btn = [UIButton buttonWithType:UIButtonTypeCustom];
    btn.frame     = CGRectMake(0, 0, btnSize, btnSize);

    if (@available(iOS 13.0, *)) {
        UIImageSymbolConfiguration *cfg = [UIImageSymbolConfiguration
            configurationWithPointSize:26 weight:UIImageSymbolWeightSemibold];
        [btn setImage:[UIImage systemImageNamed:@"xmark.circle.fill"
                                withConfiguration:cfg]
             forState:UIControlStateNormal];
        btn.tintColor = [UIColor whiteColor];
    } else {
        // Fallback: plain X label for iOS < 13 (shouldn't occur, LC targets iOS 14+)
        [btn setTitle:@"✕" forState:UIControlStateNormal];
        [btn setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
        btn.titleLabel.font = [UIFont boldSystemFontOfSize:20];
    }

    // Drop shadow so the icon stands out on any background
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

    // Use hardcoded English strings as fallback — LC's bundle isn't the main bundle
    // inside the guest process, so NSLocalizedString keys won't resolve.
    UIAlertController *alert = [UIAlertController
        alertControllerWithTitle:@"Return to LiveContainer?"
        message:@"Any unsaved data in the running app may be lost."
        preferredStyle:UIAlertControllerStyleAlert];

    [alert addAction:[UIAlertAction
        actionWithTitle:@"Leave App"
        style:UIAlertActionStyleDestructive
        handler:^(UIAlertAction *_) {
            // "selected" was already cleared by LCBootstrap before invokeAppMain,
            // so launchToGuestApp() will relaunch the process as LiveContainer itself.
            [LCSharedUtils launchToGuestApp];
        }]];

    [alert addAction:[UIAlertAction
        actionWithTitle:@"Cancel"
        style:UIAlertActionStyleCancel
        handler:nil]];

    [rootVC presentViewController:alert animated:YES completion:nil];
}

// Pass all touches through except those landing on a direct subview (the button)
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
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.3 * NSEC_PER_SEC)),
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
// Entry point — called from LCBootstrap before invokeAppMain
// ─────────────────────────────────────────────────────────────
void LCExitButtonGuestHooksInit(void) {
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
