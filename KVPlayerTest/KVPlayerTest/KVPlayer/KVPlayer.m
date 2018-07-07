//
//  KVPlayer.m
//  KVPlayer
//
//  Created by kevin on 2018/4/24.
//  Copyright © 2018年 kv. All rights reserved.
//

#import "KVPlayer.h"
#import "KVPlayerDecoder.h"
#import <pthread.h>

#define kvplayer_dispatch_main_async_safe(block)\
if ([NSThread isMainThread]) {\
block();\
} else {\
dispatch_async(dispatch_get_main_queue(), block);\
}

#define kvplayer_min_duration   2
#define kvplayer_min_framescount    5
#define kvplayer_WO(object,weakObject) __weak __typeof(&*object)weakObject = object
#define kvplayer_WS(weakSelf)  kvplayer_WO(self,weakSelf)
#define KV_IS_IPAD (UI_USER_INTERFACE_IDIOM() == UIUserInterfaceIdiomPad)

@interface KVPlayer () <KVPlayerDecoderDelegate>

/**
 视频解码器
 */
@property (nonatomic, strong) KVPlayerDecoder * decoder;

@property (readwrite, nonatomic, assign) KVPlayerPlayState state; //播放状态
@property (readwrite, nonatomic, assign) int fps;
@property (nonatomic, assign) BOOL isPlaying;
@property (readwrite, nonatomic, strong) UIView * playView;  //播放视图
@property (nonatomic, strong) UIImageView * playImgView;    //播放的图片视图，RGB
@property (nonatomic, strong) UILabel * subTitleLabel;  //字幕

@property (atomic, strong) NSMutableArray * waitToPlayVideoFrames;   //等待播放的帧数据
@property (atomic, strong) NSMutableArray * waitToPlayAudioFrames;   //等待播放的音频数据
@property (atomic, strong) NSMutableArray * waitToPlaySubTitleFrames;   //等待播放的字幕数据
@property (nonatomic, strong) KVPlayerSubtitleFrame * showingSubTitleFrame; //展示中的字幕
@property (nonatomic, assign) CGFloat subTitleShowingPosition;  //正在展示的字幕开始时间
@property (nonatomic, copy) NSString * currentShowingSubTitle;  //当前正在展示的字幕
@property (nonatomic, assign) CGFloat subTitleStartPosition;    //字幕开始时间
@property (nonatomic, assign) CGFloat subTitleEndPosition;  //字幕结束时间

@property (nonatomic, strong) NSTimer * timer;
@property (readwrite, nonatomic, assign) float duration;
@property (nonatomic, assign) BOOL isWaitingForParse;
@property (atomic, assign) BOOL isRelease;
@property (atomic, assign) BOOL isSeek;

@property (nonatomic, assign) BOOL wantToNotPlay;

@property (nonatomic, strong) UIImage * currentImage;

@property (nonatomic, assign) CGFloat currentFPS;
@property (nonatomic, assign) CGFloat correctFPS;

@property (nonatomic, strong) NSTimer * nextFrameTimer;

@end

@implementation KVPlayer
{
    dispatch_queue_t _parseQueue;  //视频数据解析队列
    pthread_mutex_t _parseLock;
    pthread_mutex_t _dataUseLock;   //缓存数据数组使用锁
    
    CGFloat _moviePosition;
    NSData * _currentAudioFrame;
    NSUInteger _currentAudioFramePos;
    
    NSTimeInterval _tickCorrectionTime;
    NSTimeInterval _tickCorrectionPosition;
    
    BOOL _isSeekAfter;
}

@synthesize position = _position;
@synthesize selectAudioTrackIndex = _selectAudioTrackIndex;

