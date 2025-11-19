/*
 * Copyright (c) 2025 Huawei Device Co., Ltd.
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *     http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */

import { media } from '@kit.MediaKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { common } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { fileIo  } from '@kit.CoreFileKit';
import { UIContext } from '@kit.ArkUI';

const DOMAIN = 0x0000;

export class AVPlayerDemo {
  private surfaceID: string = '';
  private timeStamp: number = 0;
  private avPlayer: media.AVPlayer | null = null;
  private status: string = '';
  private isSeek: boolean = true; // 用于区分模式是否支持seek操作。
  private uiContext = new UIContext()

  constructor(surfaceID: string, timeStamp: number = 0) {
    this.surfaceID = surfaceID;
    this.timeStamp = timeStamp;
  }

  setAVPlayerCallback(avPlayer: media.AVPlayer) {
    avPlayer.on('startRenderFrame', () => {
      hilog.info(DOMAIN, 'AVPlayerDemo', 'AVPlayer start render frame');
    });
    avPlayer.on('videoSizeChange', () => {

    });
    avPlayer.on('seekDone', (seekDoneTime: number) => {
      hilog.info(DOMAIN, 'AVPlayerDemo', `AVPlayer seek succeeded, seek time is ${seekDoneTime}`);
    });
    avPlayer.on('error', (err: BusinessError) => {
      hilog.error(DOMAIN, 'AVPlayerDemo', `Invoke avPlayer failed, code is ${err.code}, message is ${err.message}`);
      avPlayer.reset();
    });
    avPlayer.on('stateChange', async (state: string, reason: media.StateChangeReason) => {
      switch (state) {
        case 'idle':
          hilog.info(DOMAIN, 'AVPlayerDemo', 'AVPlayer state idle called.');
          avPlayer.release();
          break;
        case 'initialized':
          hilog.info(DOMAIN, 'AVPlayerDemo', 'AVPlayer state initialized called.');
          avPlayer.surfaceId = this.surfaceID;
          avPlayer.prepare();
          break;
        case 'prepared':
          hilog.info(DOMAIN, 'AVPlayerDemo', 'AVPlayer state prepared called.');
          avPlayer.play();
          break;
        case 'playing':
          hilog.info(DOMAIN, 'AVPlayerDemo', 'AVPlayer state playing called.');
          this.status = state;
          avPlayer.seek(this.timeStamp, media.SeekMode.SEEK_PREV_SYNC);
          break;
        case 'paused':
          hilog.info(DOMAIN, 'AVPlayerDemo', 'AVPlayer state paused called.');
          this.status = state;
          break;
        case 'completed':
          hilog.info(DOMAIN, 'AVPlayerDemo', 'AVPlayer state completed called.');
          avPlayer.stop();
          break;
        case 'stopped':
          hilog.info(DOMAIN, 'AVPlayerDemo', 'AVPlayer state stopped called.');
          avPlayer.prepare();
          break;
        case 'released':
          hilog.info(DOMAIN, 'AVPlayerDemo', 'AVPlayer state released called.');
          break;
        default:
          hilog.info(DOMAIN, 'AVPlayerDemo', 'AVPlayer state unknown called.');
          break;
      }
    });
  }

  // 以下demo为使用fs文件系统打开沙箱地址获取媒体文件地址并通过url属性进行播放示例。
  async avPlayerUrlDemo(fd: number | undefined) {
    // 创建avPlayer实例对象。
    let avPlayer: media.AVPlayer = await media.createAVPlayer();
    // 创建状态机变化回调函数。
    this.setAVPlayerCallback(avPlayer);
    let fdPath = 'fd://';
    // 通过UIAbilityContext获取沙箱地址filesDir，以Stage模型为例。
    // 打开相应的资源文件地址获取fd，并为url赋值触发initialized状态机上报。
    try {

      // let file = fileIo.openSync(sandUrl, fileIo.OpenMode.CREATE | fileIo.OpenMode.READ_WRITE);
      fdPath = fdPath+fd;
      console.log("zhao "+fdPath)
      this.isSeek = true; // 支持seek操作。
      avPlayer.url = fdPath;
      // fs.closeSync(file);
    } catch (e) {
      hilog.error(DOMAIN, 'AVPlayerDemo', `${e}`);
    }
  }

  async avPlayerFdSrcDemo(videoName: string) {
    let avPlayer: media.AVPlayer = await media.createAVPlayer();
    this.setAVPlayerCallback(avPlayer);
    let context = this.uiContext.getHostContext() as common.UIAbilityContext;
    let fileDescriptor = await context.resourceManager.getRawFd(videoName);
    let avFileDescriptor: media.AVFileDescriptor =
      { fd: fileDescriptor.fd, offset: fileDescriptor.offset, length: fileDescriptor.length };
    avPlayer.fdSrc = avFileDescriptor;
    this.avPlayer = avPlayer;
  }

  switchPlayOrPause() {
    if (this.avPlayer === null) {
      return;
    }
    if (this.status === 'playing') {
      this.avPlayer.pause();
    } else {
      this.avPlayer.play();
    }
  }

  pause() {
    if (this.avPlayer === null) {
      return;
    }
    this.avPlayer.pause();
  }

  play() {
    if (this.avPlayer === null) {
      return;
    }
    this.avPlayer.play();
  }
}