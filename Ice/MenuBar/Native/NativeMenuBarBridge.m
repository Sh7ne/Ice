// MenuBarClientCore selectors verified against macOS 27.0 (26A428).
// API discovery reference: fif7y/Pelmet, MBAssessmentShim.m (GPL-3.0).
#import "NativeMenuBarBridge.h"
#import <dlfcn.h>
#import <objc/message.h>

static Class configurationClass;
static Class assertionClass;

BOOL IceNativeMenuBarAvailable(void) {
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        if (!dlopen("/System/Library/PrivateFrameworks/MenuBarClientCore.framework/MenuBarClientCore", RTLD_LAZY)) {
            return;
        }
        configurationClass = NSClassFromString(@"MBAssessmentModeConfiguration");
        assertionClass = NSClassFromString(@"MBAssessmentModeAssertion");
    });
    return [configurationClass instancesRespondToSelector:NSSelectorFromString(@"initWithAllowedSystemItems:allowedBundleIdentifiers:")] &&
           [assertionClass instancesRespondToSelector:NSSelectorFromString(@"activateWithConfiguration:completionHandler:")] &&
           [assertionClass instancesRespondToSelector:NSSelectorFromString(@"invalidate")];
}

id IceActivateMenuBarAssertion(NSArray<NSString *> *allowedBundles, NSArray<NSNumber *> *allowedSystemItems,
                              void (^completion)(NSError *)) {
    if (!IceNativeMenuBarAvailable()) { return nil; }
    @try {
        // Keep the clock and Control Center regardless of persisted input.
        NSMutableSet *systemItems = [NSMutableSet setWithArray:allowedSystemItems];
        [systemItems addObjectsFromArray:@[@2, @8]];
        id (*initialize)(id, SEL, NSArray *, NSArray *) = (void *)objc_msgSend;
        id configuration = initialize([configurationClass alloc],
            NSSelectorFromString(@"initWithAllowedSystemItems:allowedBundleIdentifiers:"),
            systemItems.allObjects, allowedBundles);
        id assertion = [[assertionClass alloc] init];
        if (!configuration || !assertion) { return nil; }
        void (*activate)(id, SEL, id, void (^)(NSError *)) = (void *)objc_msgSend;
        activate(assertion, NSSelectorFromString(@"activateWithConfiguration:completionHandler:"),
                 configuration, completion);
        return assertion;
    } @catch (NSException *exception) {
        completion([NSError errorWithDomain:@"Ice.NativeMenuBar" code:1
                                  userInfo:@{NSLocalizedDescriptionKey: exception.reason ?: @"Menu bar activation failed"}]);
        return nil;
    }
}

void IceInvalidateMenuBarAssertion(id assertion) {
    @try {
        SEL selector = NSSelectorFromString(@"invalidate");
        if ([assertion respondsToSelector:selector]) {
            ((void (*)(id, SEL))objc_msgSend)(assertion, selector);
        }
    } @catch (NSException *exception) {
        NSLog(@"Ice: menu bar restoration failed: %@", exception.reason);
    }
}