- (instancetype)init {
    if (self = [super init]) {
        self.playView = [UIView new];
        self.playView.backgroundColor = [UIColor blackColor];
        
        self.playImgView = [UIImageView new];
        self.playImgView.layer.masksToBounds = YES;
        self.playImgView.contentMode = UIViewContentModeScaleAspectFit;
        [self.playView addSubview:self.playImgView];
        //增加约束，系统方法真的不好用，建议使用三方库
        self.playImgView.translatesAutoresizingMaskIntoConstraints = NO;
        NSLayoutConstraint * leftConstraint = [NSLayoutConstraint constraintWithItem:self.playImgView attribute:NSLayoutAttributeLeft relatedBy:NSLayoutRelationEqual toItem:self.playView attribute:NSLayoutAttributeLeft multiplier:1 constant:0];
        [self.playView addConstraint:leftConstraint];
        NSLayoutConstraint * rightConstraint = [NSLayoutConstraint constraintWithItem:self.playImgView attribute:NSLayoutAttributeRight relatedBy:NSLayoutRelationEqual toItem:self.playView attribute:NSLayoutAttributeRight multiplier:1 constant:0];
        [self.playView addConstraint:rightConstraint];
        NSLayoutConstraint * topConstraint = [NSLayoutConstraint constraintWithItem:self.playImgView attribute:NSLayoutAttributeTop relatedBy:NSLayoutRelationEqual toItem:self.playView attribute:NSLayoutAttributeTop multiplier:1 constant:0];
        [self.playView addConstraint:topConstraint];
        NSLayoutConstraint * bottomConstraint = [NSLayoutConstraint constraintWithItem:self.playImgView attribute:NSLayoutAttributeBottom relatedBy:NSLayoutRelationEqual toItem:self.playView attribute:NSLayoutAttributeBottom multiplier:1 constant:0];
        [self.playView addConstraint:bottomConstraint];
        
        self.subTitleLabel = [UILabel new];
        self.subTitleLabel.numberOfLines = 0;
        self.subTitleLabel.textAlignment = NSTextAlignmentCenter;
        [self.playImgView addSubview:self.subTitleLabel];
        self.subTitleLabel.translatesAutoresizingMaskIntoConstraints = NO;
        NSLayoutConstraint * bottomConstraint1 = [NSLayoutConstraint constraintWithItem:self.subTitleLabel attribute:NSLayoutAttributeBottom relatedBy:NSLayoutRelationEqual toItem:self.playImgView attribute:NSLayoutAttributeBottom multiplier:1 constant:-20];
        [self.playImgView addConstraint:bottomConstraint1];
        NSLayoutConstraint * centerXConstraint1 = [NSLayoutConstraint constraintWithItem:self.subTitleLabel attribute:NSLayoutAttributeCenterX relatedBy:NSLayoutRelationEqual toItem:self.playImgView attribute:NSLayoutAttributeCenterX multiplier:1 constant:0];
        [self.playImgView addConstraint:centerXConstraint1];
        NSLayoutConstraint * widthConstraint1 = [NSLayoutConstraint constraintWithItem:self.subTitleLabel attribute:NSLayoutAttributeWidth relatedBy:NSLayoutRelationLessThanOrEqual toItem:self.playImgView attribute:NSLayoutAttributeWidth multiplier:1 constant:0];
        [self.playImgView addConstraint:widthConstraint1];
        
        if (KV_IS_IPAD) {
            self.subTitleFontSize = 25;
        }else {
            self.subTitleFontSize = 22;
        }
        self.subTitleTextColor = [UIColor whiteColor];
        _screenMode = KVPlayerScreenFit;
        self.waitToPlayVideoFrames = [NSMutableArray array];
        self.waitToPlayAudioFrames = [NSMutableArray array];
        self.waitToPlaySubTitleFrames = [NSMutableArray array];
        self.wantToNotPlay = YES;
        _state = KVPlayerPlayStateIdle;
        _parseQueue = dispatch_queue_create("kvplayervideodataparse", NULL);
        pthread_mutex_init(&_parseLock, NULL);
        pthread_mutex_init(&_dataUseLock, NULL);
        [[KVPlayerAudioManager audioManager] activateAudioSession];
        _playRate = 1;
    }
    return self;
}

