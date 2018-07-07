//
//  ViewController.m
//  KVPlayerTest
//
//  Created by 魏佳林 on 2018/7/7.
//  Copyright © 2018年 魏佳林. All rights reserved.
//

#import "ViewController.h"
#import "KVPlayer.h"
#import "Masonry.h"

@interface ViewController () <KVPlayerDelegate>

@property (nonatomic, strong) KVPlayer * player;

@property (nonatomic, strong) UISlider * slider;
@property (nonatomic, strong) UILabel * currentDurationLabel;
@property (nonatomic, strong) UILabel * totalDurationLabel;
@property (nonatomic, strong) UIButton * playBtn;

@property (nonatomic, assign) BOOL isTouchDown;

@end

@implementation ViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    // Do any additional setup after loading the view, typically from a nib.
    self.view.backgroundColor = [UIColor whiteColor];
    self.player = [[KVPlayer alloc] init];
    self.player.delegate = self;
    [self.view addSubview:self.player.playView];
    [self.player.playView mas_makeConstraints:^(MASConstraintMaker *make) {
        make.width.equalTo(self.view);
        make.height.mas_equalTo(200);
        make.centerX.equalTo(self.view);
        make.top.mas_equalTo(20);
    }];
    
    NSString * filepath = [[NSBundle mainBundle] pathForResource:@"test" ofType:@"mp4"];
    filepath = [NSString stringWithFormat:@"file://%@", filepath];
    BOOL flag = [self.player resetFile:filepath position:0];
    if (flag) {
        NSLog(@"打开文件成功");
        [self setupui];
    }else {
        NSLog(@"不支持该文件");
    }
    //其他操作
//    self.player.playRate = 1.5; //倍速播放
    
//    self.player.screenMode = KVPlayerScreenOneToOne;    //屏幕模式
    
//    UIImage * snapshot = [self.player snapshot];    //截图
    
//    self.player.selectAudioTrackIndex = (self.player.selectAudioTrackIndex + 1) % self.player.audioTrackCount;  //选择音轨
    
//    //字幕操作，这里的字幕为内嵌字幕，非外挂字幕
//    if (self.player.validSubTitle) {
//        self.player.subTitleHidden = YES;   //显示隐藏字幕
//        self.player.subTitleFontSize = 14;  //字幕大小
//        self.player.subTitleTextColor = [UIColor blackColor];   //字幕颜色
//    }
}

- (void)playBtnClick:(UIButton*)btn {
    if (btn.selected) {
        [self.player pause];
    }else {
        [self.player play];
    }
}

- (void)touchUp:(UISlider*)slider {
    self.isTouchDown = NO;
    self.player.position = slider.value;
}

- (void)touchDown:(UISlider*)slider {
    self.isTouchDown = YES;
}

#pragma mark - 代理
- (void)player:(KVPlayer *)player playStateChange:(KVPlayerPlayState)state {
    switch (state) {
        case KVPlayerPlayStateIdle:
            self.playBtn.selected = NO;
            NSLog(@"初始状态");
            break;
        case KVPlayerPlayStatePlaying:
            self.playBtn.selected = YES;
            NSLog(@"播放中");
            break;
        case KVPlayerPlayStatePause:
            self.playBtn.selected = NO;
            NSLog(@"暂停");
            break;
        case KVPlayerPlayStateStop:
            self.playBtn.selected = NO;
            NSLog(@"停止");
            break;
        case KVPlayerPlayStateFinish:
            NSLog(@"完成");
            self.playBtn.selected = NO;
            break;
        case KVPlayerPlayStateLoading:
            NSLog(@"缓冲中");
            break;
        default:
            break;
    }
}

- (void)player:(KVPlayer *)player playAtTime:(float)location {
    if (!self.isTouchDown) {
        self.slider.value = location;
    }
    self.currentDurationLabel.text = [NSString stringWithFormat:@"%02ld:%02ld:%02ld", ((NSInteger)location) / 3600, ((NSInteger)location) % 3600 / 60, ((NSInteger)location) % 60];
}

- (void)player:(KVPlayer *)player fpsChanged:(int)fps {
    
}

- (void)player:(KVPlayer *)player didFailWithMsg:(NSString *)msg {
    
}

- (void)setupui {
    self.playBtn = [UIButton new];
    [self.playBtn setTitle:@"播放" forState:UIControlStateNormal];
    [self.playBtn setTitle:@"暂停" forState:UIControlStateSelected];
    [self.playBtn addTarget:self action:@selector(playBtnClick:) forControlEvents:UIControlEventTouchUpInside];
    [self.playBtn setTitleColor:[UIColor blackColor] forState:UIControlStateNormal];
    self.playBtn.layer.borderColor = [UIColor blackColor].CGColor;
    self.playBtn.layer.borderWidth = 1;
    [self.view addSubview:self.playBtn];
    [self.playBtn mas_makeConstraints:^(MASConstraintMaker *make) {
        make.size.mas_equalTo(CGSizeMake(80, 40));
        make.bottom.equalTo(self.view).offset(-20);
        make.centerX.equalTo(self.view);
    }];
    
    self.slider = [UISlider new];
    [self.slider addTarget:self action:@selector(touchUp:) forControlEvents:UIControlEventTouchUpInside];
    [self.slider addTarget:self action:@selector(touchUp:) forControlEvents:UIControlEventTouchUpOutside];
    [self.slider addTarget:self action:@selector(touchDown:) forControlEvents:UIControlEventTouchDown];
    self.slider.maximumValue = self.player.duration;
    self.slider.value = 0;
    [self.view addSubview:self.slider];
    [self.slider mas_makeConstraints:^(MASConstraintMaker *make) {
        make.width.left.equalTo(self.view);
        make.bottom.equalTo(self.playBtn.mas_top).offset(-10);
        make.height.mas_equalTo(40);
    }];
    
    self.totalDurationLabel = [UILabel new];
    self.totalDurationLabel.font = [UIFont systemFontOfSize:14];
    self.totalDurationLabel.textColor = [UIColor blackColor];
    self.totalDurationLabel.text = [NSString stringWithFormat:@"%02ld:%02ld:%02ld", ((NSInteger)self.player.duration) / 3600, ((NSInteger)self.player.duration) % 3600 / 60, ((NSInteger)self.player.duration) % 60];
    [self.view addSubview:self.totalDurationLabel];
    [self.totalDurationLabel mas_makeConstraints:^(MASConstraintMaker *make) {
        make.centerY.equalTo(self.playBtn);
        make.right.equalTo(self.view).offset(-15);
    }];
    
    self.currentDurationLabel = [UILabel new];
    self.currentDurationLabel.font = [UIFont systemFontOfSize:14];
    self.currentDurationLabel.textColor = [UIColor blackColor];
    self.currentDurationLabel.text = @"00:00:00";
    [self.view addSubview:self.currentDurationLabel];
    [self.currentDurationLabel mas_makeConstraints:^(MASConstraintMaker *make) {
        make.centerY.equalTo(self.playBtn);
        make.left.equalTo(self.view).offset(15);
    }];
}

- (void)dealloc {
    //适当的时机释放播放器
    [self.player releasePlayer];
    self.player = nil;
}


@end
