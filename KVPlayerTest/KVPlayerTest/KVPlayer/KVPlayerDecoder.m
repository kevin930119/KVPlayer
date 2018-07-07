//
//  KVPlayerDecoder.m
//  KVPlayer
//
//  Created by kevin on 2018/4/24.
//  Copyright © 2018年 kv. All rights reserved.
//

#import "KVPlayerDecoder.h"
#include "libavformat/avformat.h"
#include "libswscale/swscale.h"
#include "libswresample/swresample.h"
#include "libavutil/pixdesc.h"
#import <Accelerate/Accelerate.h>

static int interrupt_callback(void *ctx);

static void KVPlayerLog(void* context, int level, const char* format, va_list args);

static void avStreamFPSTimeBase(AVStream *st, CGFloat defaultTimeBase, CGFloat *pFPS, CGFloat *pTimeBase)
{
    CGFloat fps, timebase;
    
    if (st->time_base.den && st->time_base.num)
        timebase = av_q2d(st->time_base);
    else if(st->codec->time_base.den && st->codec->time_base.num)
        timebase = av_q2d(st->codec->time_base);
    else
        timebase = defaultTimeBase;
    
    if (st->codec->ticks_per_frame != 1) {
        
    }
    
    if (st->avg_frame_rate.den && st->avg_frame_rate.num)
        fps = av_q2d(st->avg_frame_rate);
    else if (st->r_frame_rate.den && st->r_frame_rate.num)
        fps = av_q2d(st->r_frame_rate);
    else
        fps = 1.0 / timebase;
    
    if (pFPS)
        *pFPS = fps;
    if (pTimeBase)
        *pTimeBase = timebase;
}

static BOOL audioCodecIsSupported(AVCodecContext *audio)
{
    if (audio->sample_fmt == AV_SAMPLE_FMT_S16) {
        
        KVPlayerAudioManager * audioManager = [KVPlayerAudioManager audioManager];
        return  (int)audioManager.samplingRate == audio->sample_rate &&
        audioManager.numOutputChannels == audio->channels;
    }
    return NO;
}

@interface KVPlayerDecoder ()

@property (readwrite, nonatomic, assign) BOOL fileIsOpen;
@property (readwrite, nonatomic, copy) NSString * path;
@property (readwrite, atomic, assign) BOOL isEOF;
@property (atomic, assign) NSInteger endFlagCount;  //五次
@property (nonatomic, assign) CGFloat currentPosition;
@property (readwrite, nonatomic, assign) CGFloat duration;
@property (readwrite, nonatomic, assign) CGFloat fps;
@property (readwrite, nonatomic, assign) CGFloat sampleRate;
@property (readwrite, nonatomic, assign) NSUInteger frameWidth;
@property (readwrite, nonatomic, assign) NSUInteger frameHeight;
@property (readwrite, nonatomic, assign) NSUInteger audioStreamsCount;
@property (readwrite, nonatomic, assign) NSUInteger subtitleStreamsCount;
@property (readwrite, nonatomic, assign) BOOL validVideo;
@property (readwrite, nonatomic, assign) BOOL validAudio;
@property (readwrite, nonatomic, assign) BOOL validSubtitles;
@property (readwrite, nonatomic, strong) NSDictionary *info;
@property (readwrite, nonatomic, strong) NSString *videoStreamFormatName;
@property (readwrite, nonatomic, assign) BOOL isNetwork;

@end

@implementation KVPlayerDecoder
{
    AVFormatContext * _formatCtx;
    AVCodecContext * _videoCodecCtx;
    AVCodecContext * _audioCodecCtx;
    AVCodecContext * _subtitleCodecCtx;
    AVFrame * _videoFrame;
    AVFrame * _audioFrame;
    NSInteger _videoStream;
    NSInteger _audioStream;
    NSInteger _subtitleStream;
    AVPicture _picture;
    BOOL _pictureValid;
    struct SwsContext * _swsContext;
    CGFloat _videoTimeBase;
    CGFloat _audioTimeBase;
    CGFloat _position;
    NSArray * _videoStreams;
    NSArray * _audioStreams;
    NSArray * _subtitleStreams;
    SwrContext * _swrContext;
    void * _swrBuffer;
    NSUInteger _swrBufferSize;
    NSDictionary * _info;
    KVPlayerVideoFrameFormat _videoFrameFormat;
    NSUInteger _artworkStream;
    NSInteger _subtitleASSEvents;
    
    CGFloat _newFps;
}

+ (void)initialize {
    av_log_set_callback(KVPlayerLog);
    avcodec_register_all();
    av_register_all();  //注册所有解码器
    avformat_network_init();
}