#pragma mark - public
- (BOOL)resetFile:(NSString *)path position:(float)position {
    if (![path isKindOfClass:[NSString class]]) {
        return NO;
    }
    if (!path.length) {
        return NO;
    }
    [self stopPlay];
    self.isSeek = YES;
    _tickCorrectionTime = 0;
    [self.waitToPlayAudioFrames removeAllObjects];
    [self.waitToPlayVideoFrames removeAllObjects];
    [self.waitToPlaySubTitleFrames removeAllObjects];
    pthread_mutex_unlock(&_dataUseLock);
    self.subTitleStartPosition = -1;
    self.subTitleEndPosition = -1;
    self.subTitleShowingPosition = -1;
    self.subTitleLabel.text = @"";
    self.validSubTitle = NO;
    self.currentImage = nil;
    self.wantToNotPlay = YES;
    self.state = KVPlayerPlayStateIdle;
    self.playImgView.image = nil;
    
    self.decoder = [[KVPlayerDecoder alloc] init];
    self.decoder.delegate = self;
    self.decoder.interruptCallback = ^BOOL{
        return YES;
    };
    //打开文件
    if ([self.decoder openFile:path]) {
        CGFloat duration = self.decoder.duration;
        if (position < duration) {
            self.decoder.position = position;
        }
        [self.decoder setupVideoFrameFormat:KVPlayerVideoFrameFormatRGB];
        //打开文件成功，开始解析视频数据
        self.isRelease = NO;
        self.isPlaying = NO;
        self.fps = ceil(self.decoder.fps);
        self.correctFPS = self.decoder.fps;
        self.currentFPS = self.decoder.fps;
        [self parseData];
        self.validSubTitle = self.decoder.validSubtitles;
    }else {
        //打开文件失败
        self.fps = 0;
        self.correctFPS = 0;
        self.currentFPS = 0;
        [self.decoder closeFile];
        self.decoder = nil;
        return NO;
    }
    return YES;
}

- (void)play {
    if (self.isPlaying || !self.decoder.fileIsOpen ||self.state == KVPlayerPlayStateLoading) {
        return;
    }
    self.isPlaying = YES;
    self.wantToNotPlay = NO;
    _tickCorrectionTime = 0;
    [self timeStart];   //开始播放
    [self enableAudio:YES];
    [[KVPlayerAudioManager audioManager] play];
}

- (void)pause {
    if (!self.isPlaying || !self.decoder.fileIsOpen) {
        return;
    }
    self.isPlaying = NO;
    self.wantToNotPlay = YES;
    [self enableAudio:NO];
    [[KVPlayerAudioManager audioManager] pause];
    self.state = KVPlayerPlayStatePause;
}

- (void)stop {
    if (!self.decoder.fileIsOpen) {
        return;
    }
    self.isPlaying = NO;
    [self stopPlay];
    self.state = KVPlayerPlayStateStop;
}

- (UIImage*)snapshot {
    return self.currentImage;
}

- (void)releasePlayer {
    [self stopPlay];
}

- (void)stopPlay {
    self.wantToNotPlay = YES;
    [self.nextFrameTimer invalidate];
    self.nextFrameTimer = nil;
    [[KVPlayerAudioManager audioManager] pause];
    pthread_mutex_lock(&_parseLock);
    self.isRelease = YES;
    self.decoder.isFinish = YES;
    pthread_mutex_unlock(&_parseLock);
}

#pragma mark - private
- (void)timeStart {
    if (self.decoder.isEOF && !self.waitToPlayVideoFrames.count) {
        //结束了
        self.wantToNotPlay = YES;
        [[KVPlayerAudioManager audioManager] pause];
        self.state = KVPlayerPlayStateFinish;
    }else {
        NSTimeInterval time = 0.01;
        NSTimeInterval duration = 0.01;
        BOOL isPlaying = NO;
        if (!self.wantToNotPlay) {
            if (self.waitToPlayVideoFrames.count) {
                duration = [self nextFrame];
                isPlaying = YES;
                
                NSTimeInterval correction = [self tickCorrection];
                if (self.playRate != 1.0) {
                    correction = 0;
                }
                time = duration + correction;
                if (time <= 0) {
                    time = 0.01;
                }
            }else {
                self.state = KVPlayerPlayStateLoading;
            }
        }

        if (!self.wantToNotPlay) {
            if (isPlaying) {
                self.state = KVPlayerPlayStatePlaying;
            }
            NSTimeInterval newTime = time / self.playRate;
            self.nextFrameTimer = [NSTimer scheduledTimerWithTimeInterval:newTime target:self selector:@selector(timeStart) userInfo:nil repeats:NO];
            [[NSRunLoop currentRunLoop] addTimer:self.nextFrameTimer forMode:NSRunLoopCommonModes];
        }
        if (self.waitToPlayVideoFrames.count < kvplayer_min_duration * self.decoder.fps && self.isWaitingForParse) {
            self.isWaitingForParse = NO;
            [self parseData];
        }
    }
}

