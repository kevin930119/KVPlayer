//
//  KVPlayerGLView.h
//  KVPlayer
//
//  Created by kevin on 2018/6/5.
//  Copyright © 2018年 yiye. All rights reserved.
//

#import <UIKit/UIKit.h>
#import "KVPlayerDef.h"

@interface KVPlayerGLView : UIView

@property (nonatomic, assign) float frameWidth;
@property (nonatomic, assign) float frameHeight;

- (instancetype)initWithFrame:(CGRect)frame size:(CGSize)size;

- (void)resetFrameSize:(CGSize)size;

- (void)render:(KVPlayerVideoFrame*)frame;

@end

@interface KVPlayerGLRenderer : NSObject

- (BOOL)isValid;
- (NSString*)fragmentShader;
- (void)resolveUniforms:(GLuint)program;
- (void)setFrame:(KVPlayerVideoFrame*)frame;
- (BOOL)prepareRender;

@end

@interface KVPlayerGLRenderer_YUV : KVPlayerGLRenderer

@end
