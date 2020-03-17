//
//  WBGDrawTool.h
//  CLImageEditorDemo
//
//  Created by Jason on 2017/2/28.
//  Copyright © 2017年 CALACULU. All rights reserved.
//

#import <UIKit/UIKit.h>

@interface WBGPath : NSObject
@property (nonatomic, strong) UIBezierPath *bezierPath;
@property (nonatomic, strong) UIColor *pathColor; // 画笔颜色
@property (nonatomic, assign) CGFloat *lineWidth; // 画笔线宽
@property (nonatomic, assign) BOOL isDraw; // 是否渲染
@property (nonatomic, assign) BOOL isSelected; // 是否选中

+ (instancetype)pathToPoint:(CGPoint)beginPoint pathWidth:(CGFloat)pathWidth;

- (void)pathLineToPoint:(CGPoint)movePoint; // 画
- (void)drawPath; // 绘制
@end
