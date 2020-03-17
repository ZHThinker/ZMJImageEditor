//
//  WBGDrawTool.m
//  CLImageEditorDemo
//
//  Created by Jason on 2017/2/28.
//  Copyright © 2017年 CALACULU. All rights reserved.
//

#import "WBGDrawTool.h"
#import "WBGImageEditorGestureManager.h"
#import "WBGTextToolView.h"
#import "WBGColorPanel.h"
#import "Masonry.h"
#import "WBGChatMacros.h"
#import <XXNibBridge/XXNibBridge.h>

@interface WBGDrawTool ()
@property (nonatomic, weak) WBGDrawView *canvas;
@property (nonatomic, assign) CGSize originalImageSize;
@property (nonatomic, weak) WBGColorPanel *colorPanel;
@property (nonatomic, strong) UIPanGestureRecognizer *panGesture;
@property (nonatomic, strong) UITapGestureRecognizer *tapGesture;
@property (nonatomic, strong) dispatch_semaphore_t lock;

@property (nonatomic, strong) WBGPath *selectedPath;
@property (nonatomic, assign) BOOL movingPath;
@end

@implementation WBGDrawTool

- (instancetype)initWithImageEditor:(WBGImageEditorViewController *)editor
{
    self = [super init];
    
    if(self)
    {
        self.lock = dispatch_semaphore_create(1);
        
        self.editor = editor;
        self.allLineMutableArray = [NSMutableArray new];
        self.canvas = self.editor.drawingView;
        
        WBGColorPanel *colorPanel = [WBGColorPanel xx_instantiateFromNib];
        colorPanel.backButton.alpha = 0.5f;
        [editor.view addSubview:colorPanel];
        self.colorPanel = colorPanel;
        [colorPanel mas_makeConstraints:^(MASConstraintMaker *make) {
            make.left.right.mas_equalTo(0);
            make.height.mas_equalTo([WBGColorPanel fixedHeight]);
            make.bottom.mas_equalTo(editor.bottomBar.mas_top).mas_offset(35);
        }];
        
        [self setupActions];
    }
    
    return self;
}

- (void)setupActions
{
    __weak WBGDrawTool *weakSelf = self;
    [self.colorPanel setUndoButtonTappedBlock:
    ^{
        __strong WBGDrawTool *strongSelf = weakSelf;
        [strongSelf backToLastDraw];
        
        if (strongSelf.allLineMutableArray.count > 0)
        {
            strongSelf.colorPanel.backButton.alpha = 1.0f;
        }
        else
        {
            strongSelf.colorPanel.backButton.alpha = 0.5f;
        }
    }];
    
    self.drawToolStatus = ^(BOOL canPrev)
    {
        __strong WBGDrawTool *strongSelf = weakSelf;
        if (canPrev)
        {
            strongSelf.colorPanel.backButton.alpha = 1.0f;
        }
        else
        {
            strongSelf.colorPanel.backButton.alpha = 0.5f;
        }
    };
    
    self.drawingCallback = ^(BOOL isDrawing)
    {
         __strong WBGDrawTool *strongSelf = weakSelf;
        [strongSelf.editor hiddenTopAndBottomBar:isDrawing animation:YES];
    };
    
    self.drawingDidTap =
    ^{
         __strong WBGDrawTool *strongSelf = weakSelf;
        [strongSelf.editor hiddenTopAndBottomBar:!strongSelf.editor.barsHiddenStatus animation:YES];
    };
    
    [self.canvas setDrawViewBlock:^(CGContextRef ctx)
    {
        __strong WBGDrawTool *strongSelf = weakSelf;
        Lock_Guard_Lock
        (
            strongSelf->_lock,
            NSArray<WBGPath *> *pathArray = [strongSelf.allLineMutableArray copy];
         );
        
        for (WBGPath *path in pathArray)
        {
            [path drawPath];
        }
    }];
}