- (CGFloat)tickCorrection
{
    const NSTimeInterval now = [NSDate timeIntervalSinceReferenceDate];
    
    if (!_tickCorrectionTime || _isSeekAfter) {
        _isSeekAfter = NO;
        _tickCorrectionTime = now;
        _tickCorrectionPosition = _moviePosition;
        return 0;
    }
    
    NSTimeInterval dPosition = _moviePosition - _tickCorrectionPosition;
    NSTimeInterval dTime = now - _tickCorrectionTime;
    NSTimeInterval correction = dPosition - dTime;
    
    if (correction > 1.f || correction < -1.f) {
        correction = 0;
        _tickCorrectionTime = 0;
    }
    
    return correction;
}

- (CGFloat)nextFrame {
    if (self.isRelease) {
        return 0;
    }
    CGFloat duration = 0;
    pthread_mutex_lock(&_dataUseLock);
    if (!self.waitToPlayVideoFrames.count) {
        pthread_mutex_unlock(&_dataUseLock);
        return 0;
    }
    KVPlayerVideoFrame * frame = self.waitToPlayVideoFrames.firstObject;
    duration = frame.duration;
    CGFloat position = frame.position;
    CGFloat fps = 1.0 / frame.duration;
    if (fps < self.currentFPS) {
        self.currentFPS = fps;
        self.fps = ceil(fps);
        if ([self.delegate respondsToSelector:@selector(player:fpsChanged:)]) {
            [self.delegate player:self fpsChanged:self.fps];
        }
    }else if (self.correctFPS < self.currentFPS) {
        self.currentFPS = self.correctFPS;
        self.fps = ceil(self.correctFPS);
        if ([self.delegate respondsToSelector:@selector(player:fpsChanged:)]) {
            [self.delegate player:self fpsChanged:self.fps];
        }
    }
    if ((int)_moviePosition != (int)position) {
        if ([self.delegate respondsToSelector:@selector(player:playAtTime:)]) {
            [self.delegate player:self playAtTime:position];
        }
    }
    _moviePosition = position;
    KVPlayerVideoFrameRGB * rgbFrame = (KVPlayerVideoFrameRGB*)frame;
    UIImage * image = [rgbFrame asImage];
    if (image) {
        self.playImgView.image = image;
        self.currentImage = image;
    }else {
        KVLog(@"转化图片失败");
    }
    
    [self.waitToPlayVideoFrames removeObject:frame];
    //判断字幕
    if (self.waitToPlaySubTitleFrames.count) {
        if (self.subTitleStartPosition < position) {
            //还未初始化
            BOOL isFinish = NO;
            while (!isFinish) {
                KVPlayerSubtitleFrame * frame = self.waitToPlaySubTitleFrames.firstObject;
                [self.waitToPlaySubTitleFrames removeObject:frame];
                if (position > frame.position) {
                    //视频画面已经比字幕先走了，直接下一个
                    if (self.waitToPlaySubTitleFrames.count) {
                        continue;
                    }else {
                        isFinish = YES;
                    }
                }else {
                    self.showingSubTitleFrame = frame;
                    self.subTitleStartPosition = frame.position;
                    isFinish = YES;
                }
            }
        }
    }
    
    if (self.subTitleEndPosition != -1) {
        //判断是否要隐藏
        CGFloat cha = MAX(position, self.subTitleEndPosition) - MIN(position, self.subTitleEndPosition);
        if (cha <= 0.1) {
            [self setSubTitleText:@""];
            self.subTitleEndPosition = -1;
        }
    }
    
    if (self.subTitleStartPosition != -1 && self.subTitleStartPosition != self.subTitleShowingPosition) {
        //判断停止时间
        CGFloat cha = MAX(position, self.subTitleStartPosition) - MIN(position, self.subTitleStartPosition);
        if (cha <= 0.1) {
            if (self.showingSubTitleFrame) {
                [self setSubTitleText:self.showingSubTitleFrame.text];
                self.subTitleEndPosition = self.showingSubTitleFrame.duration + self.showingSubTitleFrame.position;
                self.subTitleShowingPosition = self.subTitleStartPosition;
            }
        }
    }
    pthread_mutex_unlock(&_dataUseLock);
    return duration;
}

