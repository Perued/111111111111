#import <UIKit/UIKit.h>

static void autoTapConfirmButton(UIView *view) {
    for (UIView *subview in view.subviews) {
        if ([subview isKindOfClass:[UIButton class]]) {
            UIButton *btn = (UIButton *)subview;
            NSString *title = [btn titleForState:UIControlStateNormal];
            if (title && [title containsString:@"确认抢单"]) {
                dispatch_async(dispatch_get_main_queue(), ^{
                    [btn sendActionsForControlEvents:UIControlEventTouchUpInside];
                });
                return;
            }
        }
        autoTapConfirmButton(subview);
    }
}

%hook UIViewController
- (void)viewDidAppear:(BOOL)animated {
    %orig;
    NSString *bundleID = [[NSBundle mainBundle] bundleIdentifier];
    if ([bundleID isEqualToString:@"com.dada.staff"]) {
        autoTapConfirmButton(self.view);
    }
}
%end