#pragma mark - 打开文件相关操作
- (BOOL)openFile:(NSString*)path {
    BOOL flag = NO;
    self.path = path;
    self.fileIsOpen = NO;
    self.validSubtitles = NO;
    self.endFlagCount = 0;
    if ([self openInput:path]) {
        BOOL videoOpen = [self openVideoStream];
        BOOL audioOpen = [self openAudioStream];
        _subtitleStream = -1;
        if (videoOpen && audioOpen) {
            flag = YES;
            self.fileIsOpen = YES;
            _subtitleStreams = [self collectStreams:_formatCtx type:AVMEDIA_TYPE_SUBTITLE];
            if (_subtitleStreams.count) {
                NSNumber * n = _subtitleStreams.firstObject;
                [self openSubtitleStream:[n integerValue]];
                self.validSubtitles = YES;
            }else {
                //NSLog(@"没有字幕");
            }
        }else {
            [self closeFile];
            [self sendError:KVPlayerDecoderFileError msg:@"无法打开文件"];
        }
    }else {
        [self closeFile];
    }
    return flag;
}

- (BOOL)openInput:(NSString*)path {
    BOOL flag = NO;
    AVFormatContext * formatCtx = NULL;
//    if (self.interruptCallback) {
//        formatCtx = avformat_alloc_context();
//        if (!formatCtx) {
//            [self sendError:KVPlayerDecoderOtherError msg:@"FFmpeg出错"];
//            return flag;
//        }
//        AVIOInterruptCB cb = {interrupt_callback, (__bridge void *)(self)};
//        formatCtx->interrupt_callback = cb;
//    }else {
//        [self sendError:KVPlayerDecoderOtherError msg:@"没有设置解码回调"];
//        return flag;
//    }
    if (avformat_open_input(&formatCtx, [path UTF8String], NULL, NULL) != 0) {
        avformat_free_context(formatCtx);
        [self sendError:KVPlayerDecoderFileError msg:@"打开文件失败"];
        return flag;
    }
    
    if (avformat_find_stream_info(formatCtx, NULL) < 0) {
        avformat_close_input(&formatCtx);
        [self sendError:KVPlayerDecoderFileError msg:@"没有找到文件信息"];
        return flag;
    }
    
    _formatCtx = formatCtx;
    if (formatCtx == NULL) {
        flag = NO;
    }else {
        flag = YES;
    }
    return flag;
}

//打开视频流
- (BOOL)openVideoStream {
    BOOL flag = NO;
    _videoStream = -1;
    _artworkStream = -1;
    _videoStreams = [self collectStreams:_formatCtx type:AVMEDIA_TYPE_VIDEO];
    for (NSNumber *n in _videoStreams) {
        const NSUInteger iStream = n.integerValue;
        if (0 == (_formatCtx->streams[iStream]->disposition & AV_DISPOSITION_ATTACHED_PIC)) {
            if ([self openVideoStream:iStream]) {
                flag = YES;
                break;
            }
        } else {
            _artworkStream = iStream;
        }
    }
    return flag;
}

//打开某个视频流
- (BOOL)openVideoStream:(NSInteger)videoStream {
    BOOL flag = NO;
    AVCodecContext * codecCtx = _formatCtx->streams[videoStream]->codec;
    AVCodec *codec = avcodec_find_decoder(codecCtx->codec_id);
    if (!codec) {
        return flag;
    }
    if (avcodec_open2(codecCtx, codec, NULL) < 0) {
        return flag;
    }
    _videoFrame = av_frame_alloc();
    
    if (!_videoFrame) {
        avcodec_close(codecCtx);
        return flag;
    }
    
    _videoStream = videoStream;
    _videoCodecCtx = codecCtx;
    AVStream *st = _formatCtx->streams[_videoStream];
    avStreamFPSTimeBase(st, 0.04, &_fps, &_videoTimeBase);
    flag = YES;
    _fps = ceil(_fps);
    return flag;
}

//打开音频流
- (BOOL)openAudioStream {
    BOOL flag = NO;
    _audioStream = -1;
    _audioStreams = [self collectStreams:_formatCtx type:AVMEDIA_TYPE_AUDIO];
    for (NSNumber *n in _audioStreams) {
        if ([self openAudioStream: n.integerValue]) {
            flag = YES;
            break;
        }
    }
    return flag;
}

//打开某个音频流
- (BOOL)openAudioStream:(NSInteger)audioStream {
    BOOL flag = NO;
    AVCodecContext *codecCtx = _formatCtx->streams[audioStream]->codec;
    SwrContext *swrContext = NULL;
    
    AVCodec *codec = avcodec_find_decoder(codecCtx->codec_id);
    if(!codec) {
        return flag;
    }
    
    if (avcodec_open2(codecCtx, codec, NULL) < 0)
        return flag;
    //音频处理
    if (!audioCodecIsSupported(codecCtx)) {
        KVPlayerAudioManager * audioManager = [KVPlayerAudioManager audioManager];
        swrContext = swr_alloc_set_opts(NULL, av_get_default_channel_layout(audioManager.numOutputChannels), AV_SAMPLE_FMT_S16, audioManager.samplingRate, av_get_default_channel_layout(codecCtx->channels), codecCtx->sample_fmt, codecCtx->sample_rate, 0, NULL);
        if (!swrContext ||
            swr_init(swrContext)) {
            if (swrContext)
                swr_free(&swrContext);
            avcodec_close(codecCtx);
            return flag;
        }
    }
    
    _audioFrame = av_frame_alloc();
    
    if (!_audioFrame) {
        if (swrContext)
            swr_free(&swrContext);
        avcodec_close(codecCtx);
        return flag;
    }
    
    _audioStream = audioStream;
    _audioCodecCtx = codecCtx;
    _swrContext = swrContext;
    
    AVStream *st = _formatCtx->streams[_audioStream];
    avStreamFPSTimeBase(st, 0.025, 0, &_audioTimeBase);
    flag = YES;
    return flag;
}