- (void)setSubTitleText:(NSString*)subTitle {
    if (subTitle.length) {
        subTitle = [subTitle stringByReplacingOccurrencesOfString:@"\r" withString:@"\n"];
        NSArray * arr = [subTitle componentsSeparatedByString:@"\n"];
        if (arr.count > 1) {
            NSMutableString * str = [NSMutableString string];
            for (NSInteger i = 0; i < arr.count; i++) {
                NSString * subStr = arr[i];
                if (subStr.length) {
                    if (i != 0) {
                        [str appendString:@"\n"];
                    }
                    [str appendString:subStr];
                }
            }
            subTitle = str;
        }
    }
    if (subTitle.length) {
        NSMutableParagraphStyle * para = [[NSMutableParagraphStyle alloc] init];
        para.lineSpacing = 5;
        NSAttributedString * att = [[NSAttributedString alloc] initWithString:subTitle attributes:@{NSFontAttributeName : [UIFont systemFontOfSize:self.subTitleFontSize], NSForegroundColorAttributeName : self.subTitleTextColor, NSParagraphStyleAttributeName : para}];
        self.subTitleLabel.attributedText = att;
        self.subTitleLabel.textAlignment = NSTextAlignmentCenter;
        self.currentShowingSubTitle = subTitle;
    }else {
        self.subTitleLabel.attributedText = nil;
        self.currentShowingSubTitle = @"";
    }
}

- (void)parseData {
    kvplayer_WS(weakSelf);
    dispatch_async(_parseQueue, ^{
        [weakSelf parseDataSmall];
    });
}

- (void)parseDataSmall {
    if (!self.decoder.isEOF) {
        if (self.isRelease) {
            return;
        }
        pthread_mutex_lock(&_parseLock);
        if (self.isSeek) {
            pthread_mutex_lock(&_dataUseLock);
            self.isSeek = NO;
            [self.waitToPlayAudioFrames removeAllObjects];
            [self.waitToPlayVideoFrames removeAllObjects];
            [self.waitToPlaySubTitleFrames removeAllObjects];
            pthread_mutex_unlock(&_dataUseLock);
        }
        
        NSInteger frameCount = kvplayer_min_framescount;
        CGFloat newfps = 0;
        NSArray * frames = [self.decoder decodeFrames:frameCount newFps:&newfps];
        if (newfps) {
            self.correctFPS = newfps;
        }
        if (frames.count) {
            for (KVPlayerBaseFrame * frame in frames) {
                if (frame.type == KVPlayerFrameTypeVideo) {
                    [self.waitToPlayVideoFrames addObject:frame];
                }else if (frame.type == KVPlayerFrameTypeAudio) {
                    [self.waitToPlayAudioFrames addObject:frame];
                }else if (frame.type == KVPlayerFrameTypeSubtitle) {
                    [self.waitToPlaySubTitleFrames addObject:frame];
                }
            }
        }
        pthread_mutex_unlock(&_parseLock);
        if (self.isRelease) {
            return;
        }
        if (!self.decoder.isEOF) {
            self.isWaitingForParse = YES;
        }
    }
}

#pragma makr - 音频处理
- (void)enableAudio:(BOOL)on {
    KVPlayerAudioManager * audioManager = [KVPlayerAudioManager audioManager];
    if (on && _decoder.validAudio) {
        kvplayer_WS(weakSelf);
        audioManager.outputBlock = ^(float *outData, UInt32 numFrames, UInt32 numChannels) {
            [weakSelf audioCallbackFillData: outData numFrames:numFrames numChannels:numChannels];
        };
    } else {
        audioManager.outputBlock = nil;
    }
}

