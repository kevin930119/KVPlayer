//
//  KVPlayerAudioManager.m
//  KVPlayer
//
//  Created by kevin on 2018/4/25.
//  Copyright © 2018年 kv. All rights reserved.
//

#import "KVPlayerAudioManager.h"
#import <AVFoundation/AVFoundation.h>
#import <Accelerate/Accelerate.h>

#define MAX_FRAME_SIZE 4096
#define MAX_CHAN       2

#define MAX_SAMPLE_DUMPED 5

static BOOL checkError(OSStatus error);
static void sessionPropertyListener(void *inClientData, AudioSessionPropertyID inID, UInt32 inDataSize, const void *inData);
static void sessionInterruptionListener(void *inClientData, UInt32 inInterruption);
static OSStatus renderCallback (void *inRefCon, AudioUnitRenderActionFlags    *ioActionFlags, const AudioTimeStamp * inTimeStamp, UInt32 inOutputBusNumber, UInt32 inNumberFrames, AudioBufferList* ioData);

@interface KVPlayerAudioManager ()

@property (readwrite, assign) UInt32 numBytesPerSample;
@property (readwrite, assign) Float32 outputVolume;
@property (readwrite, assign) BOOL playing;
@property (readwrite, strong) NSString * audioRoute;
@property (nonatomic, assign) BOOL playAfterSessionEndInterruption;

@end

@implementation KVPlayerAudioManager
{
    BOOL _initialized;
    BOOL _activated;
    float * _outData;
    AudioUnit _audioUnit;
    AudioStreamBasicDescription _outputFormat;
}

+ (instancetype)audioManager {
    static KVPlayerAudioManager * kvplayeraudiomanager = nil;
    static dispatch_once_t kvplayeraudiomanagertoken;
    dispatch_once(&kvplayeraudiomanagertoken, ^{
        kvplayeraudiomanager = [[KVPlayerAudioManager alloc] init];
    });
    return kvplayeraudiomanager;
}

- (instancetype)init {
    if (self = [super init]) {
        _outData = (float *)calloc(MAX_FRAME_SIZE*MAX_CHAN, sizeof(float));
        _outputVolume = 0.5;
    }
    return self;
}

- (AudioStreamBasicDescription)getFormat {
    return _outputFormat;
}

- (BOOL) checkAudioRoute {
    UInt32 propertySize = sizeof(CFStringRef);
    CFStringRef route;
    if (checkError(AudioSessionGetProperty(kAudioSessionProperty_AudioRoute,
                                           &propertySize,
                                           &route))) {
        return NO;
    }
    _audioRoute = CFBridgingRelease(route);
    return YES;
}

- (BOOL) setupAudio
{
    // --- Audio Session Setup ---
    
    UInt32 sessionCategory = kAudioSessionCategory_MediaPlayback;
    //UInt32 sessionCategory = kAudioSessionCategory_PlayAndRecord;
    if (checkError(AudioSessionSetProperty(kAudioSessionProperty_AudioCategory,
                                           sizeof(sessionCategory),
                                           &sessionCategory)))
        return NO;
    
    
//    if (checkError(AudioSessionAddPropertyListener(kAudioSessionProperty_AudioRouteChange,
//                                                   sessionPropertyListener,
//                                                   (__bridge void *)(self))))
//    {
//        // just warning
//    }
    
    if (checkError(AudioSessionAddPropertyListener(kAudioSessionProperty_CurrentHardwareOutputVolume,
                                                   sessionPropertyListener,
                                                   (__bridge void *)(self))))
    {
        // just warning
    }
    
    // Set the buffer size, this will affect the number of samples that get rendered every time the audio callback is fired
    // A small number will get you lower latency audio, but will make your processor work harder
    
#if !TARGET_IPHONE_SIMULATOR
    Float32 preferredBufferSize = 0.0232;
    if (checkError(AudioSessionSetProperty(kAudioSessionProperty_PreferredHardwareIOBufferDuration,
                                           sizeof(preferredBufferSize),
                                           &preferredBufferSize))) {
        
        // just warning
    }
#endif
    
    if (checkError(AudioSessionSetActive(YES)))
        return NO;
    
    [self checkSessionProperties];
    
    // ----- Audio Unit Setup -----
    
    // Describe the output unit.
    
    AudioComponentDescription description = {0};
    description.componentType = kAudioUnitType_Output;
    description.componentSubType = kAudioUnitSubType_RemoteIO;
    description.componentManufacturer = kAudioUnitManufacturer_Apple;
    
    // Get component
    AudioComponent component = AudioComponentFindNext(NULL, &description);
    if (checkError(AudioComponentInstanceNew(component, &_audioUnit)))
        return NO;
    
    UInt32 size;
    
    // Check the output stream format
    size = sizeof(AudioStreamBasicDescription);
    if (checkError(AudioUnitGetProperty(_audioUnit,
                                        kAudioUnitProperty_StreamFormat,
                                        kAudioUnitScope_Input,
                                        0,
                                        &_outputFormat,
                                        &size)))
        return NO;
    _outputFormat.mSampleRate = _samplingRate;
    if (checkError(AudioUnitSetProperty(_audioUnit,
                                        kAudioUnitProperty_StreamFormat,
                                        kAudioUnitScope_Input,
                                        0,
                                        &_outputFormat,
                                        size))) {
        
        // just warning
    }
    
    _numBytesPerSample = _outputFormat.mBitsPerChannel / 8;
    _numOutputChannels = _outputFormat.mChannelsPerFrame;
    
    // Slap a render callback on the unit
    AURenderCallbackStruct callbackStruct;
    callbackStruct.inputProc = renderCallback;
    callbackStruct.inputProcRefCon = (__bridge void *)(self);
    if (checkError(AudioUnitSetProperty(_audioUnit,
                                        kAudioUnitProperty_SetRenderCallback,
                                        kAudioUnitScope_Input,
                                        0,
                                        &callbackStruct,
                                        sizeof(callbackStruct))))
        return NO;
    
    if (checkError(AudioUnitInitialize(_audioUnit)))
        return NO;
    
    return YES;
}

