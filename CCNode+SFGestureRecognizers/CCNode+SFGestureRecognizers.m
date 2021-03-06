//
//  CCNode+GestureRecognizers.m
//  Kubik
//
//  Created by Krzysztof Zablocki on 2/12/12.
//  Copyright (c) 2012 Krzysztof Zablocki. All rights reserved.
//
#import "CCNode+SFGestureRecognizers.h"
#import <objc/runtime.h>

//! __ for internal use | check out SFExecuteOnDealloc for category on NSObject that allows the same ;)
typedef void(^__SFExecuteOnDeallocBlock)(void);

@interface __SFExecuteOnDealloc : NSObject
+ (id)executeBlock:(__SFExecuteOnDeallocBlock)aBlock onObjectDealloc:(id)aObject;
- (id)initWithBlock:(__SFExecuteOnDeallocBlock)aBlock;
@end

@implementation __SFExecuteOnDealloc {
@public
  __SFExecuteOnDeallocBlock block;
}

+ (id)executeBlock:(__SFExecuteOnDeallocBlock)aBlock onObjectDealloc:(id)aObject
{
  __SFExecuteOnDealloc *executor = [[self alloc] initWithBlock:aBlock];
  objc_setAssociatedObject(aObject, executor, executor, OBJC_ASSOCIATION_RETAIN);
  return [executor autorelease];
}

- (id)initWithBlock:(__SFExecuteOnDeallocBlock)aBlock
{
  self = [super init];
  if (self) {
    block = [aBlock copy];
  }
  return self;
}

- (void)dealloc
{
  if (block) {
    block();
  }
  [block release];
  [super dealloc];
}
@end


static NSString *const CCNodeSFGestureRecognizersArrayKey = @"CCNodeSFGestureRecognizersArrayKey";
static NSString *const CCNodeSFGestureRecognizersTouchRect = @"CCNodeSFGestureRecognizersTouchRect";
static NSString *const CCNodeSFGestureRecognizersTouchEnabled = @"CCNodeSFGestureRecognizersTouchEnabled";
static NSString *const UIGestureRecognizerSFGestureRecognizersPassingDelegateKey = @"UIGestureRecognizerSFGestureRecognizersPassingDelegateKey";

@interface __SFGestureRecognizersPassingDelegate : NSObject<UIGestureRecognizerDelegate> {
@public
  __weak id <UIGestureRecognizerDelegate> originalDelegate;
  __weak CCNode *node;
}
@end

@implementation __SFGestureRecognizersPassingDelegate

#pragma mark - UIGestureRecognizer Delegate handling
- (BOOL)gestureRecognizer:(UIGestureRecognizer *)gestureRecognizer shouldReceiveTouch:(UITouch *)touch
{
  CGPoint pt = [[CCDirector sharedDirector] convertToGL:[touch locationInView: [touch view]]];
#if SF_GESTURE_RECOGNIZERS_USE_SHORTHAND
  BOOL rslt = [node isPointInArea:pt];
#else
  BOOL rslt = [node sf_isPointInArea:pt];
#endif
  
  //! we need to make sure that no other node ABOVE this one was touched, we want ONLY the top node with gesture recognizer to get callback
  if( rslt )
  {
    CCNode* curNode = node;
    CCNode* parent = node.parent;
    while( curNode != nil && rslt)
    {
      CCNode* child;
      BOOL nodeFound = NO;
      CCARRAY_FOREACH(parent.children, child)
      {
        if( !nodeFound )
        {
          if( !nodeFound && curNode == child )
            nodeFound = YES;
          continue;
        }
#if SF_GESTURE_RECOGNIZERS_USE_SHORTHAND
        if( [child isNodeInTreeTouched:pt])
#else
        if( [child sf_isNodeInTreeTouched:pt])          
#endif
        {
          rslt = NO;
          break;
        }
      }
      
      curNode = parent;
      parent = curNode.parent;
    }
  }
  
  if( rslt && [originalDelegate respondsToSelector:@selector(gestureRecognizer:shouldReceiveTouch:)])
    rslt = [originalDelegate gestureRecognizer:gestureRecognizer shouldReceiveTouch:touch];
  
  return rslt;
}

- (BOOL)gestureRecognizerShouldBegin:(UIGestureRecognizer *)gestureRecognizer
{
  if ([originalDelegate respondsToSelector:@selector(gestureRecognizerShouldBegin:)]) {
    return [originalDelegate gestureRecognizerShouldBegin:gestureRecognizer];
  }
  return YES;
}

