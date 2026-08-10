#import "NembraTuyaSDKBridge.h"
#import <objc/message.h>
#import <objc/runtime.h>

static NSString * const NembraTuyaSDKBridgeErrorDomain = @"NembraTuyaSDKBridge";

@interface NembraTuyaSDKBridge ()
@property (nonatomic, copy, nullable) NembraTuyaSDKUpdateHandler updateHandler;
@property (nonatomic, strong, nullable) id observedDevice;
@property (nonatomic, copy, nullable) NSString *currentUUID;
@end

@implementation NembraTuyaSDKBridge

- (BOOL)sdkAvailable {
    return NSClassFromString(@"ThingSmartSDK") != Nil &&
           NSClassFromString(@"ThingSmartBLEManager") != Nil &&
           NSClassFromString(@"ThingSmartDevice") != Nil &&
           NSClassFromString(@"ThingSmartUser") != Nil;
}

- (BOOL)sdkUserLoggedIn {
    Class userClass = NSClassFromString(@"ThingSmartUser");
    if (userClass == Nil) { return NO; }

    SEL sharedSelector = NSSelectorFromString(@"sharedInstance");
    if (![userClass respondsToSelector:sharedSelector]) { return NO; }
    id (*sharedSend)(id, SEL) = (void *)objc_msgSend;
    id user = sharedSend((id)userClass, sharedSelector);
    if (user == nil) { return NO; }

    SEL loginSelector = NSSelectorFromString(@"isLogin");
    if (![user respondsToSelector:loginSelector]) { return NO; }
    BOOL (*boolSend)(id, SEL) = (void *)objc_msgSend;
    return boolSend(user, loginSelector);
}

- (void)configureWithAppKey:(NSString *)appKey appSecret:(NSString *)appSecret {
    if (appKey.length == 0 || appSecret.length == 0) { return; }
    Class sdkClass = NSClassFromString(@"ThingSmartSDK");
    if (sdkClass == Nil) { return; }

    SEL sharedSelector = NSSelectorFromString(@"sharedInstance");
    if (![sdkClass respondsToSelector:sharedSelector]) { return; }
    id (*sharedSend)(id, SEL) = (void *)objc_msgSend;
    id sdk = sharedSend((id)sdkClass, sharedSelector);
    if (sdk == nil) { return; }

    SEL startSelector = NSSelectorFromString(@"startWithAppKey:secretKey:");
    if (![sdk respondsToSelector:startSelector]) { return; }
    void (*startSend)(id, SEL, NSString *, NSString *) = (void *)objc_msgSend;
    startSend(sdk, startSelector, appKey, appSecret);
}

- (void)connectDeviceID:(NSString *)deviceID
                   uuid:(NSString *)uuid
              productID:(NSString *)productID
                 update:(NembraTuyaSDKUpdateHandler)update {
    self.updateHandler = update;
    self.currentUUID = [uuid copy];

    if (!self.sdkAvailable) {
        [self emitErrorCode:1 description:@"Tuya SmartLife SDK is not linked into this Capture build."];
        return;
    }
    if (!self.sdkUserLoggedIn) {
        [self emitErrorCode:2 description:@"Tuya SmartLife SDK does not have an authorized user session."];
        return;
    }
    if (deviceID.length == 0 || uuid.length == 0 || productID.length == 0) {
        [self emitErrorCode:3 description:@"The bound scooter identity is incomplete."];
        return;
    }

    Class deviceClass = NSClassFromString(@"ThingSmartDevice");
    SEL factorySelector = NSSelectorFromString(@"deviceWithDeviceId:");
    if (deviceClass != Nil && [deviceClass respondsToSelector:factorySelector]) {
        id (*factorySend)(id, SEL, NSString *) = (void *)objc_msgSend;
        id device = factorySend((id)deviceClass, factorySelector, deviceID);
        if (device != nil) {
            self.observedDevice = device;
            SEL delegateSelector = NSSelectorFromString(@"setDelegate:");
            if ([device respondsToSelector:delegateSelector]) {
                void (*delegateSend)(id, SEL, id) = (void *)objc_msgSend;
                delegateSend(device, delegateSelector, self);
            }
        }
    }

    Class managerClass = NSClassFromString(@"ThingSmartBLEManager");
    SEL sharedSelector = NSSelectorFromString(@"sharedInstance");
    if (managerClass == Nil || ![managerClass respondsToSelector:sharedSelector]) {
        [self emitErrorCode:4 description:@"Tuya BLE manager is unavailable."];
        return;
    }

    id (*sharedSend)(id, SEL) = (void *)objc_msgSend;
    id manager = sharedSend((id)managerClass, sharedSelector);
    SEL connectSelector = NSSelectorFromString(@"connectBLEWithUUID:productKey:success:failure:");
    if (manager == nil || ![manager respondsToSelector:connectSelector]) {
        [self emitErrorCode:5 description:@"This Tuya SDK build does not expose the documented existing-device BLE connection API."];
        return;
    }

    __weak typeof(self) weakSelf = self;
    void (^success)(void) = ^{
        __strong typeof(weakSelf) self = weakSelf;
        if (self == nil) { return; }
        if (![self isLocallyConnectedUUID:uuid]) {
            [self emitErrorCode:7 description:@"Tuya reported connect success, but its local BLE state does not show the scooter connected."];
            return;
        }
        if (self.updateHandler != nil) {
            self.updateHandler(YES, nil, nil);
        }
    };
    void (^failure)(NSError *) = ^(NSError *error) {
        __strong typeof(weakSelf) self = weakSelf;
        if (self == nil) { return; }
        NSError *reported = error ?: [NSError errorWithDomain:NembraTuyaSDKBridgeErrorDomain
                                                         code:6
                                                     userInfo:@{NSLocalizedDescriptionKey: @"Tuya rejected the authenticated BLE connection."}];
        if (self.updateHandler != nil) {
            self.updateHandler(NO, nil, reported);
        }
    };

    void (*connectSend)(id, SEL, NSString *, NSString *, void (^)(void), void (^)(NSError *)) = (void *)objc_msgSend;
    connectSend(manager, connectSelector, uuid, productID, success, failure);
}