- (BOOL) openSubtitleStream: (NSInteger) subtitleStream
{
    AVCodecContext *codecCtx = _formatCtx->streams[subtitleStream]->codec;
    
    AVCodec *codec = avcodec_find_decoder(codecCtx->codec_id);
    if(!codec)
        return NO;
    
    const AVCodecDescriptor *codecDesc = avcodec_descriptor_get(codecCtx->codec_id);
    if (codecDesc && (codecDesc->props & AV_CODEC_PROP_BITMAP_SUB)) {
        // Only text based subtitles supported
        return NO;
    }
    
    if (avcodec_open2(codecCtx, codec, NULL) < 0)
        return NO;
    
    _subtitleStream = subtitleStream;
    _subtitleCodecCtx = codecCtx;
    
    _subtitleASSEvents = -1;
    
    if (codecCtx->subtitle_header_size) {
        
        NSString *s = [[NSString alloc] initWithBytes:codecCtx->subtitle_header
                                               length:codecCtx->subtitle_header_size
                                             encoding:NSASCIIStringEncoding];
        
        if (s.length) {
            
            NSArray *fields = [self parseEvents:s];
            if (fields.count && [fields.lastObject isEqualToString:@"Text"]) {
                _subtitleASSEvents = fields.count;
            }
        }
    }
    
    return YES;
}

- (NSArray*)parseEvents:(NSString*)events
{
    NSRange r = [events rangeOfString:@"[Events]"];
    if (r.location != NSNotFound) {
        
        NSUInteger pos = r.location + r.length;
        
        r = [events rangeOfString:@"Format:"
                          options:0
                            range:NSMakeRange(pos, events.length - pos)];
        
        if (r.location != NSNotFound) {
            
            pos = r.location + r.length;
            r = [events rangeOfCharacterFromSet:[NSCharacterSet newlineCharacterSet]
                                        options:0
                                          range:NSMakeRange(pos, events.length - pos)];
            
            if (r.location != NSNotFound) {
                
                NSString *format = [events substringWithRange:NSMakeRange(pos, r.location - pos)];
                NSArray *fields = [format componentsSeparatedByString:@","];
                if (fields.count > 0) {
                    
                    NSCharacterSet *ws = [NSCharacterSet whitespaceCharacterSet];
                    NSMutableArray *ma = [NSMutableArray array];
                    for (NSString *s in fields) {
                        [ma addObject:[s stringByTrimmingCharactersInSet:ws]];
                    }
                    return ma;
                }
            }
        }
    }
    
    return nil;
}

//设置图片合成
- (BOOL) setupScaler {
    [self closeScaler];
    
    _pictureValid = avpicture_alloc(&_picture,
                                    AV_PIX_FMT_RGB24,
                                    _videoCodecCtx->width,
                                    _videoCodecCtx->height) == 0;
    
    if (!_pictureValid)
        return NO;
    
    _swsContext = sws_getCachedContext(_swsContext,
                                       _videoCodecCtx->width,
                                       _videoCodecCtx->height,
                                       _videoCodecCtx->pix_fmt,
                                       _videoCodecCtx->width,
                                       _videoCodecCtx->height,
                                       AV_PIX_FMT_RGB24,
                                       SWS_FAST_BILINEAR,
                                       NULL, NULL, NULL);
    
    return _swsContext != NULL;
}

#pragma mark - 关闭文件相关操作
- (void)closeFile {
    [self closeAudioStream];
    [self closeVideoStream];
    [self closeSubtitleStream];
    
    _videoStreams = nil;
    _audioStreams = nil;
    _subtitleStreams = nil;
    
    if (_formatCtx) {
        _formatCtx->interrupt_callback.opaque = NULL;
        _formatCtx->interrupt_callback.callback = NULL;
        avformat_close_input(&_formatCtx);
        _formatCtx = NULL;
    }
}

- (void) closeVideoStream
{
    _videoStream = -1;
    
    [self closeScaler];
    
    if (_videoFrame) {
        
        av_free(_videoFrame);
        _videoFrame = NULL;
    }
    
    if (_videoCodecCtx) {
        
        avcodec_close(_videoCodecCtx);
        _videoCodecCtx = NULL;
    }
}

