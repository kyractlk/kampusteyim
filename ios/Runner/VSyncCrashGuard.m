#import <Flutter/Flutter.h>
#import <objc/runtime.h>

/// ProMotion (120Hz) + iOS 26: Flutter engine SIGSEGV in
/// `-[VSyncClient initWithTaskRunner:callback:]` when
/// `createTouchRateCorrectionVSyncClientIfNeeded` runs before the shell/task
/// runner exists (flutter#187565 / #190030).
///
/// `+load` runs at dyld image load — before AppDelegate / any viewDidLoad —
/// so the no-op is in place even if UIScene restores a window early.
@interface FlutterViewController (KampusVSyncGuard)
@end

@implementation FlutterViewController (KampusVSyncGuard)

+ (void)load {
  static dispatch_once_t onceToken;
  dispatch_once(&onceToken, ^{
    Class cls = [FlutterViewController class];
    SEL sel = NSSelectorFromString(@"createTouchRateCorrectionVSyncClientIfNeeded");
    Method method = class_getInstanceMethod(cls, sel);
    if (method == NULL) {
      NSLog(@"[KampüsteyimAPP] VSync guard: selector missing");
      return;
    }
    IMP empty = imp_implementationWithBlock(^void(id _self) {
      // intentionally empty
    });
    method_setImplementation(method, empty);
    NSLog(@"[KampüsteyimAPP] VSync touch-rate client disabled (+load)");
  });
}

@end
