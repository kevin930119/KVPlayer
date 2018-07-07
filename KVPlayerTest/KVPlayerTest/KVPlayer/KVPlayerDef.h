//
//  KVPlayerBase.h
//  KVPlayer
//
//  Created by kevin on 2018/4/24.
//  Copyright © 2018年 kv. All rights reserved.
//

#import <UIKit/UIKit.h>
#import "KVPlayerAudioManager.h"

//帧类型
typedef NS_ENUM(NSInteger, KVPlayerFrameType) {
    KVPlayerFrameTypeAudio, //音频帧
    KVPlayerFrameTypeVideo, //视频帧
    KVPlayerFrameTypeArtwork,   //封面
    KVPlayerFrameTypeSubtitle   //字幕
};

//视频帧格式
typedef NS_ENUM(NSInteger, KVPlayerVideoFrameFormat) {
    KVPlayerVideoFrameFormatRGB,
    KVPlayerVideoFrameFormatYUV
};

//帧基类
@interface KVPlayerBaseFrame : NSObject

@property (nonatomic, assign) KVPlayerFrameType type;
@property (nonatomic, assign) CGFloat position;
@property (nonatomic, assign) CGFloat duration;

@end

//音频帧
@interface KVPlayerAudioFrame : KVPlayerBaseFrame

@property (nonatomic, strong) NSData *samples;

@end

//视频帧
@interface KVPlayerVideoFrame : KVPlayerBaseFrame

@property (nonatomic, assign) KVPlayerVideoFrameFormat format;
@property (nonatomic, assign) NSUInteger width;
@property (nonatomic, assign) NSUInteger height;

@end

//RGB视频帧
@interface KVPlayerVideoFrameRGB : KVPlayerVideoFrame

@property (nonatomic, assign) NSUInteger linesize;
@property (nonatomic, strong) NSData *rgb;

- (UIImage*)asImage;

@end

//YUV视频帧
@interface KVPlayerVideoFrameYUV : KVPlayerVideoFrame

@property (nonatomic, strong) NSData *luma;
@property (nonatomic, strong) NSData *chromaB;
@property (nonatomic, strong) NSData *chromaR;

@end

//封面帧
@interface KVPlayerArtworkFrame : KVPlayerBaseFrame
@property (nonatomic, strong) NSData *picture;
- (UIImage*)asImage;
@end

//字幕帧
@interface KVPlayerSubtitleFrame : KVPlayerBaseFrame
@property (nonatomic, strong) NSString *text;
@end