- (BOOL)isLocallyConnectedUUID:(NSString *)uuid {
    if (uuid.length == 0) { return NO; }
    Class managerClass = NSClassFromString(@"ThingSmartBLEManager");
    SEL sharedSelector = NSSelectorFromString(@"sharedInstance");
    if (managerClass == Nil || ![managerClass respondsToSelector:sharedSelector]) { return NO; }

    id (*sharedSend)(id, SEL) = (void *)objc_msgSend;
    id manager = sharedSend((id)managerClass, sharedSelector);
    SEL statusSelector = NSSelectorFromString(@"deviceStatueWithUUID:");
    if (manager == nil || ![manager respondsToSelector:statusSelector]) { return NO; }

    BOOL (*statusSend)(id, SEL, NSString *) = (void *)objc_msgSend;
    return statusSend(manager, statusSelector, uuid);
}

- (void)disconnectUUID:(NSString *)uuid {
    Class managerClass = NSClassFromString(@"ThingSmartBLEManager");
    SEL sharedSelector = NSSelectorFromString(@"sharedInstance");
    if (managerClass == Nil || ![managerClass respondsToSelector:sharedSelector]) {
        self.observedDevice = nil;
        self.currentUUID = nil;
        self.updateHandler = nil;
        return;
    }
    id (*sharedSend)(id, SEL) = (void *)objc_msgSend;
    id manager = sharedSend((id)managerClass, sharedSelector);
    SEL disconnectSelector = NSSelectorFromString(@"disconnectBLEWithUUID:success:failure:");
    if (manager != nil && [manager respondsToSelector:disconnectSelector]) {
        void (^success)(void) = ^{};
        void (^failure)(NSError *) = ^(NSError *error) { (void)error; };
        void (*disconnectSend)(id, SEL, NSString *, void (^)(void), void (^)(NSError *)) = (void *)objc_msgSend;
        disconnectSend(manager, disconnectSelector, uuid, success, failure);
    }

    self.observedDevice = nil;
    self.currentUUID = nil;
    self.updateHandler = nil;
}

// ThingSmartDeviceDelegate selector. Kept untyped on purpose so this source still
// compiles in the standalone no-SDK build while becoming active when the official
// SDK is linked into the private field build.
- (void)device:(id)device dpsUpdate:(NSDictionary *)dps {
    (void)device;
    NSString *uuid = self.currentUUID;
    if (uuid.length == 0 || ![self isLocallyConnectedUUID:uuid]) {
        [self emitErrorCode:8 description:@"A Tuya device update arrived without a live local BLE session; it was not admitted as physical application evidence."];
        return;
    }
    if (self.updateHandler != nil && dps.count > 0) {
        self.updateHandler(YES, dps, nil);
    }
}

- (void)deviceOnlineUpdate:(id)device {
    (void)device;
    NSString *uuid = self.currentUUID;
    if (uuid.length == 0 || ![self isLocallyConnectedUUID:uuid]) {
        [self emitErrorCode:9 description:@"Tuya reports that the local BLE session is no longer connected."];
        return;
    }
    if (self.updateHandler != nil) {
        self.updateHandler(YES, nil, nil);
    }
}

- (void)emitErrorCode:(NSInteger)code description:(NSString *)description {
    NSError *error = [NSError errorWithDomain:NembraTuyaSDKBridgeErrorDomain
                                         code:code
                                     userInfo:@{NSLocalizedDescriptionKey: description}];
    if (self.updateHandler != nil) {
        self.updateHandler(NO, nil, error);
    }
}

@end