//填充音频数据
- (void) audioCallbackFillData: (float *) outData
                     numFrames: (UInt32) numFrames
                   numChannels: (UInt32) numChannels
{
    if (!self.waitToPlayAudioFrames.count) {
        //没有音频数据，静音
        memset(outData, 0, numFrames * numChannels * sizeof(float));
        return;
    }
    
    while (numFrames > 0) {
        if (!_currentAudioFrame) {
            
            NSUInteger count = self.waitToPlayAudioFrames.count;
            
            if (count > 0) {
                
                KVPlayerAudioFrame *frame = self.waitToPlayAudioFrames[0];
                if (_decoder.validVideo) {
                    CGFloat delta = _moviePosition - frame.position;
                    if (delta < -(0.5 * self.playRate)) {
                        memset(outData, 0, numFrames * numChannels * sizeof(float));
                        break; // silence and exit
                    }
                    
                    [self.waitToPlayAudioFrames removeObjectAtIndex:0];
                    
                    if (delta > (0.5 * self.playRate) && count > 1) {
                        continue;
                    }
                    
                } else {
                    [self.waitToPlayAudioFrames removeObjectAtIndex:0];
                    _moviePosition = frame.position;
                }
                
                _currentAudioFramePos = 0;
                _currentAudioFrame = frame.samples;
                frame = nil;
            }
        }
        
        if (_currentAudioFrame) {
            
            const void *bytes = (Byte *)_currentAudioFrame.bytes + _currentAudioFramePos;
            const NSUInteger bytesLeft = (_currentAudioFrame.length - _currentAudioFramePos);
            const NSUInteger frameSizeOf = numChannels * sizeof(float);
            const NSUInteger bytesToCopy = MIN(numFrames * frameSizeOf, bytesLeft);
            const NSUInteger framesToCopy = bytesToCopy / frameSizeOf;
            
            memcpy(outData, bytes, bytesToCopy);
            numFrames -= framesToCopy;
            outData += framesToCopy * numChannels;
            
            if (bytesToCopy < bytesLeft)
                _currentAudioFramePos += bytesToCopy;
            else
                _currentAudioFrame = nil;
        } else {
            memset(outData, 0, numFrames * numChannels * sizeof(float));
            break;
        }
    }
}

#pragma mark - decoder代理
- (void)decoder:(KVPlayerDecoder *)decoder errorWithCode:(KVPlayerDecoderErrorCode)code msg:(NSString *)msg {
    KVLog(@"%@", msg);
}

#pragma mark - setter
- (void)setState:(KVPlayerPlayState)state {
    if (_state == state) {
        return;
    }
    _state = state;
    kvplayer_dispatch_main_async_safe(^{
        if ([self.delegate respondsToSelector:@selector(player:playStateChange:)]) {
            [self.delegate player:self playStateChange:state];
        }
    });
}

- (void)setPosition:(float)position {
    [self resetPosition:position wantToPlay:YES];
}

- (void)resetPosition:(float)position wantToPlay:(BOOL)wantToPlay {
    if (self.decoder) {
        [self stopPlay];
        self.isSeek = YES;
        self.state = KVPlayerPlayStateLoading;
        _position = position;
        self.decoder.position = position;
        self.isRelease = NO;
        self.decoder.isFinish = NO;
        self.subTitleStartPosition = -1;
        self.subTitleEndPosition = -1;
        self.subTitleShowingPosition = -1;
        self.subTitleLabel.text = @"";
        [self parseData];  //重新解析数据
        self.isPlaying = NO;
        self.state = KVPlayerPlayStateIdle;
        if (wantToPlay) {
            [self play];
        }
        _isSeekAfter = YES;
    }
}

