#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN
BOOL IceNativeMenuBarAvailable(void);
id _Nullable IceActivateMenuBarAssertion(NSArray<NSString *> *allowedBundles,
                                       NSArray<NSNumber *> *allowedSystemItems,
                                       void (^completion)(NSError * _Nullable));
void IceInvalidateMenuBarAssertion(id _Nullable assertion);
NS_ASSUME_NONNULL_END
