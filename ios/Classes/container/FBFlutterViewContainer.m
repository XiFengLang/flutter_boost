/*
 * The MIT License (MIT)
 *
 * Copyright (c) 2019 Alibaba Group
 *
 * Permission is hereby granted, free of charge, to any person obtaining a copy
 * of this software and associated documentation files (the "Software"), to deal
 * in the Software without restriction, including without limitation the rights
 * to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
 * copies of the Software, and to permit persons to whom the Software is
 * furnished to do so, subject to the following conditions:
 *
 * The above copyright notice and this permission notice shall be included in
 * all copies or substantial portions of the Software.
 *
 * THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
 * IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
 * FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
 * AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
 * LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
 * OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
 * THE SOFTWARE.
 */

#import <Foundation/Foundation.h>
#import "FBFlutterViewContainer.h"
#import "FlutterBoost.h"
#import "FBLifecycle.h"
#import <objc/message.h>
#import <objc/runtime.h>

#define ENGINE [[FlutterBoost instance] engine]
#define FB_PLUGIN  [FlutterBoostPlugin getPlugin: [[FlutterBoost instance] engine]]

//#define FLUTTER_VIEW ENGINE.flutterViewController.view
//#define FLUTTER_VC ENGINE.flutterViewController

@interface FlutterViewController (bridgeToviewDidDisappear)
- (void)flushOngoingTouches;
- (void)bridge_viewDidDisappear:(BOOL)animated;
- (void)bridge_viewWillAppear:(BOOL)animated;
- (void)surfaceUpdated:(BOOL)appeared;
@end

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wincomplete-implementation"
@implementation FlutterViewController (bridgeToviewDidDisappear)
- (void)bridge_viewDidDisappear:(BOOL)animated{
    [self flushOngoingTouches];
    [super viewDidDisappear:animated];
}
- (void)bridge_viewWillAppear:(BOOL)animated {
//    [FLUTTER_APP inactive];
    [FBLifecycle inactive ];
    [super viewWillAppear:animated];
}
@end
#pragma pop

@interface FBFlutterViewContainer ()
@property (nonatomic,strong,readwrite) NSDictionary *params;
@property (nonatomic,copy) NSString *uniqueId;
@property (nonatomic, copy) NSString *flbNibName;
@property (nonatomic, strong) NSBundle *flbNibBundle;
@end

@implementation FBFlutterViewContainer

- (instancetype)init
{
    if(self = [super initWithEngine:ENGINE
                            nibName:_flbNibName
                            bundle:_flbNibBundle]){
        //NOTES:在present页面时，默认是全屏，如此可以触发底层VC的页面事件。否则不会触发而导致异常
        self.modalPresentationStyle = UIModalPresentationFullScreen;

        [self _setup];
    }
    return self;
}

- (instancetype)initWithProject:(FlutterDartProject*)projectOrNil
                        nibName:(NSString*)nibNameOrNil
                         bundle:(NSBundle*)nibBundleOrNil  {
    if (self = [super initWithProject:projectOrNil nibName:nibNameOrNil bundle:nibBundleOrNil]) {
        [self _setup];
    }
    return self;
}

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wobjc-designated-initializers"
- (instancetype)initWithCoder:(NSCoder *)aDecoder{
    if (self = [super initWithCoder: aDecoder]) {
        NSAssert(NO, @"unsupported init method!");
        [self _setup];
    }
    return self;
}
#pragma pop

- (instancetype)initWithNibName:(NSString *)nibNameOrNil bundle:(NSBundle *)nibBundleOrNil {
    _flbNibName = nibNameOrNil;
    _flbNibBundle = nibBundleOrNil;
    return [self init];
}

- (void)setName:(NSString *)name uniqueId:(NSString *)uniqueId params:(NSDictionary *)params
{
    if(!_name && name){
        _name = name;
        _params = params;
        if (uniqueId != nil) {
            _uniqueId = uniqueId;
        }
    }
}

static NSUInteger kInstanceCounter = 0;

+ (NSUInteger)instanceCounter
{
    return kInstanceCounter;
}

+ (void)instanceCounterIncrease
{
    kInstanceCounter++;
    if(kInstanceCounter == 1){
//        [FLUTTER_APP resume];
        [FBLifecycle resume ];
    }
}

+ (void)instanceCounterDecrease
{
    kInstanceCounter--;
    if([self.class instanceCounter] == 0){
//        [FLUTTER_APP pause];
        [FBLifecycle pause ];
    }
}

- (NSString *)uniqueIDString
{
    return self.uniqueId;
}

