//
//  KVPlayerDecoder.h
//  KVPlayer
//
//  Created by kevin on 2018/4/24.
//  Copyright © 2018年 kv. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "KVPlayerDef.h"

typedef NS_ENUM(NSInteger, KVPlayerDecoderErrorCode) {
    KVPlayerDecoderFileError,   //文件错误
    KVPlayerDecoderOtherError   //其他错误
};

typedef BOOL(^KVPlayerDecoderDecoderInterruptCallback)(void);

@class KVPlayerDecoder;

@protocol KVPlayerDecoderDelegate <NSObject>

- (void)decoder:(KVPlayerDecoder*)decoder errorWithCode:(KVPlayerDecoderErrorCode)code msg:(NSString*)msg;

@end

@interface KVPlayerDecoder : NSObject

@property (nonatomic, weak) id <KVPlayerDecoderDelegate> delegate;
@property (readonly, nonatomic, assign) BOOL fileIsOpen;
@property (readonly, nonatomic, copy) NSString * path;
@property (readonly, atomic, assign) BOOL isEOF;
@property (nonatomic, assign) CGFloat position;
@property (readonly, nonatomic, assign) CGFloat duration;
@property (readonly, nonatomic, assign) CGFloat fps;
@property (readonly, nonatomic, assign) CGFloat sampleRate;
@property (readonly, nonatomic, assign) NSUInteger frameWidth;
@property (readonly, nonatomic, assign) NSUInteger frameHeight;
@property (readonly, nonatomic, assign) NSUInteger audioStreamsCount;
@property (readonly, nonatomic, assign) NSUInteger subtitleStreamsCount;
@property (readonly, nonatomic, strong) NSDictionary *info;
@property (readonly, nonatomic, strong) NSString *videoStreamFormatName;

@property (nonatomic, assign) NSInteger selectedAudioStream;
@property (nonatomic, assign) NSInteger selectedSubtitleStream;

@property (readonly, nonatomic, assign) BOOL validVideo;
@property (readonly, nonatomic, assign) BOOL validAudio;
@property (readonly, nonatomic, assign) BOOL validSubtitles;

@property (readonly, nonatomic, assign) BOOL isNetwork;
@property (nonatomic, copy) KVPlayerDecoderDecoderInterruptCallback interruptCallback;
@property (atomic, assign) BOOL isFinish;

- (BOOL)openFile:(NSString*)path;

- (BOOL)setupVideoFrameFormat:(KVPlayerVideoFrameFormat)format;

- (NSArray*)decodeFrames:(NSInteger)frameCount newFps:(CGFloat*)newFps;

- (NSArray*)decodeFramesByDuration:(CGFloat)duration;

- (void)closeFile;

@end
