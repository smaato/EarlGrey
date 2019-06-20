//
// Copyright 2017 Google Inc.
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//      http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.
//

#import "GREYPinchAction.h"

#include <tgmath.h>

#import "GREYPathGestureUtils.h"
#import "NSObject+GREYApp.h"
#import "GREYAppError.h"
#import "GREYSyntheticEvents.h"
#import "GREYAllOf.h"
#import "GREYMatchers.h"
#import "GREYNot.h"
#import "GREYSyncAPI.h"
#import "NSObject+GREYCommon.h"
#import "GREYErrorConstants.h"
#import "GREYObjectFormatter.h"
#import "NSError+GREYCommon.h"

/**
 *  Reduce the magnitude of vector in the direction of pinch action to make sure that it is minimum
 *  of either height or width of the view.
 */
static CGFloat const kPinchScale = (CGFloat)0.8;

@implementation GREYPinchAction {
  /**
   *  Pinch direction.
   */
  GREYPinchDirection _pinchDirection;
  /**
   *  The duration within which the pinch action must be completed.
   */
  CFTimeInterval _duration;
  /**
   *  The angle in which in the pinch direction in pointing.
   */
  double _pinchAngle;
  /**
   *  Identifier used for diagnostics.
   */
  NSString *_diagnosticsID;
}

- (instancetype)initWithDirection:(GREYPinchDirection)pinchDirection
                         duration:(CFTimeInterval)duration
                       pinchAngle:(double)pinchAngle {
  NSString *name = [NSString stringWithFormat:@"Pinch %@ for duration %g and angle %f degree",
                                              NSStringFromPinchDirection(pinchDirection), duration,
                                              (pinchAngle * 180.0 / M_PI)];
  id<GREYMatcher> systemAlertShownMatcher = [GREYMatchers matcherForSystemAlertViewShown];
  NSArray *constraintMatchers = @[
    [[GREYNot alloc] initWithMatcher:systemAlertShownMatcher],
    [GREYMatchers matcherForRespondsToSelector:@selector(accessibilityFrame)],
    [GREYMatchers matcherForUserInteractionEnabled],
    [GREYMatchers matcherForInteractable],
  ];
  self = [super initWithName:name
                 constraints:[[GREYAllOf alloc] initWithMatchers:constraintMatchers]];
  if (self) {
    _diagnosticsID = name;
    _pinchDirection = pinchDirection;
    _duration = duration;
    _pinchAngle = pinchAngle;
  }
  return self;
}

#pragma mark - GREYAction

- (BOOL)perform:(id)element error:(__strong NSError **)error {
  __block UIWindow *window = nil;
  __block NSArray *touchPaths = nil;
  grey_dispatch_sync_on_main_thread(^{
    if (![self satisfiesConstraintsForElement:element error:error]) {
      return;
    }

    UIView *viewToPinch =
        [element isKindOfClass:[UIView class]] ? element : [element grey_viewContainingSelf];

    window =
        [viewToPinch isKindOfClass:[UIWindow class]] ? (UIWindow *)viewToPinch : viewToPinch.window;

    if (!window) {
      NSString *errorDescription = [NSString stringWithFormat:
                                                 @"Cannot pinch on view [V], "
                                                 @"as it has no window "
                                                 @"and it isn't a window itself."];
      NSDictionary *glossary = @{@"V" : element};
      I_GREYPopulateErrorNoted(error, kGREYPinchErrorDomain, kGREYPinchFailedErrorCode,
                               errorDescription, glossary);
      return;
    }

    touchPaths = [self calculateTouchPaths:element window:window error:error];
  });

  if (touchPaths) {
    [GREYSyntheticEvents touchAlongMultiplePaths:touchPaths
                                relativeToWindow:window
                                     forDuration:_duration];
  }

  return touchPaths != nil;
}