- (void)setPlayRate:(CGFloat)playRate {
    UInt32 size = sizeof(AudioStreamBasicDescription);
    _outputFormat.mSampleRate = _samplingRate * playRate;
    if (checkError(AudioUnitSetProperty(_audioUnit,
                                        kAudioUnitProperty_StreamFormat,
                                        kAudioUnitScope_Input,
                                        0,
                                        &_outputFormat,
                                        size))) {
    }
}

- (BOOL) checkSessionProperties
{
    [self checkAudioRoute];
    
    // Check the number of output channels.
    UInt32 newNumChannels;
    UInt32 size = sizeof(newNumChannels);
    if (checkError(AudioSessionGetProperty(kAudioSessionProperty_CurrentHardwareOutputNumberChannels,
                                           &size,
                                           &newNumChannels)))
        return NO;
    
    // Get the hardware sampling rate. This is settable, but here we're only reading.
    size = sizeof(_samplingRate);
    if (checkError(AudioSessionGetProperty(kAudioSessionProperty_CurrentHardwareSampleRate,
                                           &size,
                                           &_samplingRate)))
        
        return NO;
    
    size = sizeof(_outputVolume);
    if (checkError(AudioSessionGetProperty(kAudioSessionProperty_CurrentHardwareOutputVolume,
                                           &size,
                                           &_outputVolume)))
        return NO;
    
    return YES;
}

- (BOOL) renderFrames: (UInt32) numFrames
               ioData: (AudioBufferList *) ioData
{
    for (int iBuffer=0; iBuffer < ioData->mNumberBuffers; ++iBuffer) {
        memset(ioData->mBuffers[iBuffer].mData, 0, ioData->mBuffers[iBuffer].mDataByteSize);
    }
    
    if (_playing && _outputBlock ) {
        
        // Collect data to render from the callbacks
        _outputBlock(_outData, numFrames, _numOutputChannels);
        
        // Put the rendered data into the output buffer
        if (_numBytesPerSample == 4) // then we've already got floats
        {
            float zero = 0.0;
            
            for (int iBuffer=0; iBuffer < ioData->mNumberBuffers; ++iBuffer) {
                
                int thisNumChannels = ioData->mBuffers[iBuffer].mNumberChannels;
                
                for (int iChannel = 0; iChannel < thisNumChannels; ++iChannel) {
                    vDSP_vsadd(_outData+iChannel, _numOutputChannels, &zero, (float *)ioData->mBuffers[iBuffer].mData, thisNumChannels, numFrames);
                }
            }
        }
        else if (_numBytesPerSample == 2) // then we need to convert SInt16 -> Float (and also scale)
        {
            float scale = (float)INT16_MAX;
            vDSP_vsmul(_outData, 1, &scale, _outData, 1, numFrames*_numOutputChannels);
            
            for (int iBuffer=0; iBuffer < ioData->mNumberBuffers; ++iBuffer) {
                
                int thisNumChannels = ioData->mBuffers[iBuffer].mNumberChannels;
                
                for (int iChannel = 0; iChannel < thisNumChannels; ++iChannel) {
                    vDSP_vfix16(_outData+iChannel, _numOutputChannels, (SInt16 *)ioData->mBuffers[iBuffer].mData+iChannel, thisNumChannels, numFrames);
                }
            }
            
        }
    }
    
    return noErr;
}