#pragma mark - implementation 重写父方法
- (void)setup
{
    //初始化一些东西
    self.originalImageSize = self.editor.imageView.image.size;
    self.colorPanel.hidden = NO;
    
    //滑动手势
    if (!self.panGesture)
    {
        self.panGesture = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(drawingViewDidPan:)];
        self.panGesture.delegate = [WBGImageEditorGestureManager instance];
        self.panGesture.maximumNumberOfTouches = 1;
    }
    
    //点击手势
    if (!self.tapGesture)
    {
        self.tapGesture = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(drawingViewDidTap:)];
        self.tapGesture.delegate = [WBGImageEditorGestureManager instance];
        self.tapGesture.numberOfTouchesRequired = 1;
        self.tapGesture.numberOfTapsRequired = 1;
        
    }
    
    [_canvas addGestureRecognizer:self.panGesture];
    [_canvas addGestureRecognizer:self.tapGesture];
    _canvas.userInteractionEnabled = YES;
    _canvas.layer.shouldRasterize = YES;
    _canvas.layer.minificationFilter = kCAFilterTrilinear;
    
    self.editor.imageView.userInteractionEnabled = YES;
    self.editor.scrollView.panGestureRecognizer.minimumNumberOfTouches = 2;
    self.editor.scrollView.panGestureRecognizer.delaysTouchesBegan = NO;
    self.editor.scrollView.pinchGestureRecognizer.delaysTouchesBegan = NO;
    
    self.panGesture.enabled = YES;
    self.tapGesture.enabled = YES;
    
    self.editor.drawingView.userInteractionEnabled = YES;
}

- (void)cleanup
{
    self.colorPanel.hidden = YES;
    self.editor.imageView.userInteractionEnabled = NO;
    self.editor.scrollView.panGestureRecognizer.minimumNumberOfTouches = 1;
    self.panGesture.enabled = NO;
    self.tapGesture.enabled = NO;
}

- (UIView *)drawView
{
    return self.canvas;
}

- (void)hideTools:(BOOL)hidden
{
    if (hidden)
    {
        self.editor.bottomBar.alpha = 0;
        self.colorPanel.alpha = 0;
    }
    else
    {
        self.editor.bottomBar.alpha = 1.0f;
        self.colorPanel.alpha = 1.0f;
    }
}

- (void)backToLastDraw
{
    Lock_Guard
    (
        [_allLineMutableArray removeLastObject];
    );
    
    [self drawLine];
    
    if (self.drawToolStatus)
    {
        Lock_Guard
        (
            BOOL canPrev = _allLineMutableArray.count > 0 ? YES : NO;
        );
        
        self.drawToolStatus(canPrev);
    }
}

#pragma mark - Gesture
//tap
- (void)drawingViewDidTap:(UITapGestureRecognizer *)sender
{
    if (self.drawingDidTap)
    {
        self.drawingDidTap();
    }
    
    CGPoint currentTapPosition = [sender locationInView:self.canvas];
    
    
    Lock_Guard
    (
     BOOL draw = NO;
     WBGPath *selectedPath = nil;
     
     for (NSUInteger i = self.allLineMutableArray.count; i > 0; i--) {
        WBGPath *path = self.allLineMutableArray[i-1];
        BOOL contain = [self containsPoint:currentTapPosition onPath:path.bezierPath inFillArea:NO];
        if (contain) {
            selectedPath = path;
            break;
        }
     }
     
     if (selectedPath == nil) {
        for (int i = 0; i < self.allLineMutableArray.count; i++) {
            WBGPath *path = self.allLineMutableArray[i];
            if (path.isSelected) {
                path.isSelected = NO;
                draw = YES;
            }
        }
    } else {
        self.selectedPath = selectedPath;
        
        for (int i = 0; i < self.allLineMutableArray.count; i++) {
            WBGPath *path = self.allLineMutableArray[i];
            
            if ([path isEqual:selectedPath]) {
                path.isSelected = !path.isSelected;
                draw = YES;
            } else {
                if (path.isSelected) {
                    path.isSelected = NO;
                    draw = YES;
                }
            }
        }
        [self.allLineMutableArray removeObject:selectedPath];
        [self.allLineMutableArray addObject:selectedPath];
    }
    );
    if (draw) {
        [self drawLine];
    }
}

