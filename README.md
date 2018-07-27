&emsp;&emsp;[KVPlayer](https://github.com/kevin930119/KVPlayer.git)是一个基于跨平台视频解析框架*FFmpeg*的开源的多格式本地视频播放器，API简单易用，具备以下功能：

- 支持大部分视频格式（avi,mp4,wav,mkv......）；
- 支持多音轨选择（语言切换，仅针对拥有部分双语音轨的视频，一般后缀名为mkv）；
- 支持0~2倍速度播放；
- 支持内嵌字幕（非外挂字幕）；
- 支持实时截图。

&emsp;&emsp;这篇文章仅介绍KVPlayer的使用，不涉及FFmpeg的解析说明，可能以后有时间会专门写一篇文章介绍FFmpeg，有兴趣的童鞋可以通过KVPlayer的源码进行FFmpeg的学习，FFmpeg为一套纯C接口实现的框架，对于底层理解要求比较高。

# 1 集成准备
&emsp;&emsp;[GitHub地址](https://github.com/kevin930119/KVPlayer.git)
## 1.1 项目配置

1. 在**Other Linker Flags**增加-Objc；

2.在**Header Search Paths**增加FFmpeg的头文件路径
```
 ./KVPlayer/FFmpeg-iOS/include
//.代表项目路径，请参考demo配置
```

## 1.2 添加依赖系统库
![依赖系统库](https://upload-images.jianshu.io/upload_images/1711666-a2970e2a0b4b524a.png?imageMogr2/auto-orient/strip%7CimageView2/2/w/1240)

# 2 开始使用
&emsp;&emsp;Demo展示了基本的使用方法，具体说明和注意事项已经在KVPlayer的头文件中交代得比较清楚，最近工作比较忙，原谅我不想说太多话。

- 初始化
```
self.player = [[KVPlayer alloc] init];
self.player.delegate = self;
[self.view addSubview:self.player.playView];  //视频画面输出在这个视图，请选择合适位置添加
[self.player.playView mas_makeConstraints:^(MASConstraintMaker *make) {
        make.width.equalTo(self.view);
        make.height.mas_equalTo(200);
        make.centerX.equalTo(self.view);
        make.top.mas_equalTo(20);
}];
```

- 设置文件路径
```
BOOL flag = [self.player resetFile:filepath position:0];
if (flag) {
    NSLog(@"打开文件成功");
}
```

- 播放
```
[self.player play];
```
- 暂停
```
[self.player pause];
```
- seek操作
```
self.player.position = slider.value;
```

- 倍速播放
```
self.player.playRate = 1.5;
```

- 切换屏幕模式
```
self.player.screenMode = KVPlayerScreenOneToOne;    //屏幕模式，一比一
```

- 截图
```
UIImage * snapshot = [self.player snapshot];    //截图
```

- 切换音轨
```
self.player.selectAudioTrackIndex = (self.player.selectAudioTrackIndex + 1) % self.player.audioTrackCount;  //选择音轨
//这里偷了个懒，在设置音轨的时候，请先获取一下该视频的音轨数量，不要超过音轨数量
```

- 字幕操作
```
//字幕操作，这里的字幕为内嵌字幕，非外挂字幕
if (self.player.validSubTitle) {
    //判断该视频是否支持内嵌字幕，有些视频携带了字幕数据，这时候就可以设置字幕属性了
        self.player.subTitleHidden = YES;   //显示隐藏字幕
        self.player.subTitleFontSize = 14;  //字幕大小
        self.player.subTitleTextColor = [UIColor blackColor];   //字幕颜色
}
```

- 释放播放器
```
//适当的时机释放播放器
[self.player releasePlayer];
self.player = nil;
```

- 设置代理，接收播放器通知
```
//播放状态改变
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
//播放位置改变，实时通知
- (void)player:(KVPlayer *)player playAtTime:(float)location {
   
}
//FPS改变
- (void)player:(KVPlayer *)player fpsChanged:(int)fps {
    
}
//播放出错
- (void)player:(KVPlayer *)player didFailWithMsg:(NSString *)msg {
    
}
```