- (BOOL) activateAudioSession
{
    if (!_activated) {
        
        if (!_initialized) {
            
            if (checkError(AudioSessionInitialize(NULL,
                                                  kCFRunLoopDefaultMode,
                                                  sessionInterruptionListener,
                                                  (__bridge void *)(self))))
                return NO;
            
            _initialized = YES;
        }
        
        if ([self checkAudioRoute] &&
            [self setupAudio]) {
            
            _activated = YES;
        }
    }
    
    return _activated;
}

- (void) deactivateAudioSession
{
    if (_activated) {
        
        [self pause];
        
        checkError(AudioUnitUninitialize(_audioUnit));
        
        /*
         fails with error (-10851) ?
         
         checkError(AudioUnitSetProperty(_audioUnit,
         kAudioUnitProperty_SetRenderCallback,
         kAudioUnitScope_Input,
         0,
         NULL,
         0),
         "Couldn't clear the render callback on the audio unit");
         */
        
        checkError(AudioComponentInstanceDispose(_audioUnit));
        
        checkError(AudioSessionSetActive(NO));
        
//        checkError(AudioSessionRemovePropertyListenerWithUserData(kAudioSessionProperty_AudioRouteChange,
//                                                                  sessionPropertyListener,
//                                                                  (__bridge void *)(self)));
        
        checkError(AudioSessionRemovePropertyListenerWithUserData(kAudioSessionProperty_CurrentHardwareOutputVolume,
                                                                  sessionPropertyListener,
                                                                  (__bridge void *)(self)));
        
        _activated = NO;
    }
}

- (void) pause
{
    if (_playing) {
        
        _playing = checkError(AudioOutputUnitStop(_audioUnit));
    }
}

- (BOOL) play
{
    if (!_playing) {
        
        if ([self activateAudioSession]) {
            
            _playing = !checkError(AudioOutputUnitStart(_audioUnit));
        }
    }
    
    return _playing;
}

- (void)dealloc {
    if (_outData) {
        free(_outData);
        _outData = NULL;
    }
}

@end

static void sessionPropertyListener(void *                  inClientData,
                                    AudioSessionPropertyID  inID,
                                    UInt32                  inDataSize,
                                    const void *            inData)
{
    KVPlayerAudioManager *am = (__bridge KVPlayerAudioManager *)inClientData;
    
    if (inID == kAudioSessionProperty_AudioRouteChange) {
        
//        if ([am checkAudioRoute]) {
//            [am checkSessionProperties];
//        }
    } else if (inID == kAudioSessionProperty_CurrentHardwareOutputVolume) {
        
        if (inData && inDataSize == 4) {
            
            am.outputVolume = *(float *)inData;
        }
    }
}

static void sessionInterruptionListener(void *inClientData, UInt32 inInterruption)
{
    KVPlayerAudioManager *am = (__bridge KVPlayerAudioManager *)inClientData;
    
    if (inInterruption == kAudioSessionBeginInterruption) {
        
        am.playAfterSessionEndInterruption = am.playing;
        [am pause];
        
    } else if (inInterruption == kAudioSessionEndInterruption) {
        if (am.playAfterSessionEndInterruption) {
            am.playAfterSessionEndInterruption = NO;
            [am play];
        }
    }
}

static OSStatus renderCallback (void                        *inRefCon,
                                AudioUnitRenderActionFlags    * ioActionFlags,
                                const AudioTimeStamp         * inTimeStamp,
                                UInt32                        inOutputBusNumber,
                                UInt32                        inNumberFrames,
                                AudioBufferList                * ioData)
{
    KVPlayerAudioManager *am = (__bridge KVPlayerAudioManager *)inRefCon;
    return [am renderFrames:inNumberFrames ioData:ioData];
}

static BOOL checkError(OSStatus error)
{
    if (error == noErr) {
        return NO;
    }
    return YES;
}