//draw
- (void)drawingViewDidPan:(UIPanGestureRecognizer*)sender
{
    CGPoint currentDraggingPosition = [sender locationInView:self.canvas];
    
    if (sender.state == UIGestureRecognizerStateBegan) {

        if ([self shouldMovePathWithPoint:currentDraggingPosition]) {
            // 位移曲线
            self.movingPath = YES;
        } else {
            self.selectedPath.isSelected = NO;
            self.selectedPath = nil;
            self.movingPath = NO;
            [self panToDrawWithPoint:currentDraggingPosition];
        }
        
    }
    
    
    if(sender.state == UIGestureRecognizerStateChanged)
    { // 获得数组中的最后一个UIBezierPath对象(因为我们每次都把UIBezierPath存入到数组最后一个,因此获取时也取最后一个)
        
        if (self.movingPath) {
            CGPoint trans = [sender translationInView:self.canvas];
            [self.selectedPath.bezierPath applyTransform:CGAffineTransformMakeTranslation(trans.x, trans.y)];
            [self drawLine];
            [sender setTranslation:CGPointZero inView:self.canvas];
        } else {
            
            Lock_Guard
            (
             WBGPath *path = [_allLineMutableArray lastObject];
             );
            
            [path pathLineToPoint:currentDraggingPosition];//添加点
            [self drawLine];
        }
        
        if (self.drawingCallback)
        {
            self.drawingCallback(YES);
        }
        
    }
    
    if (sender.state == UIGestureRecognizerStateEnded)
    {
        
        if (self.drawToolStatus)
        {
            Lock_Guard
            (
                BOOL canPrev = _allLineMutableArray.count > 0 ? YES : NO;
            );
            
            self.drawToolStatus(canPrev);
        }
        
        if (self.drawingCallback)
        {
            self.drawingCallback(NO);
        }
    }
}

- (void)panToDrawWithPoint:(CGPoint)currentDraggingPosition {
    //取消所有加入文字激活状态
    for (UIView *subView in self.editor.drawingView.subviews)
    {
        if ([subView isKindOfClass:[WBGTextToolView class]])
        {
            [WBGTextToolView setInactiveTextView:(WBGTextToolView *)subView];
        }
    }
    
    // 初始化一个UIBezierPath对象, 把起始点存储到UIBezierPath对象中, 用来存储所有的轨迹点
    WBGPath *path = [WBGPath pathToPoint:currentDraggingPosition pathWidth:MAX(1, self.pathWidth)];
    path.pathColor = self.colorPanel.currentColor;
    
    Lock_Guard
    (
        [_allLineMutableArray addObject:path];
    );
}

- (BOOL)shouldMovePathWithPoint:(CGPoint)point {
    return self.selectedPath != nil && [self containsPoint:point onPath:self.selectedPath.bezierPath inFillArea:NO];
}

#pragma mark - Draw
- (void)drawLine
{
    [self.canvas setNeedDraw];
}


// 检测是否点击到 bezierPath
- (BOOL)containsPoint:(CGPoint)point onPath:(UIBezierPath *)path inFillArea:(BOOL)inFill
{
    
    UIGraphicsBeginImageContext(self.canvas.frame.size);
    CGContextRef context = UIGraphicsGetCurrentContext();
    CGPathRef cgPath = path.CGPath;
    BOOL    isHit = NO;
    
    CGPathDrawingMode mode = kCGPathStroke;
    // Determine the drawing mode to use. Default to
    // detecting hits on the stroked portion of the path.
    if (inFill)
    {
        // Look for hits in the fill area of the path instead.
        if (path.usesEvenOddFillRule)
            mode = kCGPathEOFill;
        else
            mode = kCGPathFill;
    }
    
    // Save the graphics state so that the path can be
    // removed later.
       CGContextSaveGState(context);
    CGContextAddPath(context, cgPath);
    
    // Do the hit detection.
    for (int i =1; i<=5; i++) {
        CGPoint t = CGPointMake(point.x, point.y+i);
        isHit = CGContextPathContainsPoint(context, t, mode);
        if (isHit) {
            break;
        }
        t = CGPointMake(point.x+i, point.y);
        isHit = CGContextPathContainsPoint(context, t, mode);
        if (isHit) {
            break;
        }
        t = CGPointMake(point.x-i, point.y);
        isHit = CGContextPathContainsPoint(context, t, mode);
        if (isHit) {
            break;
        }
        t = CGPointMake(point.x, point.y-i);
        isHit = CGContextPathContainsPoint(context, t, mode);
        if (isHit) {
            break;
        }
        
    }
    
       CGContextRestoreGState(context);
    CFRelease(context);
    return isHit;
}
@end
