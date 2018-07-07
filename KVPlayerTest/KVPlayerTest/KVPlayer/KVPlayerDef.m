//
//  KVPlayerBase.m
//  KVPlayer
//
//  Created by kevin on 2018/4/24.
//  Copyright © 2018年 kv. All rights reserved.
//

#import "KVPlayerDef.h"

@implementation KVPlayerBaseFrame
@end

@implementation KVPlayerAudioFrame
- (KVPlayerFrameType)type {
    return KVPlayerFrameTypeAudio;
}

@end

@implementation KVPlayerVideoFrame
- (KVPlayerFrameType)type {
    return KVPlayerFrameTypeVideo;
}
@end

@implementation KVPlayerVideoFrameRGB

- (KVPlayerVideoFrameFormat)format {
    return KVPlayerVideoFrameFormatRGB;
}

- (UIImage*)asImage {
    UIImage *image = nil;
    CGDataProviderRef provider = CGDataProviderCreateWithCFData((__bridge CFDataRef)(_rgb));
    if (provider) {
        CGColorSpaceRef colorSpace = CGColorSpaceCreateDeviceRGB();
        if (colorSpace) {
            CGImageRef imageRef = CGImageCreate(self.width, self.height, 8, 24, self.linesize, colorSpace, kCGBitmapByteOrderDefault, provider, NULL, YES, kCGRenderingIntentDefault);
            if (imageRef) {
                image = [UIImage imageWithCGImage:imageRef];
                CGImageRelease(imageRef);
            }
            CGColorSpaceRelease(colorSpace);
        }
        CGDataProviderRelease(provider);
    }
    return image;
}

@end

@implementation KVPlayerVideoFrameYUV

- (KVPlayerVideoFrameFormat)format {
    return KVPlayerVideoFrameFormatYUV;
}

@end

@implementation KVPlayerArtworkFrame

- (KVPlayerFrameType)type {
    return KVPlayerFrameTypeArtwork;
}

- (UIImage*)asImage {
    UIImage *image = nil;
    CGDataProviderRef provider = CGDataProviderCreateWithCFData((__bridge CFDataRef)(_picture));
    if (provider) {
        CGImageRef imageRef = CGImageCreateWithJPEGDataProvider(provider, NULL, YES, kCGRenderingIntentDefault);
        if (imageRef) {
            image = [UIImage imageWithCGImage:imageRef];
            CGImageRelease(imageRef);
        }
        CGDataProviderRelease(provider);
    }
    return image;
}

@end

@implementation KVPlayerSubtitleFrame
- (KVPlayerFrameType)type {
    return KVPlayerFrameTypeSubtitle;
}
@end