- (void) closeAudioStream
{
    _audioStream = -1;
    
    if (_swrBuffer) {
        
        free(_swrBuffer);
        _swrBuffer = NULL;
        _swrBufferSize = 0;
    }
    
    if (_swrContext) {
        
        swr_free(&_swrContext);
        _swrContext = NULL;
    }
    
    if (_audioFrame) {
        
        av_free(_audioFrame);
        _audioFrame = NULL;
    }
    
    if (_audioCodecCtx) {
        
        avcodec_close(_audioCodecCtx);
        _audioCodecCtx = NULL;
    }
}

- (void) closeSubtitleStream
{
    _subtitleStream = -1;
    
    if (_subtitleCodecCtx) {
        
        avcodec_close(_subtitleCodecCtx);
        _subtitleCodecCtx = NULL;
    }
}

- (void) closeScaler
{
    if (_swsContext) {
        sws_freeContext(_swsContext);
        _swsContext = NULL;
    }
    
    if (_pictureValid) {
        avpicture_free(&_picture);
        _pictureValid = NO;
    }
}

- (BOOL)setupVideoFrameFormat:(KVPlayerVideoFrameFormat)format {
    if (format == KVPlayerVideoFrameFormatYUV &&
        _videoCodecCtx &&
        (_videoCodecCtx->pix_fmt == AV_PIX_FMT_YUV420P || _videoCodecCtx->pix_fmt == AV_PIX_FMT_YUVJ420P)) {
        _videoFrameFormat = KVPlayerVideoFrameFormatYUV;
        return YES;
    }else {
        _videoFrameFormat = KVPlayerVideoFrameFormatRGB;
    }
    return _videoFrameFormat == format;
}

#pragma mark - 解析数据
- (NSArray*)decodeFrames:(NSInteger)frameCount newFps:(CGFloat *)newFps {
    if (_videoStream == -1 &&
        _audioStream == -1) {
        return nil;
    }
    if (!_newFps) {
        AVStream *st = _formatCtx->streams[_videoStream];
        _newFps = av_q2d(st->r_frame_rate);
        if (newFps) {
            *newFps = _newFps;
        }
    }
    
    NSMutableArray *result = [NSMutableArray array];
    AVPacket packet;
    CGFloat decodedCount = 0;
    BOOL finished = NO;
    while (!finished) {
        if (self.isFinish) {
            return nil;
        }
        int flag = av_read_frame(_formatCtx, &packet);
        if (flag < 0) {
            if (_position < self.duration - 20) {
                if (self.endFlagCount >= 400) {
                    self.isEOF = YES;
                    self.endFlagCount = 0;
                    break;
                }else {
                    self.endFlagCount++;
                    continue;
                }
            }else {
                self.isEOF = YES;
                self.endFlagCount = 0;
                break;
            }
        }
        self.endFlagCount = 0;
        if (packet.stream_index ==_videoStream) {
            //视频
            int pktSize = packet.size;
            
            while (pktSize > 0) {
                if (self.isFinish) {
                    return nil;
                }
                int gotframe = 0;
                avcodec_receive_frame(_videoCodecCtx, _videoFrame);
                int len = avcodec_decode_video2(_videoCodecCtx,
                                                _videoFrame,
                                                &gotframe,
                                                &packet);
                
                if (len < 0) {
                    break;
                }
                
                if (gotframe) {
                    
                    KVPlayerVideoFrame *frame = [self handleVideoFrame];
                    if (frame) {
                        
                        [result addObject:frame];
                        _position = frame.position;
                        decodedCount += 1;
                        if (decodedCount >= frameCount)
                            finished = YES;
                    }
                }
                
                if (0 == len)
                    break;
                
                pktSize -= len;
            }
        }else if (packet.stream_index == _audioStream) {
            //音频
            int pktSize = packet.size;
            while (pktSize > 0) {
                if (self.isFinish) {
                    return nil;
                }
                int gotframe = 0;
                int len = avcodec_decode_audio4(_audioCodecCtx,
                                                _audioFrame,
                                                &gotframe,
                                                &packet);
                
                if (len < 0) {
                    break;
                }
                
                if (gotframe) {
                    
                    KVPlayerAudioFrame * frame = [self handleAudioFrame];
                    if (frame) {

                        [result addObject:frame];

                        if (_videoStream == -1) {
                            _position = frame.position;
                            decodedCount += 1;
                            if (decodedCount >= frameCount)
                                finished = YES;
                        }
                    }
                }
                
                if (0 == len)
                    break;
                
                pktSize -= len;
            }
        }else if (packet.stream_index == _subtitleStream) {
            //字幕
            int pktSize = packet.size;

            while (pktSize > 0) {

                AVSubtitle subtitle;
                int gotsubtitle = 0;
                int len = avcodec_decode_subtitle2(_subtitleCodecCtx,
                                                   &subtitle,
                                                   &gotsubtitle,
                                                   &packet);

                if (len < 0) {
                    break;
                }

                if (gotsubtitle) {

                    KVPlayerSubtitleFrame *frame = [self handleSubtitle: &subtitle];
                    if (frame) {
                        [result addObject:frame];
                    }
                    avsubtitle_free(&subtitle);
                }

                if (0 == len)
                    break;

                pktSize -= len;
            }
        }
        
        av_free_packet(&packet);
    }
    return result;
}