- (void)setScreenMode:(KVPlayerScreenMode)screenMode {
    _screenMode = screenMode;
    if (screenMode == KVPlayerScreenFit) {
        self.playImgView.contentMode = UIViewContentModeScaleAspectFit;
        self.playImgView.translatesAutoresizingMaskIntoConstraints = NO;
        [self.playImgView removeConstraints:self.playImgView.constraints];
        NSLayoutConstraint * leftConstraint = [NSLayoutConstraint constraintWithItem:self.playImgView attribute:NSLayoutAttributeLeft relatedBy:NSLayoutRelationEqual toItem:self.playView attribute:NSLayoutAttributeLeft multiplier:1 constant:0];
        [self.playView addConstraint:leftConstraint];
        NSLayoutConstraint * rightConstraint = [NSLayoutConstraint constraintWithItem:self.playImgView attribute:NSLayoutAttributeRight relatedBy:NSLayoutRelationEqual toItem:self.playView attribute:NSLayoutAttributeRight multiplier:1 constant:0];
        [self.playView addConstraint:rightConstraint];
        NSLayoutConstraint * topConstraint = [NSLayoutConstraint constraintWithItem:self.playImgView attribute:NSLayoutAttributeTop relatedBy:NSLayoutRelationEqual toItem:self.playView attribute:NSLayoutAttributeTop multiplier:1 constant:0];
        [self.playView addConstraint:topConstraint];
        NSLayoutConstraint * bottomConstraint = [NSLayoutConstraint constraintWithItem:self.playImgView attribute:NSLayoutAttributeBottom relatedBy:NSLayoutRelationEqual toItem:self.playView attribute:NSLayoutAttributeBottom multiplier:1 constant:0];
        [self.playView addConstraint:bottomConstraint];
    }else if (screenMode == KVPlayerScreenFill) {
        self.playImgView.contentMode = UIViewContentModeScaleAspectFill;
        self.playImgView.translatesAutoresizingMaskIntoConstraints = NO;
        [self.playImgView removeConstraints:self.playImgView.constraints];
        NSLayoutConstraint * leftConstraint = [NSLayoutConstraint constraintWithItem:self.playImgView attribute:NSLayoutAttributeLeft relatedBy:NSLayoutRelationEqual toItem:self.playView attribute:NSLayoutAttributeLeft multiplier:1 constant:0];
        [self.playView addConstraint:leftConstraint];
        NSLayoutConstraint * rightConstraint = [NSLayoutConstraint constraintWithItem:self.playImgView attribute:NSLayoutAttributeRight relatedBy:NSLayoutRelationEqual toItem:self.playView attribute:NSLayoutAttributeRight multiplier:1 constant:0];
        [self.playView addConstraint:rightConstraint];
        NSLayoutConstraint * topConstraint = [NSLayoutConstraint constraintWithItem:self.playImgView attribute:NSLayoutAttributeTop relatedBy:NSLayoutRelationEqual toItem:self.playView attribute:NSLayoutAttributeTop multiplier:1 constant:0];
        [self.playView addConstraint:topConstraint];
        NSLayoutConstraint * bottomConstraint = [NSLayoutConstraint constraintWithItem:self.playImgView attribute:NSLayoutAttributeBottom relatedBy:NSLayoutRelationEqual toItem:self.playView attribute:NSLayoutAttributeBottom multiplier:1 constant:0];
        [self.playView addConstraint:bottomConstraint];
    }else if (screenMode == KVPlayerScreenOneToOne) {
        self.playImgView.contentMode = UIViewContentModeScaleAspectFill;
        NSInteger minW = MIN([UIScreen mainScreen].bounds.size.width, [UIScreen mainScreen].bounds.size.height) / 3.0 * 2.0;
        self.playImgView.translatesAutoresizingMaskIntoConstraints = NO;
        [self.playImgView removeConstraints:self.playImgView.constraints];
        NSLayoutConstraint * centerXConstraint = [NSLayoutConstraint constraintWithItem:self.playImgView attribute:NSLayoutAttributeCenterX relatedBy:NSLayoutRelationEqual toItem:self.playView attribute:NSLayoutAttributeCenterX multiplier:1 constant:0];
        [self.playView addConstraint:centerXConstraint];
        NSLayoutConstraint * centerYConstraint = [NSLayoutConstraint constraintWithItem:self.playImgView attribute:NSLayoutAttributeCenterY relatedBy:NSLayoutRelationEqual toItem:self.playView attribute:NSLayoutAttributeCenterY multiplier:1 constant:0];
        [self.playView addConstraint:centerYConstraint];
        NSLayoutConstraint * widthConstraint = [NSLayoutConstraint constraintWithItem:self.playImgView attribute:NSLayoutAttributeWidth relatedBy:NSLayoutRelationEqual toItem:nil attribute:NSLayoutAttributeNotAnAttribute multiplier:1 constant:minW];
        [self.playView addConstraint:widthConstraint];
        NSLayoutConstraint * heightConstraint = [NSLayoutConstraint constraintWithItem:self.playImgView attribute:NSLayoutAttributeHeight relatedBy:NSLayoutRelationEqual toItem:nil attribute:NSLayoutAttributeNotAnAttribute multiplier:1 constant:minW];
        [self.playView addConstraint:heightConstraint];
    }else {
        self.playImgView.contentMode = UIViewContentModeScaleAspectFit;
        NSInteger minW = MIN([UIScreen mainScreen].bounds.size.width, [UIScreen mainScreen].bounds.size.height) / 3.0 * 2.0;
        self.playImgView.translatesAutoresizingMaskIntoConstraints = NO;
        [self.playView removeConstraints:self.playImgView.constraints];
        NSLayoutConstraint * centerXConstraint = [NSLayoutConstraint constraintWithItem:self.playImgView attribute:NSLayoutAttributeCenterX relatedBy:NSLayoutRelationEqual toItem:self.playView attribute:NSLayoutAttributeCenterX multiplier:1 constant:0];
        [self.playView addConstraint:centerXConstraint];
        NSLayoutConstraint * centerYConstraint = [NSLayoutConstraint constraintWithItem:self.playImgView attribute:NSLayoutAttributeCenterY relatedBy:NSLayoutRelationEqual toItem:self.playView attribute:NSLayoutAttributeCenterY multiplier:1 constant:0];
        [self.playView addConstraint:centerYConstraint];
        NSLayoutConstraint * widthConstraint = [NSLayoutConstraint constraintWithItem:self.playImgView attribute:NSLayoutAttributeWidth relatedBy:NSLayoutRelationEqual toItem:nil attribute:NSLayoutAttributeNotAnAttribute multiplier:1 constant:minW];
        [self.playView addConstraint:widthConstraint];
        NSLayoutConstraint * heightConstraint = [NSLayoutConstraint constraintWithItem:self.playImgView attribute:NSLayoutAttributeHeight relatedBy:NSLayoutRelationEqual toItem:nil attribute:NSLayoutAttributeNotAnAttribute multiplier:1 constant:minW];
        [self.playView addConstraint:heightConstraint];
    }
}

