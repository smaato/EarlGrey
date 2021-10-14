//
// Copyright 2016 Google Inc.
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

#import "Assertion/GREYAssertions.h"

#import "Additions/NSObject+GREYAdditions.h"
#import "Assertion/GREYAssertion.h"
#import "Assertion/GREYAssertionBlock.h"
#import "Assertion/GREYAssertionDefines.h"
#import "Core/GREYInteraction.h"
#import "Matcher/GREYMatcher.h"
#import "Matcher/GREYMatchers.h"
#import "Matcher/GREYStringDescription.h"
#import "Common/GREYError.h"
#import "Common/GREYLogger.h"

@implementation GREYAssertions

#pragma mark - Package Internal

+ (void)grey_raiseExceptionNamed:(NSString *)name
                exceptionDetails:(NSString *)details
                       withError:(GREYError *)error {
  id<GREYFailureHandler> failureHandler =
  [[[NSThread currentThread] threadDictionary] valueForKey:kGREYFailureHandlerKey];
  NSString *reason = [GREYError grey_nestedDescriptionForError:error];
  [failureHandler handleException:[GREYFrameworkException exceptionWithName:name
                                                                     reason:reason]
                          details:details];
}

+ (id<GREYAssertion>)grey_createAssertionWithMatcher:(id<GREYMatcher>)matcher {
  NSParameterAssert(matcher);

  NSString *assertionName = [NSString stringWithFormat:@"assertWithMatcher: %@", matcher];
  return [GREYAssertionBlock assertionWithName:assertionName
                       assertionBlockWithError:^BOOL (id element, NSError *__strong *errorOrNil) {
    GREYStringDescription *mismatch = [[GREYStringDescription alloc] init];
    if (![matcher matches:element describingMismatchTo:mismatch]) {
      NSMutableString *reason = [[NSMutableString alloc] init];
      NSMutableDictionary *glossary = [[NSMutableDictionary alloc] init];
      if (!element) {
        [reason appendFormat:@"Assertion with matcher [M] failed: no UI element was matched."];
        glossary[@"M"] = [matcher description];

        GREYPopulateErrorNotedOrLog(errorOrNil,
                                    kGREYInteractionErrorDomain,
                                    kGREYInteractionElementNotFoundErrorCode,
                                    reason,
                                    glossary);
      } else {
        [reason appendFormat:@"Assertion with matcher [M] failed: UI element [E] failed to match "
                             @"due to the mismatch [S]."];
        glossary[@"M"] = [matcher description];
        glossary[@"E"] = [element grey_description];
        glossary[@"S"] = [mismatch description];

        GREYPopulateErrorNotedOrLog(errorOrNil,
                                    kGREYInteractionErrorDomain,
                                    kGREYInteractionAssertionFailedErrorCode,
                                    reason,
                                    glossary);
      }

      // Log error if we are not populating errorOrNil.
      if (!errorOrNil) {
        GREYLogError(*errorOrNil);
      }
      return NO;
    }
    return YES;
  }];
}

@end