- (BOOL)gestureRecognizer:(UIGestureRecognizer *)gestureRecognizer shouldRecognizeSimultaneouslyWithGestureRecognizer:(UIGestureRecognizer *)otherGestureRecognizer
{
  if ([originalDelegate respondsToSelector:@selector(gestureRecognizer:shouldRecognizeSimultaneouslyWithGestureRecognizer:)]) {
    return [originalDelegate gestureRecognizer:gestureRecognizer shouldRecognizeSimultaneouslyWithGestureRecognizer:otherGestureRecognizer];
  }
  
  return NO;
}

#pragma mark - Handling delegate change
- (void)setDelegate:(id<UIGestureRecognizerDelegate>)aDelegate
{
  __SFGestureRecognizersPassingDelegate *passingDelegate = objc_getAssociatedObject(self, UIGestureRecognizerSFGestureRecognizersPassingDelegateKey);
  if (passingDelegate) {
    passingDelegate->originalDelegate = aDelegate;
  } else {
    [self performSelector:@selector(originalSetDelegate:) withObject:aDelegate];
  }
}

- (id<UIGestureRecognizerDelegate>)delegate
{
  __SFGestureRecognizersPassingDelegate *passingDelegate = objc_getAssociatedObject(self, UIGestureRecognizerSFGestureRecognizersPassingDelegateKey);
  if (passingDelegate) {
    return passingDelegate->originalDelegate;
  }
  
  //! no delegate yet so use original method
  return [self performSelector: @selector(originalDelegate)];
}
@end


@implementation UIGestureRecognizer (SFGestureRecognizers)
#ifdef SF_GESTURE_RECOGNIZERS_USE_SHORTHAND
@dynamic node;
#else
@dynamic sf_node;
#endif

#ifdef SF_GESTURE_RECOGNIZERS_USE_SHORTHAND
- (CCNode*)node
#else
- (CCNode*)sf_node
#endif
{
  __SFGestureRecognizersPassingDelegate *passingDelegate = objc_getAssociatedObject(self, UIGestureRecognizerSFGestureRecognizersPassingDelegateKey);
  if (passingDelegate) {
    return passingDelegate->node;
  }
  return nil;
}
@end


@implementation CCNode (SFGestureRecognizers)

#ifdef SF_GESTURE_RECOGNIZERS_USE_SHORTHAND
@dynamic isTouchEnabled;
@dynamic touchRect;
#else
@dynamic sf_isTouchEnabled;
@dynamic sf_touchRect;
#endif

#if SF_GESTURE_RECOGNIZERS_USE_SHORTHAND
- (void)addGestureRecognizer:(UIGestureRecognizer*)aGestureRecognizer
#else
- (void)sf_addGestureRecognizer:(UIGestureRecognizer*)aGestureRecognizer
#endif
{
  //! prepare passing gesture recognizer
  __SFGestureRecognizersPassingDelegate *passingDelegate = [[__SFGestureRecognizersPassingDelegate alloc] init];
  passingDelegate->originalDelegate = aGestureRecognizer.delegate;
  passingDelegate->node = self;
  aGestureRecognizer.delegate = passingDelegate;
  //! retain passing delegate as it only lives as long as this gesture recognizer lives
  objc_setAssociatedObject(aGestureRecognizer, UIGestureRecognizerSFGestureRecognizersPassingDelegateKey, passingDelegate, OBJC_ASSOCIATION_RETAIN);
  [passingDelegate release];
  
  //! we need to swap gesture recognizer methods so that we can handle delegates nicely, but we also need to be able to call originalMethods if gesture isnt assigned to CCNode, do it only once in whole app
  static dispatch_once_t onceToken;
  dispatch_once(&onceToken, ^{
    Method originalGetter = class_getInstanceMethod([UIGestureRecognizer class], @selector(delegate));
    Method originalSetter = class_getInstanceMethod([UIGestureRecognizer class], @selector(setDelegate:));
    Method swappedGetter = class_getInstanceMethod([__SFGestureRecognizersPassingDelegate class], @selector(delegate));
    Method swappedSetter = class_getInstanceMethod([__SFGestureRecognizersPassingDelegate class], @selector(setDelegate:));
    
    class_addMethod([UIGestureRecognizer class], @selector(originalDelegate), method_getImplementation(originalGetter), method_getTypeEncoding(originalGetter));
    class_replaceMethod([UIGestureRecognizer class], @selector(delegate), method_getImplementation(swappedGetter), method_getTypeEncoding(swappedGetter));
    class_addMethod([UIGestureRecognizer class], @selector(originalSetDelegate:), method_getImplementation(originalSetter), method_getTypeEncoding(originalSetter));
    class_replaceMethod([UIGestureRecognizer class], @selector(setDelegate:), method_getImplementation(swappedSetter), method_getTypeEncoding(swappedSetter));
  });
  

if ([[CCDirector sharedDirector] respondsToSelector:@selector(view)]) {
  [[[CCDirector sharedDirector] performSelector:@selector(view)] addGestureRecognizer:aGestureRecognizer];
} else {
  [[[CCDirector sharedDirector] performSelector:@selector(openGLView)] addGestureRecognizer:aGestureRecognizer];
}
  //! add to array
  NSMutableArray *gestureRecognizers = objc_getAssociatedObject(self, CCNodeSFGestureRecognizersArrayKey);
  if (!gestureRecognizers) {
    gestureRecognizers = [NSMutableArray array];
    objc_setAssociatedObject(self, CCNodeSFGestureRecognizersArrayKey, gestureRecognizers, OBJC_ASSOCIATION_RETAIN);
    
  }
  [gestureRecognizers addObject:aGestureRecognizer];

  //! remove this gesture recognizer from view when array is deallocatd
  __block CCNode *weakSelf = self; 
  [__SFExecuteOnDealloc executeBlock:^{
#if SF_GESTURE_RECOGNIZERS_USE_SHORTHAND
    [weakSelf removeGestureRecognizer:aGestureRecognizer];
#else
    [weakSelf sf_removeGestureRecognizer:aGestureRecognizer];
#endif
  } onObjectDealloc:gestureRecognizers];

#if SF_GESTURE_RECOGNIZERS_AUTO_ENABLE_TOUCH_ON_NEW_GESTURE_RECOGNIZER
  //! enable touch for this element or it won't work
#if SF_GESTURE_RECOGNIZERS_USE_SHORTHAND
  [self setIsTouchEnabled:YES];
#else
  [self sf_setIsTouchEnabled:YES];
#endif
#endif
}