- (void)_setup
{
    self.uniqueId = [[NSUUID UUID] UUIDString];
    [self.class instanceCounterIncrease];
}

- (void)willMoveToParentViewController:(UIViewController *)parent {
    if (parent && _name) {
        //当VC将要被移动到Parent中的时候，才出发flutter层面的page init
        FBCommonParams* params = [[FBCommonParams alloc] init];
        params.pageName = _name;
        params.arguments = _params;
        params.uniqueId = self.uniqueId;

        [FB_PLUGIN.flutterApi pushRoute: params completion:^(NSError * e) {
                }];
    }
    [super willMoveToParentViewController:parent];
}

- (void)didMoveToParentViewController:(UIViewController *)parent {
    if (!parent) {
        //当VC被移出parent时，就通知flutter层销毁page
        [self notifyWillDealloc];
        
        if (self.engine.viewController == self) {
            [self detatchFlutterEngine];
        }
    }
    [super didMoveToParentViewController:parent];
}

- (void)dismissViewControllerAnimated:(BOOL)flag completion:(void (^)(void))completion {

    [super dismissViewControllerAnimated:flag completion:^(){
        if (completion) {
            completion();
        }
        //当VC被dismiss时，就通知flutter层销毁page
        [self notifyWillDealloc];
    }];
}

- (void)dealloc
{
    [NSNotificationCenter.defaultCenter removeObserver:self];
}

- (void)notifyWillDealloc
{
    FBCommonParams* params =[[FBCommonParams alloc] init ];
    params.pageName = _name;
    params.arguments = _params;
    params.uniqueId = self.uniqueId;
    [FB_PLUGIN.flutterApi removeRoute: params  completion:^(NSError * e) {

            }];
    [FB_PLUGIN removeContainer:self];
        
    [self.class instanceCounterDecrease];
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = UIColor.whiteColor;
}

#pragma mark - ScreenShots
- (BOOL)isFlutterViewAttatched
{
    return ENGINE.viewController.view.superview == self.view;
}

- (void)attatchFlutterEngine
{
    if(ENGINE.viewController != self){
        ENGINE.viewController=self;
    }
}

- (void)detatchFlutterEngine
{
    if(ENGINE.viewController != nil) {
        ENGINE.viewController = nil;
    }
}

- (void)surfaceUpdated:(BOOL)appeared {
    if (self.engine && self.engine.viewController == self) {
        [super surfaceUpdated:appeared];
    }
}

#pragma mark - Life circle methods

- (void)viewDidLayoutSubviews
{
    [super viewDidLayoutSubviews];
}

- (void)viewWillAppear:(BOOL)animated
{
    //For new page we should attach flutter view in view will appear
    //for better performance.
    FBCommonParams* params = [[FBCommonParams alloc] init];
    params.pageName = _name;
    params.arguments = _params;
    params.uniqueId = self.uniqueId;
    [FB_PLUGIN.flutterApi pushRoute: params completion:^(NSError * e) {
           
            }];
    [FB_PLUGIN addContainer:self];

    [self attatchFlutterEngine];

    [super bridge_viewWillAppear:animated];
    [self.view setNeedsLayout];//TODO:通过param来设定
   
}

- (void)viewDidAppear:(BOOL)animated
{
    //Ensure flutter view is attached.
    [self attatchFlutterEngine];

    //根据淘宝特价版日志证明，即使在UIViewController的viewDidAppear下，application也可能在inactive模式，此时如果提交渲染会导致GPU后台渲染而crash
    //参考：https://github.com/flutter/flutter/issues/57973
    //https://github.com/flutter/engine/pull/18742
    if([UIApplication sharedApplication].applicationState == UIApplicationStateActive){
        //NOTES：务必在show之后再update，否则有闪烁; 或导致侧滑返回时上一个页面会和top页面内容一样
        [self surfaceUpdated:YES];

    }
    [super viewDidAppear:animated];

    // Enable or disable pop gesture
    // note: if disablePopGesture is nil, do nothing
    if (self.disablePopGesture) {
        self.navigationController.interactivePopGestureRecognizer.enabled = ![self.disablePopGesture boolValue];
    }
}

- (void)viewWillDisappear:(BOOL)animated
{
    [[[UIApplication sharedApplication] keyWindow] endEditing:YES];
    [super viewWillDisappear:animated];
}

- (void)viewDidDisappear:(BOOL)animated
{
    [super bridge_viewDidDisappear:animated];
}

- (void)installSplashScreenViewIfNecessary {
    //Do nothing.
}

- (BOOL)loadDefaultSplashScreenView
{
    return YES;
}

@end

