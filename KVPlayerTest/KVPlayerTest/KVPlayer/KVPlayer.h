//
//  KVPlayer.h
//  KVPlayer
//
//  Created by kevin on 2018/4/24.
//  Copyright © 2018年 kv. All rights reserved.
//

#import <UIKit/UIKit.h>

#ifdef DEBUG
#define KVLog(...) NSLog(__VA_ARGS__)
#else
#define KVLog(...)
#endif

typedef NS_ENUM(NSInteger, KVPlayerPlayState) {
    KVPlayerPlayStateIdle,
    KVPlayerPlayStateLoading,
    KVPlayerPlayStatePlaying,
    KVPlayerPlayStatePause,
    KVPlayerPlayStateStop,
    KVPlayerPlayStateFinish
};

typedef enum : NSUInteger {
    KVPlayerScreenFit,
    KVPlayerScreenFill,
    KVPlayerScreenOneToOne,
    KVPlayerScreenSmall
} KVPlayerScreenMode;

@class KVPlayer;
@protocol KVPlayerDelegate <NSObject>

@optional
- (void)player:(KVPlayer*)player playAtTime:(float)location;
- (void)player:(KVPlayer*)player playStateChange:(KVPlayerPlayState)state;
- (void)player:(KVPlayer*)player fpsChanged:(int)fps;
- (void)player:(KVPlayer*)player didFailWithMsg:(NSString*)msg;

@end

@interface KVPlayer : NSObject

@property (nonatomic, weak) id <KVPlayerDelegate> delegate;
/**
 视频画面填充模式
 */
@property (nonatomic, assign) KVPlayerScreenMode screenMode;
/**
 当前播放状态，可通过代理方法监听播放状态的改变
 */
@property (readonly, nonatomic, assign) KVPlayerPlayState state;
/**
 设置播放位置
 */
@property (nonatomic, assign) float position;
/**
 音轨数量，多音轨视频可以切换音轨
 */
@property (readonly, nonatomic, assign) NSInteger audioTrackCount;
/**
 获取/切换当前音轨
 */
@property (nonatomic, assign) NSInteger selectAudioTrackIndex;
/**
 播放速率，即时改变
 */
@property (nonatomic, assign) float playRate;
/**
 视频时长
 */
@property (readonly, nonatomic, assign) float duration;
/**
 视频宽高
 */
@property (readonly, nonatomic, assign) CGSize videoSize;
/**
 视频fps（即一秒有多少帧图片，由于某些视频文件格式问题，不是每一帧的时长都是一样的，所以KVPlayer内部进行了fps校对，当fps改变时会通过回调通知）
 */
@property (readonly, nonatomic, assign) int fps;
/**
 播放视图，视频画面将会被输出到该view上，请将该view添加到合适位置
 */
@property (readonly, nonatomic, strong) UIView * playView;
/**
 是否拥有字幕（非内嵌字幕，内嵌字幕：即合成到视频画面中的字幕，无法改变）
 该字幕为封装到视频文件中的字幕数据
 */
@property (nonatomic, assign) BOOL validSubTitle;
/**
 是否隐藏视频字幕
 */
@property (nonatomic, assign) BOOL subTitleHidden;
/**
 修改字幕字体颜色
 */
@property (nonatomic, strong) UIColor * subTitleTextColor;
/**
 修改字幕字体大小
 */
@property (nonatomic, assign) NSInteger subTitleFontSize;
/**
 重设文件路径

 @param path 视频路径，必须以file://为前缀
 @param position 播放位置，在哪个位置开始播放
 @return 是否打开文件成功（非视频文件返回NO）
 */
- (BOOL)resetFile:(NSString*)path position:(float)position;

/**
 播放
 */
- (void)play;

/**
 暂停
 */
- (void)pause;

/**
 停止
 */
- (void)stop;

/**
 重设位置

 @param position 位置
 @param wantToPlay 是否播放
 */
- (void)resetPosition:(float)position wantToPlay:(BOOL)wantToPlay;

/**
 截屏

 @return 截取到的视频图片，没有返回nil
 */
- (UIImage*)snapshot;

/**
 释放播放器
 */
- (void)releasePlayer;

@end