- (NSArray *)calculateTouchPaths:(UIView *)view
                          window:(UIWindow *)window
                           error:(__strong NSError **)error {
  CGRect pinchActionFrame = CGRectIntersection(view.accessibilityFrame, window.bounds);
  if (CGRectIsNull(pinchActionFrame)) {
    NSMutableDictionary *errorDetails = [[NSMutableDictionary alloc] init];

    errorDetails[kErrorDetailActionNameKey] = self.name;
    errorDetails[kErrorDetailElementKey] = [view grey_description];
    errorDetails[kErrorDetailWindowKey] = window.description;
    errorDetails[kErrorDetailRecoverySuggestionKey] = @"Make sure the element lies in the window";

    NSArray *keyOrder = @[
      kErrorDetailActionNameKey, kErrorDetailElementKey, kErrorDetailWindowKey,
      kErrorDetailRecoverySuggestionKey
    ];

    NSString *reasonDetail = [GREYObjectFormatter formatDictionary:errorDetails
                                                            indent:2
                                                         hideEmpty:YES
                                                          keyOrder:keyOrder];

    NSString *reason = [NSString
        stringWithFormat:@"Cannot apply pinch action on the element. Error: %@\n", reasonDetail];

    I_GREYPopulateErrorNoted(error, kGREYPinchErrorDomain, kGREYPinchFailedErrorCode, reason,
                             @{@"V" : view});

    return nil;
  }

  // Outward pinch starts at the center of pinchActionFrame.
  // Inward pinch ends at the center of pinchActionFrame.
  CGPoint centerPoint =
      CGPointMake(CGRectGetMidX(pinchActionFrame), CGRectGetMidY(pinchActionFrame));

  // End and start points for the two pinch actions points.
  CGPoint endPoint1 = CGPointZero;
  CGPoint endPoint2 = CGPointZero;
  CGPoint startPoint1 = CGPointZero;
  CGPoint startPoint2 = CGPointZero;

  // Scale of the vector to obtain the start and end points from the center of the
  // pinchActionFrame. Make sure that the rotationVectorScale is minimum of the frame width and
  // height. Also decrease the scale length further.
  CGFloat rotationVectorScale = MIN(centerPoint.x, centerPoint.y) * kPinchScale;

  // Rotated points at the given pinch angle to determine start and end points.
  CGPoint rotatedPoint1 =
      [self grey_pointOnCircleAtAngle:_pinchAngle center:centerPoint radius:rotationVectorScale];
  CGPoint rotatedPoint2 = [self grey_pointOnCircleAtAngle:(_pinchAngle + M_PI)
                                                   center:centerPoint
                                                   radius:rotationVectorScale];

  switch (_pinchDirection) {
    case kGREYPinchDirectionOutward:
      startPoint1 = centerPoint;
      startPoint2 = centerPoint;
      endPoint1 = rotatedPoint1;
      endPoint2 = rotatedPoint2;
      break;
    case kGREYPinchDirectionInward:
      startPoint1 = rotatedPoint1;
      startPoint2 = rotatedPoint2;
      endPoint1 = centerPoint;
      endPoint2 = centerPoint;
      break;
  }

  // Based on the @c GREYPinchDirection two touch paths are required to generate a pinch gesture
  // If the pinch direction is @c kGREYPinchDirectionOutward then the two touch paths have their
  // starting points as the center of the view for the gesture and the ending points are on the
  // circle having the touch path as the radius. Similarly when pinch direction is
  // @c kGREYPinchDirectionInward then the two touch paths have starting points on the circle
  // having the touch path as the radius and ending points are the center of the view under
  // test.
  NSArray *touchPathInDirection1 =
      [GREYPathGestureUtils touchPathForDragGestureWithStartPoint:startPoint1
                                                         endPoint:endPoint1
                                                    cancelInertia:NO];
  NSArray *touchPathInDirection2 =
      [GREYPathGestureUtils touchPathForDragGestureWithStartPoint:startPoint2
                                                         endPoint:endPoint2
                                                    cancelInertia:NO];
  return @[ touchPathInDirection1, touchPathInDirection2 ];
}

#pragma mark - private

/**
 *  Returns a point at an @c angle on a circle having @c center and @c radius.
 *
 *  @param angle   Angle to which a point is to be located on the given circle.
 *  @param center  Center of the circle.
 *  @param radius  Radius of the circle.
 */
- (CGPoint)grey_pointOnCircleAtAngle:(double)angle center:(CGPoint)center radius:(CGFloat)radius {
  return CGPointMake(center.x + (CGFloat)(radius * cos(angle)),
                     center.y + (CGFloat)(radius * sin(angle)));
}

#pragma mark - GREYDiagnosable

- (NSString *)diagnosticsID {
  return _diagnosticsID;
}

@end