- (NSArray*)decodeFramesByDuration:(CGFloat)duration {
    if (_videoStream == -1 &&
        _audioStream == -1) {
        return nil;
    }
    NSMutableArray *result = [NSMutableArray array];
    AVPacket packet;
    CGFloat decodedDuration = 0;
    BOOL finished = NO;
    while (!finished) {
        if (self.isFinish) {
            return nil;
        }
        if (av_read_frame(_formatCtx, &packet) < 0) {
            if (self.endFlagCount >= 5) {
                self.isEOF = YES;
                break;
            }else {
                self.endFlagCount++;
                continue;
            }
        }
        self.endFlagCount = 0;
        if (packet.stream_index ==_videoStream) {
            //视频
            int pktSize = packet.size;
            
            while (pktSize > 0) {
                if (self.isFinish) {
                    return nil;
                }
                int gotframe = 0;
                int len = avcodec_decode_video2(_videoCodecCtx,
                                                _videoFrame,
                                                &gotframe,
                                                &packet);
                
                if (len < 0) {
                    break;
                }
                
                if (gotframe) {
                    
                    KVPlayerVideoFrame *frame = [self handleVideoFrame];
                    if (frame) {
                        
                        [result addObject:frame];
                        _position = frame.position;
                        decodedDuration += frame.duration;
                        if (decodedDuration > duration)
                            finished = YES;
                    }
                }
                
                if (0 == len)
                    break;
                
                pktSize -= len;
            }
        }else if (packet.stream_index == _audioStream) {
            //音频
            int pktSize = packet.size;
            while (pktSize > 0) {
                if (self.isFinish) {
                    return nil;
                }
                int gotframe = 0;
                int len = avcodec_decode_audio4(_audioCodecCtx,
                                                _audioFrame,
                                                &gotframe,
                                                &packet);
                
                if (len < 0) {
                    break;
                }
                
                if (gotframe) {
                    
                    KVPlayerAudioFrame * frame = [self handleAudioFrame];
                    if (frame) {
                        
                        [result addObject:frame];
                        
                        if (_videoStream == -1) {
                            _position = frame.position;
                            decodedDuration += frame.duration;
                            if (decodedDuration > duration)
                                finished = YES;
                        }
                    }
                }
                
                if (0 == len)
                    break;
                
                pktSize -= len;
            }
        }else if (packet.stream_index == _subtitleStream) {
            //字幕
        }
        
        av_free_packet(&packet);
    }
    return result;
}

#pragma mark - 处理帧数据
//处理视频帧
- (KVPlayerVideoFrame*)handleVideoFrame {
    if (!_videoFrame->data[0] || self.isFinish) {
        return nil;
    }
    KVPlayerVideoFrame * frame = nil;
    if (_videoFrameFormat == KVPlayerVideoFrameFormatYUV) {
        KVPlayerVideoFrameYUV * yuvFrame = [[KVPlayerVideoFrameYUV alloc] init];
        yuvFrame.luma = [self copyFrameData:_videoFrame->data[0] linesize:_videoFrame->linesize[0] width:_videoCodecCtx->width height:_videoCodecCtx->height];
        
        yuvFrame.chromaB = [self copyFrameData:_videoFrame->data[1] linesize:_videoFrame->linesize[1] width:_videoCodecCtx->width / 2 height:_videoCodecCtx->height / 2];
        
        yuvFrame.chromaR = [self copyFrameData:_videoFrame->data[2] linesize:_videoFrame->linesize[2] width:_videoCodecCtx->width / 2 height:_videoCodecCtx->height / 2];
        
        frame = yuvFrame;
    }else {
        if (!_swsContext &&
            ![self setupScaler]) {
            return nil;
        }
        sws_scale(_swsContext,
                  (const uint8_t **)_videoFrame->data,
                  _videoFrame->linesize,
                  0,
                  _videoCodecCtx->height,
                  _picture.data,
                  _picture.linesize);
        
        KVPlayerVideoFrameRGB *rgbFrame = [[KVPlayerVideoFrameRGB alloc] init];
        rgbFrame.linesize = _picture.linesize[0];
        rgbFrame.rgb = [NSData dataWithBytes:_picture.data[0]
                                      length:rgbFrame.linesize * _videoCodecCtx->height];
        frame = rgbFrame;
    }
    frame.width = _videoCodecCtx->width;
    frame.height = _videoCodecCtx->height;
    frame.position = av_frame_get_best_effort_timestamp(_videoFrame) * _videoTimeBase;
    
    const int64_t frameDuration = av_frame_get_pkt_duration(_videoFrame);
    if (frameDuration) {
        frame.duration = frameDuration * _videoTimeBase;
        frame.duration += _videoFrame->repeat_pict * _videoTimeBase * 0.5;
    } else {
        frame.duration = 1.0 / _fps;
    }
    return frame;
}

