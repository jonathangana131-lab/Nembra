#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

typedef void (^NembraTuyaSDKUpdateHandler)(BOOL authenticated, NSDictionary * _Nullable dps, NSError * _Nullable error);

/// Narrow Objective-C runtime bridge around Tuya SmartLife SDK APIs used by the
/// authenticated stationary Capture preflight.
///
/// The bridge intentionally exposes only SDK initialization, connection-state
/// observation, DP observation, and disconnect. There is no generic write,
/// publish-DP, pairing, reset, unbind, activation, firmware, or control surface.
@interface NembraTuyaSDKBridge : NSObject

@property (nonatomic, readonly) BOOL sdkAvailable;
@property (nonatomic, readonly) BOOL sdkUserLoggedIn;

- (void)configureWithAppKey:(NSString *)appKey appSecret:(NSString *)appSecret;
- (void)connectDeviceID:(NSString *)deviceID
                   uuid:(NSString *)uuid
              productID:(NSString *)productID
                 update:(NembraTuyaSDKUpdateHandler)update;

/// Reads Tuya's own local BLE connection status for the exact UUID. This is the
/// authority used by the monotonic stability gate; elapsed UI time cannot keep a
/// disconnected session alive.
- (BOOL)isLocallyConnectedUUID:(NSString *)uuid;

- (void)disconnectUUID:(NSString *)uuid;

@end

NS_ASSUME_NONNULL_END