- (void)setSelectAudioTrackIndex:(NSInteger)selectAudioTrackIndex {
    if (self.state == KVPlayerPlayStateLoading) {
        return;
    }
    if (selectAudioTrackIndex < self.audioTrackCount) {
        _selectAudioTrackIndex = selectAudioTrackIndex;
        [self stopPlay];
        self.isSeek = YES;
        self.decoder.selectedAudioStream = selectAudioTrackIndex;
        self.decoder.position = _moviePosition;
        self.isRelease = NO;
        self.decoder.isFinish = NO;
        [self parseData];  //重新解析数据
        self.isPlaying = NO;
        [self play];
    }
}

- (void)setPlayRate:(float)playRate {
    if (playRate <= 0 || playRate > 2.0) {
        return;
    }
    _playRate = playRate;
    [[KVPlayerAudioManager audioManager] setPlayRate:playRate];
}

- (void)setSubTitleHidden:(BOOL)subTitleHidden {
    _subTitleHidden = subTitleHidden;
    self.subTitleLabel.hidden = subTitleHidden;
}

- (void)setSubTitleTextColor:(UIColor *)subTitleTextColor {
    _subTitleTextColor = subTitleTextColor;
    self.subTitleLabel.textColor = subTitleTextColor;
    [self setSubTitleText:self.currentShowingSubTitle];
}

- (void)setSubTitleFontSize:(NSInteger)subTitleFontSize {
    _subTitleFontSize = subTitleFontSize;
    self.subTitleLabel.font = [UIFont systemFontOfSize:subTitleFontSize];
    [self setSubTitleText:self.currentShowingSubTitle];
}

#pragma mark - getter
- (float)duration {
    return self.decoder.duration;
}

- (NSInteger)audioTrackCount {
    return self.decoder.audioStreamsCount;
}

- (NSInteger)selectAudioTrackIndex {
    return self.decoder.selectedAudioStream;
}

- (CGSize)videoSize {
    return CGSizeMake(self.decoder.frameWidth, self.decoder.frameHeight);
}

- (void)dealloc {
    pthread_mutex_destroy(&_parseLock);
    pthread_mutex_destroy(&_dataUseLock);
    if (self.decoder) {
        [self.decoder closeFile];
        self.decoder = nil;
    }
}

@end