//处理音频帧
- (KVPlayerAudioFrame*)handleAudioFrame {
    if (!_audioFrame->data[0])
        return nil;
    KVPlayerAudioManager * audioManager = [KVPlayerAudioManager audioManager];
    
    const NSUInteger numChannels = audioManager.numOutputChannels;
    NSInteger numFrames;
    
    void * audioData;
    
    if (_swrContext) {
        const NSUInteger ratio = MAX(1, audioManager.samplingRate / _audioCodecCtx->sample_rate) *
        MAX(1, audioManager.numOutputChannels / _audioCodecCtx->channels) * 2;
        
        const int bufSize = av_samples_get_buffer_size(NULL,
                                                       audioManager.numOutputChannels,
                                                       _audioFrame->nb_samples * ratio,
                                                       AV_SAMPLE_FMT_S16,
                                                       1);
        
        if (!_swrBuffer || _swrBufferSize < bufSize) {
            _swrBufferSize = bufSize;
            _swrBuffer = realloc(_swrBuffer, _swrBufferSize);
        }
        
        Byte *outbuf[2] = { _swrBuffer, 0 };
        
        numFrames = swr_convert(_swrContext,
                                outbuf,
                                _audioFrame->nb_samples * ratio,
                                (const uint8_t **)_audioFrame->data,
                                _audioFrame->nb_samples);
        
        if (numFrames < 0) {
            return nil;
        }
        
        //int64_t delay = swr_get_delay(_swrContext, audioManager.samplingRate);
        //if (delay > 0)
        //    LoggerAudio(0, @"resample delay %lld", delay);
        
        audioData = _swrBuffer;
        
    } else {
        
        if (_audioCodecCtx->sample_fmt != AV_SAMPLE_FMT_S16) {
            return nil;
        }
        
        audioData = _audioFrame->data[0];
        numFrames = _audioFrame->nb_samples;
    }
    
    const NSUInteger numElements = numFrames * numChannels;
    NSMutableData *data = [NSMutableData dataWithLength:numElements * sizeof(float)];
    
    float scale = 1.0 / (float)INT16_MAX ;
    vDSP_vflt16((SInt16 *)audioData, 1, data.mutableBytes, 1, numElements);
    vDSP_vsmul(data.mutableBytes, 1, &scale, data.mutableBytes, 1, numElements);
    
    KVPlayerAudioFrame *frame = [[KVPlayerAudioFrame alloc] init];
    frame.position = av_frame_get_best_effort_timestamp(_audioFrame) * _audioTimeBase;
    frame.duration = av_frame_get_pkt_duration(_audioFrame) * _audioTimeBase;
    frame.samples = data;
    
    if (frame.duration == 0) {
        // sometimes ffmpeg can't determine the duration of audio frame
        // especially of wma/wmv format
        // so in this case must compute duration
        frame.duration = frame.samples.length / (sizeof(float) * numChannels * audioManager.samplingRate);
    }
    return frame;
}
    
//处理字幕帧
- (KVPlayerSubtitleFrame *) handleSubtitle: (AVSubtitle *)pSubtitle
{
    NSMutableString *ms = [NSMutableString string];
    
    for (NSUInteger i = 0; i < pSubtitle->num_rects; ++i) {
        
        AVSubtitleRect *rect = pSubtitle->rects[i];
        if (rect) {
            
            if (rect->text) { // rect->type == SUBTITLE_TEXT
                
                NSString *s = [NSString stringWithUTF8String:rect->text];
                if (s.length) [ms appendString:s];
                
            } else if (rect->ass && _subtitleASSEvents != -1) {
                
                NSString *s = [NSString stringWithUTF8String:rect->ass];
                if (s.length) {
                    
                    NSArray *fields = [self parseDialogue:s numFields:_subtitleASSEvents];
                    if (fields.count && [fields.lastObject length]) {
                        
                        s = [self removeCommandsFromEventText: fields.lastObject];
                        if (s.length) [ms appendString:s];
                    }
                }
            }
        }
    }
    
    if (!ms.length)
        return nil;
    
    KVPlayerSubtitleFrame *frame = [[KVPlayerSubtitleFrame alloc] init];
    frame.text = [ms copy];
    frame.position = pSubtitle->pts / AV_TIME_BASE + pSubtitle->start_display_time;
    frame.duration = (CGFloat)(pSubtitle->end_display_time - pSubtitle->start_display_time) / 1000.f;
    return frame;
}