#if SF_GESTURE_RECOGNIZERS_USE_SHORTHAND
- (void)removeGestureRecognizer:(UIGestureRecognizer*)aGestureRecognizer
#else
- (void)sf_removeGestureRecognizer:(UIGestureRecognizer*)aGestureRecognizer
#endif
{
  NSMutableArray *gestureRecognizers = objc_getAssociatedObject(self, CCNodeSFGestureRecognizersArrayKey);
  objc_setAssociatedObject(self, UIGestureRecognizerSFGestureRecognizersPassingDelegateKey, nil, OBJC_ASSOCIATION_RETAIN);
  if ([[CCDirector sharedDirector] respondsToSelector:@selector(view)]) {
    [[[CCDirector sharedDirector] performSelector:@selector(view)] removeGestureRecognizer:aGestureRecognizer];
  } else {
    [[[CCDirector sharedDirector] performSelector:@selector(openGLView)] removeGestureRecognizer:aGestureRecognizer];
  }
  [gestureRecognizers removeObject:aGestureRecognizer];
}

#if SF_GESTURE_RECOGNIZERS_USE_SHORTHAND
- (NSArray*)gestureRecognizers
#else
- (NSArray*)sf_gestureRecognizers
#endif
{
  //! add to array
  NSMutableArray *gestureRecognizers = objc_getAssociatedObject(self, CCNodeSFGestureRecognizersArrayKey);
  if (!gestureRecognizers) {
    gestureRecognizers = [NSMutableArray array];
    objc_setAssociatedObject(self, CCNodeSFGestureRecognizersArrayKey, gestureRecognizers, OBJC_ASSOCIATION_RETAIN);
  }
  return [NSArray arrayWithArray: gestureRecognizers];
}

#pragma mark - Point inside

#if SF_GESTURE_RECOGNIZERS_USE_SHORTHAND
- (BOOL)isPointInArea:(CGPoint)pt
#else
- (BOOL)sf_isPointInArea:(CGPoint)pt
#endif
{
  if (!visible_ || !isRunning_)
    return NO;
#if SF_GESTURE_RECOGNIZERS_USE_SHORTHAND
  if (!self.isTouchEnabled) {
    return NO;
  }
#else 
  if (!self.sf_isTouchEnabled) {
    return NO;
  }
#endif

  //! convert to local space 
  pt = [self convertToNodeSpace:pt];
  
  //! get touchable rect in local space
#if SF_GESTURE_RECOGNIZERS_USE_SHORTHAND
  CGRect rect = self.touchRect;
#else
  CGRect rect = self.sf_touchRect;
#endif
  
  if( CGRectContainsPoint(rect,pt) )
    return YES;
  return NO;
}

