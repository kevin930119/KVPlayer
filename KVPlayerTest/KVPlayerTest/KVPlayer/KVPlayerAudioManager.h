//
//  KVPlayerAudioManager.h
//  KVPlayer
//
//  Created by kevin on 2018/4/25.
//  Copyright © 2018年 kv. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <AudioToolbox/AudioToolbox.h>
#import <UIKit/UIKit.h>
//耳机拔出通知
#define kNotifyKVPlayerRouteChange @"kNotifyKVPlayerRouteChange"

typedef void (^KVPlayerAudioManagerOutputBlock)(float *data, UInt32 numFrames, UInt32 numChannels);

@interface KVPlayerAudioManager : NSObject

@property (nonatomic, assign) UInt32 numOutputChannels;
@property (nonatomic, assign) Float64 samplingRate;
@property (readonly, assign) UInt32 numBytesPerSample;
@property (readonly, assign) Float32 outputVolume;
@property (readonly, assign) BOOL playing;
@property (readonly, strong) NSString * audioRoute;

@property (nonatomic, copy) KVPlayerAudioManagerOutputBlock outputBlock;

+ (instancetype)audioManager;
- (AudioStreamBasicDescription)getFormat;
- (BOOL) activateAudioSession;
- (void) deactivateAudioSession;
- (BOOL) play;
- (void) pause;
- (void)setPlayRate:(CGFloat)playRate;

@end