- (NSArray *) parseDialogue: (NSString *) dialogue
                  numFields: (NSUInteger) numFields
{
    if ([dialogue hasPrefix:@"Dialogue:"]) {
        
        NSMutableArray *ma = [NSMutableArray array];
        
        NSRange r = {@"Dialogue:".length, 0};
        NSUInteger n = 0;
        
        while (r.location != NSNotFound && n++ < numFields) {
            
            const NSUInteger pos = r.location + r.length;
            
            r = [dialogue rangeOfString:@","
                                options:0
                                  range:NSMakeRange(pos, dialogue.length - pos)];
            
            const NSUInteger len = r.location == NSNotFound ? dialogue.length - pos : r.location - pos;
            NSString *p = [dialogue substringWithRange:NSMakeRange(pos, len)];
            p = [p stringByReplacingOccurrencesOfString:@"\\N" withString:@"\n"];
            [ma addObject: p];
        }
        
        return ma;
    }
    
    return nil;
}

- (NSString *) removeCommandsFromEventText: (NSString *) text
{
    NSMutableString *ms = [NSMutableString string];
    
    NSScanner *scanner = [NSScanner scannerWithString:text];
    while (!scanner.isAtEnd) {
        
        NSString *s;
        if ([scanner scanUpToString:@"{\\" intoString:&s]) {
            
            [ms appendString:s];
        }
        
        if (!([scanner scanString:@"{\\" intoString:nil] &&
              [scanner scanUpToString:@"}" intoString:nil] &&
              [scanner scanString:@"}" intoString:nil])) {
            
            break;
        }
    }
    
    return ms;
}

- (BOOL)interruptDecoder
{
    if (_interruptCallback)
        return _interruptCallback();
    return NO;
}

#pragma mark - 收集流
- (NSArray*)collectStreams:(AVFormatContext*)formatCtx type:(enum AVMediaType)codecType {
    NSMutableArray *ma = [NSMutableArray array];
    for (NSInteger i = 0; i < formatCtx->nb_streams; ++i)
        if (codecType == formatCtx->streams[i]->codec->codec_type)
            [ma addObject: [NSNumber numberWithInteger: i]];
    return [ma copy];
}

//拷贝数据，转成NSData
- (NSData*)copyFrameData:(UInt8*)src linesize:(int)linesize width:(int)width height:(int)height {
    width = MIN(linesize, width);
    NSMutableData *md = [NSMutableData dataWithLength: width * height];
    Byte *dst = md.mutableBytes;
    for (NSUInteger i = 0; i < height; ++i) {
        memcpy(dst, src, width);
        dst += width;
        src += linesize;
    }
    return md;
}

- (void)sendError:(KVPlayerDecoderErrorCode)code msg:(NSString*)msg {
    if ([self.delegate respondsToSelector:@selector(decoder:errorWithCode:msg:)]) {
        [self.delegate decoder:self errorWithCode:code msg:msg];
    }
}

#pragma mark - setter
- (void)setPosition:(CGFloat)seconds {
    _position = seconds;
    _isEOF = NO;
    
    if (_videoStream != -1) {
        int64_t ts = (int64_t)(seconds / _videoTimeBase);
        avformat_seek_file(_formatCtx, (int)_videoStream, ts, ts, ts, AVSEEK_FLAG_FRAME);
        avcodec_flush_buffers(_videoCodecCtx);
    }
    
    if (_audioStream != -1) {
        int64_t ts = (int64_t)(seconds / _audioTimeBase);
        avformat_seek_file(_formatCtx, (int)_audioStream, ts, ts, ts, AVSEEK_FLAG_FRAME);
        avcodec_flush_buffers(_audioCodecCtx);
    }
}
//选择音轨
- (void)setSelectedAudioStream:(NSInteger)selectedAudioStream {
    if (selectedAudioStream < 0) {
        return;
    }
    if (selectedAudioStream >= _audioStreams.count) {
        return;
    }
    NSInteger audioStream = [_audioStreams[selectedAudioStream] integerValue];
    [self closeAudioStream];
    [self openAudioStream:audioStream];
}

- (void)setSelectedSubtitleStream:(NSInteger)selected {
    [self closeSubtitleStream];
    if (selected == -1) {
        _subtitleStream = -1;
    } else {
        //        NSInteger subtitleStream = [_subtitleStreams[selected] integerValue];
        //        [self openSubtitleStream:subtitleStream];
    }
}

#pragma mark - getter
- (BOOL)validVideo {
    return _videoStream != -1;
}

- (BOOL)validAudio {
    return _audioStream != -1;
}

- (CGFloat)duration {
    if (!_formatCtx)
        return 0;
    if (_formatCtx->duration == AV_NOPTS_VALUE)
        return MAXFLOAT;
    return (CGFloat)_formatCtx->duration / AV_TIME_BASE;
}

- (NSUInteger)frameWidth {
    return _videoCodecCtx ? _videoCodecCtx->width : 0;
}

- (NSUInteger)frameHeight {
    return _videoCodecCtx ? _videoCodecCtx->height : 0;
}

- (CGFloat)sampleRate {
    return _audioCodecCtx ? _audioCodecCtx->sample_rate : 0;
}

- (NSUInteger)audioStreamsCount {
    return [_audioStreams count];
}

- (NSUInteger)subtitleStreamsCount {
    return [_subtitleStreams count];
}