#if SF_GESTURE_RECOGNIZERS_USE_SHORTHAND
- (BOOL)isNodeInTreeTouched:(CGPoint)pt
#else
- (BOOL)sf_isNodeInTreeTouched:(CGPoint)pt
#endif
{
#if SF_GESTURE_RECOGNIZERS_USE_SHORTHAND
  if( [self isPointInArea:pt] ) {
     return YES;
  }
#else
  if( [self sf_isPointInArea:pt] ) {
    return YES;
  }
#endif
  
  BOOL rslt = NO;
  CCNode* child;
  CCARRAY_FOREACH(children_, child )
  {
#if SF_GESTURE_RECOGNIZERS_USE_SHORTHAND
    if( [child isNodeInTreeTouched:pt] )
#else
    if( [child sf_isNodeInTreeTouched:pt] )
#endif
    {
      rslt = YES;
      break;
    }
  }
  return rslt;
}

#pragma mark - Touch Enabled

- (BOOL)sf_isTouchEnabled
{
  if ([self respondsToSelector:@selector(isTouchEnabled)]) {
    return (BOOL)[self performSelector:@selector(isTouchEnabled)];
  }
  //! our own implementation
  NSNumber *touchEnabled = objc_getAssociatedObject(self, CCNodeSFGestureRecognizersTouchEnabled);
  if (!touchEnabled) {
    [self sf_setIsTouchEnabled:NO];
    return NO;
  }
  return [touchEnabled boolValue];
}

- (void)sf_setIsTouchEnabled:(BOOL)aTouchEnabled
{
  if ([self respondsToSelector:@selector(setIsTouchEnabled:)]) {
    [self performSelector:@selector(setIsTouchEnabled:) withObject:(id)aTouchEnabled];
    return;
  }
  
  objc_setAssociatedObject(self, CCNodeSFGestureRecognizersTouchEnabled, [NSNumber numberWithBool:aTouchEnabled], OBJC_ASSOCIATION_RETAIN);
}

#pragma mark - Touch Rectangle

#if SF_GESTURE_RECOGNIZERS_USE_SHORTHAND
- (void)setTouchRect:(CGRect)aRect
#else
- (void)sf_setTouchRect:(CGRect)aRect
#endif
{
  objc_setAssociatedObject(self, CCNodeSFGestureRecognizersTouchRect, [NSValue valueWithCGRect:aRect], OBJC_ASSOCIATION_RETAIN);
}

#if SF_GESTURE_RECOGNIZERS_USE_SHORTHAND
- (CGRect)touchRect
#else
- (CGRect)sf_touchRect
#endif
{
  NSValue *rectValue = objc_getAssociatedObject(self, CCNodeSFGestureRecognizersTouchRect);
  if (rectValue) {
    return [rectValue CGRectValue];
  } else {
    CGRect defaultRect = CGRectMake(0, 0, self.contentSize.width, self.contentSize.height);
#if SF_GESTURE_RECOGNIZERS_USE_SHORTHAND
    self.touchRect = defaultRect;
#else 
    self.sf_touchRect = defaultRect;
#endif
    return defaultRect;
  }
}

//! CCLayer has implementation of isTouchEnabled / setIsTouchEnabled, so we only use our internal methods if we are NOT CCLayer subclass 
#if SF_GESTURE_RECOGNIZERS_USE_SHORTHAND
- (void)forwardInvocation:(NSInvocation *)anInvocation
{
  if (anInvocation.selector == @selector(isTouchEnabled)) {
    anInvocation.selector = @selector(sf_isTouchEnabled);
  } else if (anInvocation.selector == @selector(setIsTouchEnabled:)) {
    anInvocation.selector = @selector(sf_setIsTouchEnabled:);
  }
  [anInvocation invokeWithTarget:self];
}

- (NSMethodSignature *)methodSignatureForSelector:(SEL)aSelector
{
  if (![self respondsToSelector:aSelector]) {
    if (aSelector == @selector(isTouchEnabled)) {
      return [self methodSignatureForSelector:@selector(sf_isTouchEnabled)]; 
    } else if (aSelector == @selector(setIsTouchEnabled:)) {
      return [self methodSignatureForSelector:@selector(sf_setIsTouchEnabled:)]; 
    }
  }
  
  return [super methodSignatureForSelector:aSelector];
}
#endif
@end
