#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>

double animationDurationFactorImpl();

CABasicAnimation * _Nonnull makeSpringAnimationImpl(NSString * _Nonnull keyPath, double duration);
CABasicAnimation * _Nonnull make26SpringAnimationImpl(NSString * _Nonnull keyPath, double duration);
CASpringAnimation * _Nonnull makeSpringBounceAnimationImpl(NSString * _Nonnull keyPath, CGFloat initialVelocity, CGFloat damping);
CGFloat springAnimationValueAtImpl(CABasicAnimation * _Nonnull animation, CGFloat t);

UIBlurEffect * _Nonnull makeCustomZoomBlurEffectImpl(bool isLight);
void applySmoothRoundedCornersImpl(CALayer * _Nonnull layer);

@protocol UIKitPortalViewProtocol <NSObject>

@property(nonatomic) __weak UIView * _Nullable sourceView;
@property(nonatomic) _Bool forwardsClientHitTestingToSourceView;
@property(nonatomic) _Bool allowsHitTesting; // @dynamic allowsHitTesting;
@property(nonatomic) _Bool allowsBackdropGroups; // @dynamic allowsBackdropGroups;
@property(nonatomic) _Bool matchesPosition; // @dynamic matchesPosition;
@property(nonatomic) _Bool matchesTransform; // @dynamic matchesTransform;
@property(nonatomic) _Bool matchesAlpha; // @dynamic matchesAlpha;
@property(nonatomic) _Bool hidesSourceView; // @dynamic hidesSourceView;

@end

UIView<UIKitPortalViewProtocol> * _Nullable makePortalView(bool matchPosition);
bool isViewPortalView(UIView * _Nonnull view);
UIView * _Nullable getPortalViewSourceView(UIView * _Nonnull portalView);

NSObject * _Nullable makeBlurFilter();
NSObject * _Nullable makeVariableBlurFilter();
NSObject * _Nullable makeLuminanceToAlphaFilter();
NSObject * _Nullable makeColorInvertFilter();
NSObject * _Nullable makeMonochromeFilter();
NSObject * _Nullable makeDisplacementMapFilter();
NSObject * _Nullable makeColorMatrixFilter();

void setLayerDisableScreenshots(CALayer * _Nonnull layer, bool disableScreenshots);
bool getLayerDisableScreenshots(CALayer * _Nonnull layer);

// SuperGram: screen capture of protected (noforwards) content.
// setLayerDisableScreenshots stays strict; callers split their flag into a secret part and a copy-protected part.
// Secret chats, self-destructing / view-once media, paid media and login codes are always protected.
// sgAllowScreenCaptureProtected: NSUserDefaults.standardUserDefaults key "sgAllowScreenCaptureProtected", default true (cached).
bool sgAllowScreenCaptureProtected(void);
// Final flag value: isSecret || (isCopyProtected && !sgAllowScreenCaptureProtected()).
bool sgShouldDisableScreenCapture(bool isSecret, bool isCopyProtected) NS_SWIFT_NAME(sgShouldDisableScreenCapture(isSecret:isCopyProtected:));
// setLayerDisableScreenshots(layer, sgShouldDisableScreenCapture(isSecret, isCopyProtected)).
void setLayerDisableScreenshotsForContent(CALayer * _Nonnull layer, bool isSecret, bool isCopyProtected) NS_SWIFT_NAME(setLayerDisableScreenshotsForContent(_:isSecret:isCopyProtected:));

void setLayerContentsMaskMode(CALayer * _Nonnull layer, bool maskMode);

void setMonochromaticEffectImpl(UIView * _Nonnull view, bool isEnabled);