- (NSInteger)selectedAudioStream {
    if (_audioStream == -1)
        return -1;
    NSNumber *n = [NSNumber numberWithInteger:_audioStream];
    return [_audioStreams indexOfObject:n];
}

- (NSInteger)selectedSubtitleStream {
    if (_subtitleStream == -1)
        return -1;
    return [_subtitleStreams indexOfObject:@(_subtitleStream)];
}

- (NSDictionary*)info {
    if (!_info) {
        
        NSMutableDictionary *md = [NSMutableDictionary dictionary];
        
        if (_formatCtx) {
            
            const char *formatName = _formatCtx->iformat->name;
            [md setValue: [NSString stringWithCString:formatName encoding:NSUTF8StringEncoding]
                  forKey: @"format"];
            
            if (_formatCtx->bit_rate) {
                
                [md setValue: [NSNumber numberWithInt:(int)_formatCtx->bit_rate]
                      forKey: @"bitrate"];
            }
            
            if (_formatCtx->metadata) {
                
                NSMutableDictionary *md1 = [NSMutableDictionary dictionary];
                
                AVDictionaryEntry *tag = NULL;
                while((tag = av_dict_get(_formatCtx->metadata, "", tag, AV_DICT_IGNORE_SUFFIX))) {
                    
                    [md1 setValue: [NSString stringWithCString:tag->value encoding:NSUTF8StringEncoding]
                           forKey: [NSString stringWithCString:tag->key encoding:NSUTF8StringEncoding]];
                }
                
                [md setValue: [md1 copy] forKey: @"metadata"];
            }
            
            char buf[256];
            
            if (_videoStreams.count) {
                NSMutableArray *ma = [NSMutableArray array];
                for (NSNumber *n in _videoStreams) {
                    AVStream *st = _formatCtx->streams[n.integerValue];
                    avcodec_string(buf, sizeof(buf), st->codec, 1);
                    NSString *s = [NSString stringWithCString:buf encoding:NSUTF8StringEncoding];
                    if ([s hasPrefix:@"Video: "])
                        s = [s substringFromIndex:@"Video: ".length];
                    [ma addObject:s];
                }
                md[@"video"] = ma.copy;
            }
            
            if (_audioStreams.count) {
                NSMutableArray *ma = [NSMutableArray array];
                for (NSNumber *n in _audioStreams) {
                    AVStream *st = _formatCtx->streams[n.integerValue];
                    
                    NSMutableString *ms = [NSMutableString string];
                    AVDictionaryEntry *lang = av_dict_get(st->metadata, "language", NULL, 0);
                    if (lang && lang->value) {
                        [ms appendFormat:@"language %s ", lang->value];
                    }
                    
                    avcodec_string(buf, sizeof(buf), st->codec, 1);
                    NSString *s = [NSString stringWithCString:buf encoding:NSUTF8StringEncoding];
                    if ([s hasPrefix:@"Audio: "])
                        s = [s substringFromIndex:@"Audio: ".length];
                    [ms appendString:s];
                    
                    [ma addObject:ms.copy];
                }
                md[@"audio"] = ma.copy;
            }
            
            if (_subtitleStreams.count) {
                NSMutableArray *ma = [NSMutableArray array];
                for (NSNumber *n in _subtitleStreams) {
                    AVStream *st = _formatCtx->streams[n.integerValue];
                    
                    NSMutableString *ms = [NSMutableString string];
                    AVDictionaryEntry *lang = av_dict_get(st->metadata, "language", NULL, 0);
                    if (lang && lang->value) {
                        [ms appendFormat:@"%s ", lang->value];
                    }
                    
                    avcodec_string(buf, sizeof(buf), st->codec, 1);
                    NSString *s = [NSString stringWithCString:buf encoding:NSUTF8StringEncoding];
                    if ([s hasPrefix:@"Subtitle: "])
                        s = [s substringFromIndex:@"Subtitle: ".length];
                    [ms appendString:s];
                    
                    [ma addObject:ms.copy];
                }
                md[@"subtitles"] = ma.copy;
            }
            
        }
        
        _info = [md copy];
    }
    
    return _info;
}

- (NSString*)videoStreamFormatName {
    if (!_videoCodecCtx)
        return nil;
    
    if (_videoCodecCtx->pix_fmt == AV_PIX_FMT_NONE)
        return @"";
    
    const char *name = av_get_pix_fmt_name(_videoCodecCtx->pix_fmt);
    return name ? [NSString stringWithCString:name encoding:NSUTF8StringEncoding] : @"?";
}

- (void)dealloc {
    [self closeFile];
}

@end

static int interrupt_callback(void *ctx)
{
    if (!ctx)
        return 0;
    __unsafe_unretained KVPlayerDecoder *p = (__bridge KVPlayerDecoder *)ctx;
    const BOOL r = [p interruptDecoder];
    if (r) {
        
    };
    return r;
}

static void KVPlayerLog(void* context, int level, const char* format, va_list args) {
}
