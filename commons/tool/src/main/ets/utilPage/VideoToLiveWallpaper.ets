import { curves, display, promptAction, UIContext, window } from '@kit.ArkUI';
import { BusinessError } from '@kit.BasicServicesKit';
import { photoAccessHelper } from '@kit.MediaLibraryKit';
import { videoCropUtil } from '../util/videoCropUtil';
import VideoUtils from '../util/VideoUtils';
import { image } from '@kit.ImageKit';
import { media } from '@kit.MediaKit';
import { VideoSizeData } from '../model/VideoSizeData';
import { fileIo, ReadOptions, WriteOptions } from '@kit.CoreFileKit';
import { ICallBack, MP4Parser } from '@ohos/mp4parser';
import { getTimeString } from '../util/TimeTools';
import { LoadingDialog } from '../commons/LoadingDialog';
import { AdFreeUseButton } from 'uicomponents';
import { OpenMemberVIP } from 'uicomponents/src/main/ets/button/OpenMemberVIP';
import { AdActionType } from 'globalclass';
import { AVPlayerDemo } from '../util/AVPlayerDemo';
import { fileIo as fs, fileUri } from '@kit.CoreFileKit';

export enum VideoToAnimationStyle {
  LIVE = 'LIVE',
  GIF = 'GIF'
}

//可以调节的参数枚举
enum AdjustableParameters {
  Clarity = '清晰度',
  Proportion = '比例',
  Crop = '裁切',
  Speed = '速率',
  Null = ''
}

//视频显示和裁剪的比例接口
export interface VideoToLiveWallpaperRatio {
  describe: string,
  aspRatio: number,
  icon: Resource
  ratio?: string
}

//GIF清晰度选项接口
export interface GifClarityOption {
  value: number,
  label: string,
  describe: string,
  icon: Resource
}

interface videoRect {
  x: number,
  y: number,
  width: number,
  height: number
}

//GIF清晰度选项数据
const GifClarityOptions: GifClarityOption[] = [
  {
    value: 240,
    label: '240p',
    describe: '低清',
    icon: $r('app.media.hq')
  },
  {
    value: 480,
    label: '480p',
    describe: '标清',
    icon: $r('app.media.sd')
  },
  {
    value: 720,
    label: '720p',
    describe: '高清',
    icon: $r('app.media.hd')
  },
  {
    value: 1080,
    label: '1080p',
    describe: '超清',
    icon: $r('app.media.hdplus')
  }
];

const VideoToLiveWallpaperRatioData: VideoToLiveWallpaperRatio[] = [
  {
    describe: '默认',
    aspRatio: 0,
    icon: $r('app.media.default')
  },
  {
    describe: '正方形',
    aspRatio: 1 / 1,
    icon: $r('app.media.square'),
    ratio: '1:1'
  },
  {
    describe: '标准',
    aspRatio: 4 / 3,
    icon: $r('app.media.standard'),
    ratio: '4:3'
  },
  {
    describe: '宽屏',
    aspRatio: 16 / 9,
    icon: $r('app.media.widescreen'),
    ratio: '16:9'
  },
  {
    describe: '竖屏',
    aspRatio: 9 / 16,
    icon: $r('app.media.verticalscreen'),
    ratio: '9:16'
  },
  {
    describe: '电影',
    aspRatio: 21 / 9,
    icon: $r('app.media.movie'),
    ratio: '21:9'
  },
  {
    describe: '自定义',
    aspRatio: -1,
    icon: $r('app.media.default')
  },
]

//可观测数组
@Observed
export class ObservedArray<T> extends Array<T> {
  constructor(args?: T[]) {
    if (args instanceof Array) {
      super(...args)
    } else {
      super()
    }
  }
}

const THUMBNAIL_HEIGHT = 50
const THUMBNAIL_COUNT = 4 // 时间轴显示的缩略图数量
// 最大、最小时长（毫秒）
const MAX_DURATION = 10000
const MIN_DURATION = 3000

//XComponent展示组件尺寸
const VIDEO_WIDTH = 1280;
const VIDEO_HEIGHT = 720;

@Component
export struct VideoToLiveWallpaper {
  // 屏幕安全区域高度配置
  bottomRectHeight: string = AppStorage.get<number>('bottomRectHeight') + 'px' // 底部安全区域高度
  topRectHeight: string = AppStorage.get<number>('topRectHeight') + 'px' // 顶部安全区域高度
  // 组件属性
  @Prop videoStyle: VideoToAnimationStyle // 判断是剪裁LIVE还是GIF的模式
  @Consume('nimblePathStack') nimblePathStack: NavPathStack; // 导航栈，用于页面跳转
  @State pixelMapInfoList: ObservedArray<image.PixelMap> = new ObservedArray() // 视频缩略图帧列表
  // SaveButton安全控件配置
  saveButtonOptions: SaveButtonOptions = {
    icon: SaveIconStyle.FULL_FILLED,
    text: SaveDescription.SAVE_TO_GALLERY,
    buttonType: ButtonType.Normal
  }
  // 加载框控制器
  dialog: CustomDialogController = new CustomDialogController({
    builder: LoadingDialog({ message: '正在生成' }),
    customStyle: true,
    alignment: DialogAlignment.Center,
    isModal: false
  })
  // 用户信息和广告控制
  // @StorageLink('userInfo') userInfo: huaweiUserInfo | null | undefined = null // 用户登录信息
  @State isVip: boolean = false //用于识别当前用户是否是会员（具体算法由其他模块实现）
  @StorageLink(`adType_${AdActionType.VideoEditing}`) VideoEditing: number = 0 // 视频编辑广告剩余次数
  // 拖拽控制
  @State private canDrag: boolean = true // 控制拖拽防抖，避免频繁触发
  // 视频相关状态
  @State private avImageGenerator: media.AVImageGenerator | undefined = undefined // 视频缩略图生成器
  @State private pixelMapShow: image.PixelMap | undefined = undefined // 当前显示的视频帧
  @State private currentTimeShow: string = '00:00:00' // 格式化的当前播放时间显示
  @State private fullTimeShow: string = '00:00:00' // 格式化的视频总时长显示
  @State private fullTime: number = 0 // 视频总时长（毫秒）
  @State private thumbnailWidth: number = 0 // 缩略图单帧宽度（动态计算）
  @State private selectedVideoUri: string = '' // 用户选择的视频URI
  @State private videoSize: VideoSizeData = new VideoSizeData() // 视频尺寸信息类
  @State private oneSecondWidth: number = 0 // 时间轴上一秒对应的像素宽度
  // 时间控制
  @State private startTime: number = 0 // 视频剪切开始时间（毫秒）
  @State private endTime: number = 0 // 视频剪切结束时间（毫秒）
  @State private currentTime: number = 0 // 当前播放时间（毫秒）
  // 时间轴UI控制
  @State private rightWidth: number = 0 // 右边界当前位置
  @State private rightWidthOrigin: number = 0 // 右边界原始位置（拖拽起始点）
  @State private leftWidthOrigin: number = 0 // 左边界原始位置（拖拽起始点）
  @State private currentOffsetOrigin: number = 0 // 播放指针原始位置（拖拽起始点）
  @State private currentOffset: number = 0 // 播放指针当前位置
  @State private leftWidth: number = 0 // 左边界当前位置
  // 播放状态控制
  @State private isVideoStart: boolean = false // 视频是否正在播放
  @State private isPlayed: boolean = false // 视频是否已经播放过（用于优化性能）
  @State private showTimePopup: boolean = false // 是否显示时间信息弹窗
  @State private isEditMode: boolean = false // 是否处于剪辑模式
  // 动态壁纸配置
  @State private imgName: string = 'moving_photo' // 动态壁纸文件名
  @State private _total: number = 2 // 广告免费使用总次数
  // GIF相关配置
  @State private isCreatingGif: boolean = false // 是否正在生成GIF（控制加载状态）
  @State private gifCropRatio: string = '' // GIF裁剪比例设置，如'4:3'、'16:9'等
  @State private gifSpeed: number = 1; //gif速率
  @State private currentSpeed: string = '1x'; // 组件显示速率
  // 拖拽辅助变量
  @State private initialRelative: number = 0 // 拖拽开始时播放指针的相对位置比例
  @State private isShowSheet: boolean = false // 是否显示登录面板
  @State private isShowSaveOptions: boolean = false // 是否显示保存选项
  //================================================================================

  //控制GIF部分自定义参数的变量
  @State private selectIndex: number = 0 //选中了比例调节按钮的索引
  @State private isShowParameterAdjustment: boolean = false //是否显示参数调节的部分
  @State private AdjustParameters: AdjustableParameters = AdjustableParameters.Null //当前调节的参数
  @State private videoScale: number = 0 //视频缩放比例
  @State private gifClarity: number = 720 //GIF清晰度，默认480p
  @State private claritySelectIndex: number = 2 //清晰度选择索引，默认选中480p
  //=====================================================================视频裁切=====================


  @State previewWidth: number = 0; // 预览区域宽（= 视频显示宽）
  @State previewHeight: number = 0; // 预览区域高（= 视频显示高）
  @State cropRect: videoRect = {
    x: 0,
    y: 0,
    width: 0,
    height: 0
  };
  private lastX: number = 0;
  private lastY: number = 0;
  private activeHandle: string = ''; // 'move' | 'lt' | 'rt' | 'lb' | 'rb'
  private dragging: boolean = false;
  private resizing: boolean = false;
  // 画布上下文配置 & 上下文对象
  private cropCanvasSettings: RenderingContextSettings = new RenderingContextSettings(true)
  private cropCanvasCtx: CanvasRenderingContext2D = new CanvasRenderingContext2D(this.cropCanvasSettings)
  private xComponentController: XComponentController = new XComponentController();
  @State surfaceID: string = '';
  @State avPlayer: AVPlayerDemo = new AVPlayerDemo('');
  @State private currentWidth: number = 0; //视频容器宽高
  @State private currentHeight: number = 0;
  @State private scaleVideo: number = 0; // 视频缩放比
  @State private isOr: boolean = false;
  @State isSelecting: boolean = false; //是否裁切
  @State isCropDone: boolean = false; //用于控制确定和撤销裁切
  @State cropDone: boolean = false; //用于控制buildMask显示
  private file: fileIo.File | null = null; // 视频文件描述符
  //================================================================================
  private context = this.getUIContext().getHostContext()!
  private videoController: VideoController = new VideoController() // 视频控制器
  private fileAlbum: fileIo.File | undefined = undefined //视频文件
  private avFileDescriptor: media.AVFileDescriptor | undefined = undefined //视频文件描述符
  private phAccessHelper: photoAccessHelper.PhotoAccessHelper =
    photoAccessHelper.getPhotoAccessHelper(this.context) //相册访问助手
  private speedMap: Record<string, number> = {
    '0.1x': 10,
    '1x': 1,
    '2x': 0.5,
    '5x': 0.2,
    '10x': 0.1,
    '100x': 0.01
  }
  pageInfos: NavPathStack = new NavPathStack();


  //设置状态栏颜色(深色，浅色)
  statusBarColor(model: boolean) {
    window.getLastWindow(this.context, async (err: BusinessError, data) => {
      if (model) {
        let SystemBarProperties: window.SystemBarProperties = {
          statusBarContentColor: '#F1F3F5'
        }
        await data.setWindowSystemBarProperties(SystemBarProperties);
      } else {
        let SystemBarProperties: window.SystemBarProperties = {
          statusBarContentColor: '#2F2F2F'
        }
        await data.setWindowSystemBarProperties(SystemBarProperties);
      }
    })
  }

  //从相册中选择视频
  selectVideo() {
    let photoSelectOptions: photoAccessHelper.PhotoSelectOptions =
      new photoAccessHelper.PhotoSelectOptions();
    photoSelectOptions.MIMEType = photoAccessHelper.PhotoViewMIMETypes.VIDEO_TYPE;
    photoSelectOptions.maxSelectNumber = 1;
    const photoViewPicker = new photoAccessHelper.PhotoViewPicker();
    photoViewPicker.select(photoSelectOptions)
      .then(async (photoSelectResult: photoAccessHelper.PhotoSelectResult) => {
        if (photoSelectResult.photoUris.length == 0) {
          return
        }
        // 清理之前的资源
        await this.cleanupResources()

        this.selectedVideoUri = photoSelectResult.photoUris[0]

        this.file = await fs.open(this.selectedVideoUri);

        //开始获取视频信息
        this.getVideoInfo()
      })
  }

  async getVideoInfo() {
    this.fullTime = await videoCropUtil.getVideoDuration(this.selectedVideoUri, this.context)
    console.log('视频总时长：', this.fullTime.toString());
    this.fullTimeShow = videoCropUtil.formatDuration(this.fullTime)
    this.currentTimeShow = videoCropUtil.formatDuration(this.currentTime)

    // 根据模式设置时间范围
    if (!this.isEditMode) {
      // 开始创作模式：显示完整视频
      this.startTime = 0
      this.endTime = this.fullTime
    } else {
      // 剪辑模式：应用时长限制
      if (this.fullTime <= MAX_DURATION) {
        this.startTime = 0
        this.endTime = this.fullTime
      } else {
        this.startTime = 0
        this.endTime = MAX_DURATION
      }
    }

    // 根据时间换算成宽度
    this.leftWidth = this.timeToOffset(this.startTime)
    this.rightWidth = this.timeToOffset(this.endTime)
    this.leftWidthOrigin = this.leftWidth
    this.rightWidthOrigin = this.rightWidth

    this.currentTime = this.startTime
    // 设置视频控制器的当前时间到开始时间
    this.currentOffset = this.timeToOffset(this.startTime)
    this.currentOffsetOrigin = this.currentOffset

    // 获取视频一秒所占的宽度
    this.oneSecondWidth = this.fullTime > 0 ? (this.getTimelineWidth() / this.fullTime * 1000) : 0

    await this.imageGeneratorGetThumbnail() //获取视频缩略图
    this.pixelMapShow = await this.fetchFrameByTime(this.currentTime * 1000, false)

    // 视频帧缩略图
    this.pixelMapInfoList = [
      await this.fetchFrameByTime(0),
      await this.fetchFrameByTime(Math.floor(this.fullTime * 1000 / 3)),
      await this.fetchFrameByTime(Math.floor(this.fullTime * 1000 / 3 * 2)),
      await this.fetchFrameByTime(Math.floor(this.fullTime * 1000))
    ].filter(pm => pm !== undefined) as image.PixelMap[];
  }

  /**
   * 创建视频帧生成器（AVImageGenerator）并准备获取缩略图
   */
  async imageGeneratorGetThumbnail() {
    // 1. 如果没有选择视频 URI，则直接返回，不做处理
    if (this.selectedVideoUri === '') {
      return;
    }

    // 2. 如果之前已经有 AVImageGenerator 实例，先释放资源
    if (this.avImageGenerator) {
      if (canIUse('SystemCapability.Multimedia.Media.AVImageGenerator')) {
        await this.avImageGenerator.release()
      }
    }

    // 3. 打开视频文件，只读模式
    this.fileAlbum = fileIo.openSync(this.selectedVideoUri, fileIo.OpenMode.READ_ONLY)

    // 4. 获取文件描述符，用于 AVImageGenerator 读取视频内容
    this.avFileDescriptor = { fd: this.fileAlbum.fd }

    // 5. 使用 getVideoData 获取视频的宽高和总时长
    this.videoSize = await videoCropUtil.getVideoData(this.avFileDescriptor)

    // 6. 创建 AVImageGenerator 实例
    this.avImageGenerator = await media.createAVImageGenerator()

    // 7. 如果创建成功，绑定视频源文件描述符
    if (this.avImageGenerator) {
      this.avImageGenerator.fdSrc = this.avFileDescriptor;
    } else {
      // 8. 创建失败，直接返回
      return;
    }
  }

  /**
   * 根据指定时间获取视频帧图像（统一方法）
   * @param time 时间点（毫秒）
   * @param precise 是否使用精确模式，true为精确（慢），false为快速（可能不够精确）
   * @returns 对应时间的 PixelMap（视频帧图像），如果不可用返回 undefined
   */
  async fetchFrameByTime(time: number, precise: boolean = false): Promise<image.PixelMap | undefined> {
    const queryOption = precise
      ? media.AVImageQueryOptions.AV_IMAGE_QUERY_CLOSEST     // 精确模式
      : media.AVImageQueryOptions.AV_IMAGE_QUERY_NEXT_SYNC; // 快速模式

    let pixelMap = await this.avImageGenerator?.fetchFrameByTime(
      time,
      queryOption,
      this.videoSize.photoSize
    );

    return pixelMap;
  }

  aboutToAppear() {
    //改变状态栏颜色
    this.statusBarColor(true)
    // 计算缩略图的宽度
    // 1.获取当前窗口宽度
    const windowWidth = display.getDefaultDisplaySync().width;
    // 2.将宽度从px转换为vp
    this.thumbnailWidth = windowWidth / display.getDefaultDisplaySync().densityPixels / 5
    // 设置默认时间轴宽度，确保时间轴始终可见
    this.rightWidth = this.getTimelineWidth()
    this.rightWidthOrigin = this.rightWidth
    this.leftWidth = 0
    this.leftWidthOrigin = 0
    this.currentOffset = 0
    this.currentOffsetOrigin = 0
  }

  aboutToDisappear() {
    this.statusBarColor(false)
    // 页面销毁时清理所有资源
    this.cleanupResources()
  }

  build() {
    Navigation(this.pageInfos) {
      Column() {
        //top栏目
        Row() {
          Row() {
            Image($r('app.media.chevron_left'))
              .fillColor(Color.White)
              .width(40)
              .height(40)
              .margin({ right: 8 })
              .padding(11.5)
              .borderRadius(20)
              .backgroundColor('#2F2F2F')
              .onClick(() => {
                this.nimblePathStack.pop()
              })

            Text('编辑')
              .fontColor(Color.White)
              .fontSize(20)
              .fontWeight(FontWeight.Bold)
          }
          .justifyContent(FlexAlign.Start)
          .transition(TransitionEffect.translate({ x: 50, y: 0 })
            .animation({ duration: 500, curve: Curve.LinearOutSlowIn }))

          Blank()
          Button("保存")
            .type(ButtonType.Normal)
            .backgroundColor($r('app.color.shareButtonConfirm'))
            .height(35)
            .borderRadius(10)
            .onClick(() => {
              // 检查是否选择了视频
              if (!this.selectedVideoUri) {
                promptAction.showToast({
                  message: '请先选择视频',
                  duration: 2000
                });
                return;
              }

              // 如果参数调节面板正在显示，先收回
              if (this.isShowParameterAdjustment) {
                this.isShowParameterAdjustment = false;
              }

              // 切换保存选项显示状态
              this.isShowSaveOptions = !this.isShowSaveOptions;
            })
        }
        .padding({ left: 10, right: 10 })
        .width('100%')
        .flexBasis('auto')

        Column() {
          //视频播放区域
          Stack({ alignContent: Alignment.Center }) {
            //自动登录相关算法
            // unifiedLoginComPanel({
            //   show: this.isShowSheet
            // })
            //点击添加视频的按钮
            Row() {
              this.selectVideoButton()
            }
            .visibility(!this.selectedVideoUri ? Visibility.Visible : Visibility.Hidden)
            .transition(TransitionEffect.scale({ x: 0.2, y: 0.2 }).animation({ curve: curves.springMotion(0.6, 0.8) }))

            //video组件播放视频 - 使用条件渲染解决aspectRatio重置问题
            if (this.videoScale === 0) {
              // 默认比例：不设置aspectRatio，让视频保持原始比例
              this.buildVideoComponent(false)
            } else if (this.videoScale === -1) {
              this.cropVideoComponent()
            } else {
              // 指定比例：设置aspectRatio
              this.buildVideoComponent(true)
            }
          }
          .onSizeChange((oldValue: SizeOptions, newValue: SizeOptions) => {
            this.currentWidth = Number(newValue.width)
            this.currentHeight = Number(newValue.height)
          })
          .height('65%')
          .width('100%')
          .margin({ top: 10, bottom: 10 })
          .backgroundColor('#141414')
          .displayPriority(2)

          //视频播放时间区域
          Row() {
            // 根据模式显示不同的时间信息
            if (this.isEditMode) {
              // 剪辑模式：显示当前播放时间和选中区域的结束时间
              Text(videoCropUtil.formatDuration(this.currentTime) + ' | ')
                .timeText()
              Text(videoCropUtil.formatDuration(this.endTime))
                .timeText()
            } else {
              // 普通模式：显示当前播放时间和总时长
              Text(this.currentTimeShow + ' | ')
                .timeText()
              Text(this.fullTimeShow)
                .timeText()
            }

            Blank()

            Image(this.selectedVideoUri ? (this.isVideoStart ? $r('app.media.pause') : $r('app.media.play_fill')) :
            $r('app.media.pause'))
              .width(20)
              .height(20)
              .opacity(this.selectedVideoUri ? 1 : 0.5) // 没有视频时显示为半透明
              .onClick(async () => {
                // 如果没有选择视频，不执行任何操作
                if (!this.selectedVideoUri) {
                  console.log('没有选择视频，播放按钮无效');
                  return;
                }

                if (this.isVideoStart) {
                  // 当前正在播放，点击暂停
                  console.log('暂停播放');
                  this.videoController.pause();
                  this.isVideoStart = false;
                } else {
                  // 当前已暂停，点击播放
                  console.log('开始播放');
                  // 如果当前时间已经到达结束时间，从开始时间重新播放
                  if (this.currentTime >= this.endTime - 100) { // 100ms容差
                    const startTimeSeconds = Math.round(this.startTime / 1000);
                    console.log('从开始时间重新播放：', startTimeSeconds, '秒');
                    this.videoController.setCurrentTime(startTimeSeconds, SeekMode.Accurate);
                    this.currentTime = this.startTime;
                    this.currentOffset = this.timeToOffset(this.startTime);
                    this.currentOffsetOrigin = this.currentOffset;
                    await new Promise<void>(r => setTimeout(r, 120));
                  }
                  this.videoController.start();
                  this.isVideoStart = true;
                }
              })
          }
          .width('100%')
          .padding({ left: 10, right: 10 })
          .margin({ bottom: 10 })
          .flexBasis('auto')
          .displayPriority(2)

          Column() {
            //参数调节选择区域
            Row() {
              if (this.AdjustParameters == AdjustableParameters.Proportion) {
                this.SelectRatio()
              } else if (this.AdjustParameters == AdjustableParameters.Clarity) {
                this.SelectClarity()
              } else if (this.AdjustParameters == AdjustableParameters.Speed) {
                this.SelectSpeed()
              } else if (this.AdjustParameters == AdjustableParameters.Crop) {
                this.SelectCrop()
              }
            }
            .width('100%')
            .padding({
              left: 10,
              right: 10,
              top: 20,
              bottom: 20
            })
            .height(110)
            .visibility((this.isShowParameterAdjustment && this.videoStyle !== VideoToAnimationStyle.LIVE) ?
            Visibility.Visible : Visibility.Hidden)
            .transition(TransitionEffect.translate({ y: '100%' }))
            .animation({ duration: 340, curve: Curve.EaseInOut })
            .margin({ bottom: 6 })

            //底部按钮
            Row() {
              if (!this.isShowSaveOptions) {
                //参数调节按钮区域 - 在LIVE模式下隐藏
                if (this.videoStyle !== VideoToAnimationStyle.LIVE) {
                  Column() {
                    Divider()
                      .color(Color.Gray)
                      .strokeWidth(1.5)
                      .margin({ bottom: 4 })
                    Row({ space: 20 }) {
                      //调节GIF分辨率按钮（仅GIF模式显示）
                      if (this.videoStyle == VideoToAnimationStyle.GIF) {
                        Column({ space: 3 }) {
                          Image(this.AdjustParameters === AdjustableParameters.Clarity ?
                          $r('app.media.resolution_select') : $r('app.media.resolution'))
                            .width(24)
                            .height(24)
                            .objectFit(1)
                            .margin({ bottom: 4 })
                          Text('分辨率')
                            .fontColor(Color.White)
                            .fontWeight(500)
                            .fontSize(10)
                        }
                        .onClick(() => {
                          // 显示清晰度参数调节
                          if (this.isShowParameterAdjustment &&
                            this.AdjustParameters === AdjustableParameters.Clarity) {
                            // 如果当前已显示清晰度参数，则隐藏
                            this.isShowParameterAdjustment = false
                          } else {
                            // 否则显示清晰度参数
                            this.videoScale = 0
                            this.isShowParameterAdjustment = true
                            this.AdjustParameters = AdjustableParameters.Clarity
                          }
                        })
                      }
                      // 裁切按钮（仅GIF模式显示）
                      if (this.videoStyle == VideoToAnimationStyle.GIF) {
                        Column({ space: 3 }) {
                          Image(this.AdjustParameters === AdjustableParameters.Crop ? $r('app.media.cut_selects') :
                          $r('app.media.cut'))
                            .width(24)
                            .height(24)
                            .objectFit(1)
                            .margin({ bottom: 4 })
                          Text('裁切')
                            .fontColor(Color.White)
                            .fontWeight(500)
                            .fontSize(10)
                            .maxLines(1)
                        }
                        .onClick(() => {
                          if (this.isShowParameterAdjustment &&
                            this.AdjustParameters === AdjustableParameters.Crop) {
                            this.isShowParameterAdjustment = false
                          } else {

                            this.videoScale = 0
                            this.isEditMode = true
                            this.isShowParameterAdjustment = true
                            this.AdjustParameters = AdjustableParameters.Crop
                          }
                        })
                      }
                      // 比例选择按钮（仅GIF模式显示）
                      if (this.videoStyle == VideoToAnimationStyle.GIF) {
                        Column({ space: 3 }) {
                          Image(this.AdjustParameters === AdjustableParameters.Proportion ?
                          $r('app.media.proportion_select') : $r('app.media.proportion'))
                            .width(24)
                            .height(24)
                            .objectFit(1)
                            .margin({ bottom: 4 })
                          Text(this.gifCropRatio || '比例')
                            .fontColor(Color.White)
                            .fontWeight(500)
                            .fontSize(10)
                            .maxLines(1)
                        }
                        .onClick(() => {
                          // 显示比例选择
                          if (this.isShowParameterAdjustment &&
                            this.AdjustParameters === AdjustableParameters.Proportion) {
                            // 如果当前已显示比例参数，则隐藏
                            this.isShowParameterAdjustment = false
                          } else {
                            // 否则显示比例参数
                            this.pageInfos.pushPath({ name: 'CropVideo' });
                            this.isShowParameterAdjustment = true
                            this.AdjustParameters = AdjustableParameters.Proportion
                          }
                        })
                      }
                      if (this.videoStyle == VideoToAnimationStyle.GIF) {
                        Column({ space: 3 }) {
                          Image(this.AdjustParameters === AdjustableParameters.Speed ? $r('app.media.speed_selects') :
                          $r('app.media.speed'))
                            .width(24)
                            .height(24)
                            .objectFit(1)
                            .margin({ bottom: 4 })
                          Text('速率')
                            .fontColor(Color.White)
                            .fontWeight(500)
                            .fontSize(10)
                            .maxLines(1)
                        }
                        .onClick(() => {
                          // 显示比例选择
                          if (this.isShowParameterAdjustment &&
                            this.AdjustParameters === AdjustableParameters.Speed) {
                            // 如果当前已显示比例参数，则隐藏
                            this.isShowParameterAdjustment = false
                          } else {
                            this.videoScale = 0 //======================= 明天修改要求  只将自定义功能隔离出来==================//
                            this.isShowParameterAdjustment = true
                            this.AdjustParameters = AdjustableParameters.Speed
                          }
                        })
                      }
                    }
                    .width('100%')
                    .padding({ left: 10, right: 10 })
                    .justifyContent(FlexAlign.SpaceAround)
                  }
                  .backgroundColor('#1c1c1c')
                  .zIndex(2)
                  .clip(true)
                  .width('100%')
                  .height('100%')
                }
              } else {
                //保存选项区域 - 使用已有的builder
                if (this.videoStyle == VideoToAnimationStyle.LIVE) {
                  //保存为动态壁纸
                  Column() {
                    Row() {
                      if ((!this.isVip) && this.VideoEditing < 2) {
                        this.buildActionButton(false)
                      } else {
                        Stack() {
                          this.buildActionButton(true)
                          SaveButton(this.saveButtonOptions)
                            .borderRadius(20)
                            .backgroundColor('#20000000')
                            .height(50)
                            .onClick(async (event, result: SaveButtonOnClickResult) => {
                              if (result == SaveButtonOnClickResult.SUCCESS) {
                                await this.saveAsMovingPhoto()
                              } else {
                                promptAction.showToast({
                                  message: '需要授权才能保存动态壁纸',
                                  duration: 2000
                                })
                              }
                            })
                            .width('80%')
                        }
                      }
                    }
                    .justifyContent(FlexAlign.Center)
                    .width('100%')
                  }
                  .height('100%')
                  .width('100%')
                  .padding({ left: 10, right: 10 })
                } else if (this.videoStyle == VideoToAnimationStyle.GIF) {
                  //保存为GIF
                  Column() {
                    Row() {
                      if ((!this.isVip) && this.VideoEditing < 2) {
                        this.buildActionButton(false)
                      } else {
                        Stack() {
                          this.buildActionButton(true)
                          SaveButton(this.saveButtonOptions)
                            .borderRadius(20)
                            .backgroundColor('#20000000')
                            .height(50)
                            .onClick(async (event, result: SaveButtonOnClickResult) => {
                              if (result == SaveButtonOnClickResult.SUCCESS) {
                                await this.saveAsGifWithPermission()
                              } else {
                                promptAction.showToast({
                                  message: '需要授权才能保存GIF',
                                  duration: 2000
                                })
                              }
                            })
                            .width('80%')
                        }
                      }
                    }
                    .justifyContent(FlexAlign.Center)
                    .width('100%')
                  }
                  .height('100%')
                  .width('100%')
                  .padding({ left: 10, right: 10 })
                }
              }
            }
            .width('100%')
            .height('100%')
            .justifyContent(FlexAlign.Start)
          }
          .justifyContent(FlexAlign.End)
          .width('100%')
          .flexBasis('auto')
          .height(180)
          .displayPriority(2)
        }
        .justifyContent(FlexAlign.SpaceBetween)
        .flexGrow(1)
        .flexShrink(1)


        // .flexBasis('auto')
      }
      .padding({ top: this.topRectHeight, bottom: this.bottomRectHeight })
      .width('100%')
      .height('100%')
      .alignItems(HorizontalAlign.Start)
      .justifyContent(FlexAlign.Start)
    }
  }

  @Builder
  cropVideoComponent() {
    Stack({ alignContent: Alignment.TopStart }) {
      // 底层：XComponent 播放视频
      XComponent({
        id: 'VideoCropping',
        type: XComponentType.SURFACE,
        controller: this.xComponentController
      })
        .onLoad(async () => {
          this.isOr = await videoCropUtil.getVideoOrientation(this.selectedVideoUri, this.context) //判断视频是否旋转
          let w = this.videoSize.photoSize.width
          let h = this.videoSize.photoSize.height

          if (this.isOr) { // 如果视频是旋转的，将宽高置换
            h = this.videoSize.photoSize.width
            w = this.videoSize.photoSize.height
          }

          // 设置画布显示尺寸大小（和你原来的逻辑一致）
          if (w! > h!) {
            this.scaleVideo = this.currentWidth / w!
            const displayH = this.scaleVideo * h!
            this.previewWidth = this.currentWidth
            this.previewHeight = displayH

            this.xComponentController.setXComponentSurfaceRect({
              surfaceWidth: this.getUIContext().vp2px(this.previewWidth),
              surfaceHeight: this.getUIContext().vp2px(this.previewHeight)
            })
          } else {
            this.scaleVideo = this.currentHeight / h!
            const displayW = this.scaleVideo * w!
            this.previewWidth = displayW
            this.previewHeight = this.currentHeight

            this.xComponentController.setXComponentSurfaceRect({
              surfaceWidth: this.getUIContext().vp2px(this.previewWidth),
              surfaceHeight: this.getUIContext().vp2px(this.previewHeight)
            })
          }

          // 初始化一个居中的裁剪框（80%大小）
          const initW = this.previewWidth * 0.8
          const initH = this.previewHeight * 0.8
          this.cropRect = {
            x: (this.previewWidth - initW) / 2,
            y: (this.previewHeight - initH) / 2,
            width: initW,
            height: initH
          }

          this.surfaceID = this.xComponentController.getXComponentSurfaceId();
          this.avPlayer = new AVPlayerDemo(this.surfaceID, 0); // 创建AVPlayer实例
          this.avPlayer.avPlayerUrlDemo(this.file?.fd) // 将已经视频文件描述符传给AVPlayer用于打开视频
        })
        // XComponent 在 UI 上也用同样的大小
        .width(this.previewWidth || '100%')
        .height(this.previewHeight || '100%')

      // 上层：裁剪蒙层
      if (this.previewWidth > 0 && this.previewHeight > 0) {
        this.cropMask()
      }

    }
    .alignContent(Alignment.Center)
    .height('100%')
    .width('100%')
  }

  //自定义视频尺寸截取遮罩
  @Builder
  cropMask() {
    Canvas(this.cropCanvasCtx)
      .width(this.previewWidth)
      .height(this.previewHeight)
      .onReady(() => {
        // 每次 ready 或尺寸变化时重画一遍
        this.drawCropMask()
      })
      .onTouch((event: TouchEvent) => {
        this.onCropTouch(event)
        // 手势改变了 cropRect 之后，重画一次
        this.drawCropMask()
      })
  }

  private hitTestHandle(x: number, y: number): string {
    const r = this.cropRect
    const handleSize = 30 // 角 handle 半径
    const edgeThickness = 20 // 边 handle 的点击高度/宽度

    // 四角
    if (Math.abs(x - r.x) < handleSize && Math.abs(y - r.y) < handleSize) {
      return 'lt'
    }
    if (Math.abs(x - (r.x + r.width)) < handleSize && Math.abs(y - r.y) < handleSize) {
      return 'rt'
    }
    if (Math.abs(x - r.x) < handleSize && Math.abs(y - (r.y + r.height)) < handleSize) {
      return 'lb'
    }
    if (Math.abs(x - (r.x + r.width)) < handleSize && Math.abs(y - (r.y + r.height)) < handleSize) {
      return 'rb'
    }

    // 上边中段
    if (Math.abs(y - r.y) < edgeThickness && x > r.x + handleSize && x < r.x + r.width - handleSize) {
      return 'top'
    }
    // 下边中段
    if (Math.abs(y - (r.y + r.height)) < edgeThickness && x > r.x + handleSize && x < r.x + r.width - handleSize) {
      return 'bottom'
    }
    // 左边中段
    if (Math.abs(x - r.x) < edgeThickness && y > r.y + handleSize && y < r.y + r.height - handleSize) {
      return 'left'
    }
    // 右边中段
    if (Math.abs(x - (r.x + r.width)) < edgeThickness && y > r.y + handleSize && y < r.y + r.height - handleSize) {
      return 'right'
    }

    // 框内拖动
    if (x > r.x && x < r.x + r.width && y > r.y && y < r.y + r.height) {
      return 'move'
    }

    return ''
  }

  private updateCropRect(dx: number, dy: number) {
    const maxW: number = this.previewWidth
    const maxH: number = this.previewHeight
    const minSize: number = 60

    let left: number = this.cropRect.x
    let top: number = this.cropRect.y
    let right: number = this.cropRect.x + this.cropRect.width
    let bottom: number = this.cropRect.y + this.cropRect.height

    // ========== 1. 整体移动 ==========
    if (this.dragging && this.activeHandle === 'move') {
      left += dx
      right += dx
      top += dy
      bottom += dy

      const widthNow: number = right - left
      const heightNow: number = bottom - top

      // 水平方向整体限制在 [0, maxW]
      if (widthNow <= maxW) {
        if (left < 0) {
          right -= left
          left = 0
        }
        if (right > maxW) {
          const over = right - maxW
          left -= over
          right = maxW
        }
      }

      // 垂直方向整体限制在 [0, maxH]
      if (heightNow <= maxH) {
        if (top < 0) {
          bottom -= top
          top = 0
        }
        if (bottom > maxH) {
          const over = bottom - maxH
          top -= over
          bottom = maxH
        }
      }
    }
    // ========== 2. 缩放 ==========
    else if (this.resizing) {
      const dragLeft: boolean =
        (this.activeHandle === 'lt' || this.activeHandle === 'lb' || this.activeHandle === 'left')
      const dragRight: boolean =
        (this.activeHandle === 'rt' || this.activeHandle === 'rb' || this.activeHandle === 'right')
      const dragTop: boolean = (this.activeHandle === 'lt' || this.activeHandle === 'rt' || this.activeHandle === 'top')
      const dragBottom: boolean =
        (this.activeHandle === 'lb' || this.activeHandle === 'rb' || this.activeHandle === 'bottom')

      // 先根据拖拽修改边
      if (dragLeft) {
        left += dx
      }
      if (dragRight) {
        right += dx
      }
      if (dragTop) {
        top += dy
      }
      if (dragBottom) {
        bottom += dy
      }

      // ……下面那段“只约束正在拖的那一侧 + minSize 限制”的逻辑照旧即可
      // 水平方向
      if (dragLeft) {
        if (left < 0) {
          left = 0
        }
        if (right - left < minSize) {
          left = right - minSize
          if (left < 0) {
            left = 0
            right = minSize
          }
        }
      } else if (dragRight) {
        if (right > maxW) {
          right = maxW
        }
        if (right - left < minSize) {
          right = left + minSize
          if (right > maxW) {
            right = maxW
            left = right - minSize
          }
        }
      }

      // 垂直方向
      if (dragTop) {
        if (top < 0) {
          top = 0
        }
        if (bottom - top < minSize) {
          top = bottom - minSize
          if (top < 0) {
            top = 0
            bottom = minSize
          }
        }
      } else if (dragBottom) {
        if (bottom > maxH) {
          bottom = maxH
        }
        if (bottom - top < minSize) {
          bottom = top + minSize
          if (bottom > maxH) {
            bottom = maxH
            top = bottom - minSize
          }
        }
      }
    }


    // 写回
    this.cropRect = {
      x: left,
      y: top,
      width: right - left,
      height: bottom - top
    }
  }

  private drawCropMask() {
    const ctx: CanvasRenderingContext2D = this.cropCanvasCtx
    const r = this.cropRect
    const w = this.previewWidth
    const h = this.previewHeight

    // 1. 清空画布
    ctx.clearRect(0, 0, w, h)

    // 2. 外部暗角（可选，如果不想要就删掉这几行）
    ctx.fillStyle = 'rgba(0, 0, 0, 0.5)'
    ctx.fillRect(0, 0, w, h)
    // 挖出中间区域
    ctx.clearRect(r.x, r.y, r.width, r.height)

    // 3. 九宫格辅助线
    ctx.strokeStyle = '#FFFFFF'
    ctx.lineWidth = 1

    const colW = r.width / 3
    const rowH = r.height / 3

    // 竖线
    ctx.beginPath()
    ctx.moveTo(r.x + colW, r.y)
    ctx.lineTo(r.x + colW, r.y + r.height)
    ctx.moveTo(r.x + 2 * colW, r.y)
    ctx.lineTo(r.x + 2 * colW, r.y + r.height)
    ctx.stroke()

    // 横线
    ctx.beginPath()
    ctx.moveTo(r.x, r.y + rowH)
    ctx.lineTo(r.x + r.width, r.y + rowH)
    ctx.moveTo(r.x, r.y + 2 * rowH)
    ctx.lineTo(r.x + r.width, r.y + 2 * rowH)
    ctx.stroke()

    // 4. 四个直角边角
    const cornerLen = 22 // 边角线长度
    ctx.lineWidth = 3

    // 左上角
    ctx.beginPath()
    ctx.moveTo(r.x, r.y + cornerLen)
    ctx.lineTo(r.x, r.y)
    ctx.lineTo(r.x + cornerLen, r.y)
    ctx.stroke()

    // 右上角
    ctx.beginPath()
    ctx.moveTo(r.x + r.width - cornerLen, r.y)
    ctx.lineTo(r.x + r.width, r.y)
    ctx.lineTo(r.x + r.width, r.y + cornerLen)
    ctx.stroke()

    // 左下角
    ctx.beginPath()
    ctx.moveTo(r.x, r.y + r.height - cornerLen)
    ctx.lineTo(r.x, r.y + r.height)
    ctx.lineTo(r.x + cornerLen, r.y + r.height)
    ctx.stroke()

    // 右下角
    ctx.beginPath()
    ctx.moveTo(r.x + r.width - cornerLen, r.y + r.height)
    ctx.lineTo(r.x + r.width, r.y + r.height)
    ctx.lineTo(r.x + r.width, r.y + r.height - cornerLen)
    ctx.stroke()

    // 5. 四条边中点的小手柄（短白线）
    const edgeHandleLen = 26
    const edgeLineWidth = 4
    ctx.lineWidth = edgeLineWidth

    // 上边中点
    let cx = r.x + r.width / 2
    ctx.beginPath()
    ctx.moveTo(cx - edgeHandleLen / 2, r.y)
    ctx.lineTo(cx + edgeHandleLen / 2, r.y)
    ctx.stroke()

    // 下边中点
    ctx.beginPath()
    ctx.moveTo(cx - edgeHandleLen / 2, r.y + r.height)
    ctx.lineTo(cx + edgeHandleLen / 2, r.y + r.height)
    ctx.stroke()

    // 左边中点
    let cy = r.y + r.height / 2
    ctx.beginPath()
    ctx.moveTo(r.x, cy - edgeHandleLen / 2)
    ctx.lineTo(r.x, cy + edgeHandleLen / 2)
    ctx.stroke()

    // 右边中点
    ctx.beginPath()
    ctx.moveTo(r.x + r.width, cy - edgeHandleLen / 2)
    ctx.lineTo(r.x + r.width, cy + edgeHandleLen / 2)
    ctx.stroke()
  }

  private onCropTouch(event: TouchEvent) {
    const touch = event.touches[0]
    const x = touch.x
    const y = touch.y

    switch (event.type) {
      case TouchType.Down:
        this.activeHandle = this.hitTestHandle(x, y)
        this.dragging = this.activeHandle === 'move'
        this.resizing = this.activeHandle !== '' && this.activeHandle !== 'move'
        this.lastX = x
        this.lastY = y
        break
      case TouchType.Move:
        const dx = x - this.lastX
        const dy = y - this.lastY
        this.lastX = x
        this.lastY = y
        if (this.dragging || this.resizing) {
          this.updateCropRect(dx, dy)
        }
        break
      case TouchType.Up:
      case TouchType.Cancel:
        this.dragging = false
        this.resizing = false
        this.activeHandle = ''
        break
    }
  }

  private getCropResult(): videoRect {
    const scale = this.scaleVideo // 你初始化视频时算过的缩放比例

    const cropX = Math.round(this.cropRect.x / scale)
    const cropY = Math.round(this.cropRect.y / scale)
    const cropW = Math.round(this.cropRect.width / scale)
    const cropH = Math.round(this.cropRect.height / scale)

    return {
      x: cropX,
      y: cropY,
      width: cropW,
      height: cropH
    }
  }

  //构建Video组件的通用Builder================================================================================
  @Builder
  buildVideoComponent(useAspectRatio: boolean) {

    Video({ src: this.selectedVideoUri, controller: this.videoController, previewUri: this.pixelMapShow })
      .objectFit(useAspectRatio ? ImageFit.Cover : ImageFit.Contain)
      .aspectRatio(useAspectRatio ? this.videoScale : undefined)
      .animation({
        duration: 400,
        curve: Curve.EaseInOut
      })
      .controls(false)
      .visibility(this.selectedVideoUri ? Visibility.Visible : Visibility.None)
      .transition(TransitionEffect.scale({ x: 0.2, y: 0.2 }).animation({ curve: curves.springMotion(0.6, 0.8) }))
      .onUpdate((event) => {
        if (event) {
          // 更新当前播放时间
          this.currentTime = event.time * 1000; // 转换为毫秒
          this.currentTimeShow = videoCropUtil.formatDurationSecond(event.time)

          // 更新播放指示条位置
          const newOffset = this.timeToOffset(event.time * 1000);
          if (newOffset >= this.currentOffsetOrigin) {
            this.currentOffset = newOffset
          }

          // 视频播放到结束位置时自动暂停
          if (event.time >= this.endTime / 1000 - 1) { // 1秒容差
            console.log('视频播放到结束位置，自动暂停');
            this.videoController.pause()
            this.isVideoStart = false
            this.currentTime = this.endTime;
            this.currentOffset = this.timeToOffset(this.endTime)
            this.currentOffsetOrigin = this.currentOffset
          }
        }
      })
      .onPause(() => {
        this.isVideoStart = false
        console.log('结束播放了');
      })
      .onPrepared(() => {
        // 视频准备就绪时，只更新UI状态，不设置播放时间
        console.log('视频准备就绪');
        this.currentOffset = this.timeToOffset(this.startTime);
        this.currentOffsetOrigin = this.currentOffset;
      })
      .onStart(() => {
        console.log('视频开始播放');
        this.isPlayed = true
        this.isVideoStart = true
        // 同步播放指示条位置到当前时间
        this.currentOffset = this.timeToOffset(this.currentTime)
        this.currentOffsetOrigin = this.currentOffset
      })


  }

  //选择视频的按钮Builder
  @Builder
  selectVideoButton() {
    Column() {
      Text('+')
        .fontWeight(800)
        .fontSize(20)
        .textAlign(TextAlign.Center)
        .fontColor('#2F2F2F')
        .width(30)
        .height(30)
        .borderRadius(5)
        .backgroundColor(Color.White)
        .margin({ bottom: 10 })
      Text('开始创作')
        .fontSize(17)
        .fontColor(Color.White)
        .fontWeight(800)
    }
    .onClick(() => {
      //开始创作：直接选择视频并进入剪辑模式
      this.selectVideo()
    })
  }

  //视频缩略图Builder
  @Builder
  thumbnailShow() {
    Row() {
      if (this.pixelMapInfoList.length > 0 && this.isEditMode) {
        // 有视频时显示真实缩略图
        ForEach(this.pixelMapInfoList, (item: image.PixelMap, index: number) => {
          Image(item)
            .height(THUMBNAIL_HEIGHT)
            .width(this.thumbnailWidth)
            .draggable(false)
        })
      } else {
        // 没有视频时显示占位符
        ForEach([1, 2, 3, 4], (item: number, index: number) => {
          Row()
            .backgroundColor('#d7d7d7')
            .height(THUMBNAIL_HEIGHT)
            .width(this.thumbnailWidth || 75) // 使用默认宽度
        })
      }
    }
    .justifyContent(FlexAlign.Start)
    .width(this.thumbnailWidth > 0 ? this.getTimelineWidth() : 300) // 使用默认宽度
    .height(THUMBNAIL_HEIGHT)
  }

  @Builder
  timePopupBuilder() {
    Column() {
      Text('已选择时间范围')
        .fontSize(16)
        .fontWeight(FontWeight.Bold)
        .fontColor('#333333')
        .margin({ bottom: 8 })

      Text(`开始时间：${videoCropUtil.formatDuration(this.startTime)}`)
        .fontSize(14)
        .fontColor('#666666')
        .margin({ bottom: 4 })

      Text(`结束时间：${videoCropUtil.formatDuration(this.endTime)}`)
        .fontSize(14)
        .fontColor('#666666')
        .margin({ bottom: 4 })

      Text(`总时长：${videoCropUtil.formatDuration(this.endTime - this.startTime)}`)
        .fontSize(14)
        .fontColor('#007AFF')
        .fontWeight(FontWeight.Medium)
    }
    .padding(16)
    .backgroundColor(Color.White)
    .borderRadius(8)
    .shadow({
      radius: 8,
      color: '#1F000000',
      offsetX: 0,
      offsetY: 2
    })
  }

  //统一的按钮构建器
  @Builder
  buildActionButton(isVIP: boolean) {
    if (isVIP) {
      // VIP用户看到的背景按钮
      Row() {
      }
      .borderRadius(20)
      .backgroundColor('#20000000')
      .linearGradient({
        angle: 180,
        colors: [['#393939', 0.0], ['#000000', 1.0]]
      })
      .height(50)
      .width('80%')
    } else {
      // 非VIP用户看到的广告和会员按钮
      Row({ space: 10 }) {
        AdFreeUseButton({
          AdAction_Type: AdActionType.VideoEditing,
          _width: '100%',
          _height: 50,
          _borderRadius: 20,
          _total: this._total,
          _fontSize: 12,
          _click: () => {
            console.info('DreamShip', '测试点击回调事件')
          }
        })
          .flexShrink(1.5)
          .flexGrow(1)

        OpenMemberVIP({
          _height: 50,
          _borderRadius: 20,
          _fontSize: 12,
          _click: () => {

            this.isVip = true

            promptAction.showToast({ message: '用户已登录', duration: 3000 })

            //省略以下具体实现。
            // if (this.userInfo == null) {
            //   console.log('userinfo==null')
            //   this.isShowSheet = true
            //   promptAction.showToast({ message: '登录后再次点击可进入会员付费页面', duration: 3000 })
            // } else
            // if (!this.isVip) {
            //   console.log('userinfo.VIPLevel==0')
            //   // 跳转到VIP页面
            //   let pathInfo: NavPathInfo = new NavPathInfo('unpaidPage', null)
            //   this.nimblePathStack.pushDestination(pathInfo, true)
            // } else {
            //   console.log('userinfo!=null &&  userinfo.VIPLevel!=0')
            // }
          }
        })
          .flexShrink(1)
          .flexGrow(1.5)
      }
      .width('100%')
    }
  }

  // 速度选择组件
  @Builder
  slider(sp: string) {
    Column() {
      if (this.currentSpeed == sp) {
        Circle()
          .width(10)
          .height(10)
          .stroke('#ff298ae0')
          .strokeWidth(2)
          .fill(Color.Black)
      } else {
        Text('|')
          .fontWeight(900)
          .fontSize(16)
          .fontColor(Color.White)
      }
    }.padding({ left: 1, right: 1 })
    .onClick(() => {
      this.currentSpeed = sp;
    })

  }

  // 选中速率组件
  @Builder
  SelectSpeed() {
    Column({ space: 8 }) {
      Row() {
        Row({ space: 3 }) {
          Text('时长' + this.fullTime / 1000 + 's')
            .fontColor("#ffb0b0b1")
            .fontWeight(400)
            .fontSize(14)
          Image($r('app.media.arrow_right'))
            .width(16)
          Text(((this.fullTime / 1000) * this.speedMap[this.currentSpeed]).toFixed(1) + 's')
            .fontColor(Color.White)
            .fontWeight(400)
            .fontSize(14)
        }

        Row({ space: 4 }) {
          Image($r('app.media.Undo'))
            .width(20)
            .onClick(() => {
              this.currentSpeed = '1x'
            })
          Text('|')
            .fontColor("#ffb0b0b1")
            .fontWeight(400)
            .fontSize(14)
          Image($r("app.media.check"))
            .width(20)
            .onClick(() => {
              if (((this.fullTime / 1000) * this.speedMap[this.currentSpeed]) < 3) {
                promptAction.showToast({ message: '不得小于3秒' })
                return;
              }

              promptAction.showToast({ message: "播放速率为" + this.currentSpeed })
              this.gifSpeed = this.speedMap[this.currentSpeed]
            })
        }
      }.width('100%')
      .justifyContent(FlexAlign.SpaceBetween)

      Row() {
        this.slider('0.1x')
        Line()
          .height(30)
          .startPoint([0.1])
          .endPoint([60, 1])
          .stroke(Color.White)
          .strokeWidth(6)
          .strokeDashArray([2, 2])
        this.slider('1x')
        Line()
          .height(30)
          .startPoint([0.1])
          .endPoint([60, 1])
          .stroke(Color.White)
          .strokeWidth(6)
          .strokeDashArray([2, 2])
        this.slider('2x')
        Line()
          .height(30)
          .startPoint([0.1])
          .endPoint([60, 1])
          .stroke(Color.White)
          .strokeWidth(6)
          .strokeDashArray([2, 2])
        this.slider('5x')
        Line()
          .height(30)
          .startPoint([0.1])
          .endPoint([60, 1])
          .stroke(Color.White)
          .strokeWidth(6)
          .strokeDashArray([2, 2])
        this.slider('10x')
        Line()
          .height(30)
          .startPoint([0.1])
          .endPoint([60, 1])
          .stroke(Color.White)
          .strokeWidth(6)
          .strokeDashArray([2, 2])
        this.slider('100x')
      }
    }
    .padding({
      left: 10,
      right: 10,
      top: 6,
      bottom: 6
    })
    .borderRadius(8)
    .backgroundColor('#252525')
    .width('100%')
    .height('100%') // ==========================================================

  }

  //选中比例的组件
  @Builder
  SelectRatio() {
    Row({ space: 8 }) {
      ForEach(VideoToLiveWallpaperRatioData, (item: VideoToLiveWallpaperRatio, index: number) => {
        Column({ space: 4 }) {
          // 图标
          Image(item.icon)
            .width(22)
            .height(22)
            .fillColor(Color.White)
            .objectFit(ImageFit.Contain)

          // 描述文字
          Text(item.describe)
            .fontColor(Color.White)
            .fontSize(11)
            .fontWeight(this.selectIndex == index ? 600 : 400)
        }
        .width('80%')
        .height('100%')
        .backgroundColor(this.selectIndex == index ? 'rgba(255, 255, 255, 0.1)' : undefined)
        .borderRadius(8)
        .layoutWeight(1)
        .justifyContent(FlexAlign.Center)
        .onClick(() => {
          if (item.aspRatio === -1 && !this.selectedVideoUri) {
            promptAction.showToast({ message: '选中视频后，才可以使用' })
          } else {
            this.selectIndex = index
            this.videoScale = item.aspRatio
            if (item.ratio) {
              this.gifCropRatio = item.ratio
            } else {
              this.gifCropRatio = ''
            }
          }
        })
      })
    }
    .padding({
      left: 10,
      right: 10,
      top: 6,
      bottom: 6
    })
    .borderRadius(8)
    .backgroundColor('#252525')
    .width('100%')
    .height('100%')
  }

  //选中清晰度的组件
  @Builder
  SelectClarity() {
    Row({ space: 8 }) {
      ForEach(GifClarityOptions, (item: GifClarityOption, index: number) => {
        Column({ space: 4 }) {
          // 图标
          Image(item.icon)
            .width(22)
            .height(22)
            .fillColor(Color.White)
            .objectFit(ImageFit.Contain)

          // 描述文字
          Text(item.describe)
            .fontColor(Color.White)
            .fontSize(11)
            .fontWeight(this.claritySelectIndex == index ? 600 : 400)
        }
        .width('80%')
        .height('100%')
        .backgroundColor(this.claritySelectIndex == index ? 'rgba(255, 255, 255, 0.1)' : undefined)
        .borderRadius(8)
        .layoutWeight(1)
        .justifyContent(FlexAlign.Center)
        .onClick(() => {
          this.claritySelectIndex = index
          this.gifClarity = item.value
        })
      })
    }
    .padding({
      left: 10,
      right: 10,
      top: 6,
      bottom: 6
    })
    .borderRadius(8)
    .backgroundColor('#252525')
    .width('100%')
    .height('100%')
  }

  @Builder
  SelectCrop() {
    Row() {
      Stack() {
        Row() {
          this.thumbnailShow()
        }
        .opacity(0.6)
        .justifyContent(FlexAlign.Start)
        .width('100%')
        .height(THUMBNAIL_HEIGHT)

        Row() {
          Row() {
            this.thumbnailShow()
          }
          .clip(true)
          .justifyContent(FlexAlign.Start)
          .width(this.rightWidth)
          .height(THUMBNAIL_HEIGHT)
        }
        .justifyContent(FlexAlign.Start)
        .width('100%')

        Row() {
          Row() {
          }
          .backgroundColor('rgba(0,0,0,0.6)')
          .clip(true)
          .justifyContent(FlexAlign.Start)
          .width(this.leftWidth)
          .height(THUMBNAIL_HEIGHT)
        }
        .justifyContent(FlexAlign.Start)

        Row() {
          Row() {
            this.thumbnailShow()
          }
          .opacity(0.6)
          .clip(true)
          .justifyContent(FlexAlign.Start)
          .width(this.leftWidth)
          .height(THUMBNAIL_HEIGHT)
        }
        .justifyContent(FlexAlign.Start)

        // 中间拖动区域：整体平移 startTime / endTime
        Row() {
        }
        .width(this.rightWidth - this.leftWidth)
        .height(THUMBNAIL_HEIGHT)
        .offset({ x: this.leftWidth })
        .border({ width: { top: 2, bottom: 2 }, color: Color.White })
        .justifyContent(FlexAlign.Center)
        .gesture(
          PanGesture({ fingers: 1, distance: 1 })
            .onActionStart(() => {
              // 只在剪辑模式下且已选择视频时允许拖动
              if (!this.isEditMode || !this.selectedVideoUri) {
                return;
              }
              // 1. 拖动开始时立即暂停视频，防止播放时时间更新干扰
              this.videoController.pause();
              this.isVideoStart = false; // 标记视频已暂停
              // 2. 保存拖动前的相对偏移比例
              this.initialRelative = (this.currentTime - this.startTime) / (this.endTime - this.startTime);
              // 3. 显示时间popup
              this.showTimePopup = true;
            })
            .onActionUpdate(event => {
              // 只在剪辑模式下且已选择视频时允许拖动
              if (!this.isEditMode || !this.selectedVideoUri) {
                return;
              }
              let deltaX = event.offsetX;
              let newLeft = this.leftWidthOrigin + deltaX;
              let newRight = this.rightWidthOrigin + deltaX;

              if (newLeft >= 0 && newRight <= this.getTimelineWidth()) {
                this.leftWidth = newLeft;
                this.rightWidth = newRight;

                // 更新 startTime / endTime
                this.startTime = this.offsetToTime(this.leftWidth);
                this.endTime = this.offsetToTime(this.rightWidth);

                // 更新 currentTime 和 currentOffset
                this.currentTime = this.startTime + this.initialRelative * (this.endTime - this.startTime);
                this.currentOffset =
                  this.leftWidth + this.initialRelative * (this.rightWidth - this.leftWidth);

                // 移除频繁的视频时间更新，减少延迟
                // this.videoController.setCurrentTime(Math.round(this.currentTime / 1000));
              }
            })
            .onActionEnd(async () => {
              // 只在剪辑模式下且已选择视频时处理拖动结束
              if (!this.isEditMode || !this.selectedVideoUri) {
                return;
              }
              this.leftWidthOrigin = this.leftWidth;
              this.rightWidthOrigin = this.rightWidth;
              // 拖动结束后自动从新区域开始播放：先暂停 -> 设置时间 -> 等待100ms -> 开始播放
              this.videoController.pause();
              this.isVideoStart = false;
              this.videoController.setCurrentTime(Math.round(this.startTime / 1000), SeekMode.Accurate);
              await new Promise<void>(r => setTimeout(r, 120));
              this.videoController.start();
              this.isVideoStart = true;
              // 隐藏时间popup
              this.showTimePopup = false;
            })
        )

        // 左边按钮：控制 startTime
        Text('|')
          .fontWeight(800)
          .fontColor(Color.Gray)
          .textAlign(TextAlign.Center)
          .borderRadius({ topLeft: 6, bottomLeft: 6 })
          .backgroundColor(Color.White)
          .height(THUMBNAIL_HEIGHT)
          .width(16)
          .offset({ x: this.leftWidth - 16 })
          .gesture(
            PanGesture({ fingers: 1, distance: 1 })
              .onActionStart(() => {
                // 只在剪辑模式下且已选择视频时允许拖动
                if (!this.isEditMode || !this.selectedVideoUri) {
                  return;
                }
                this.showTimePopup = true;
              })
              .onActionUpdate(async event => {
                // 只在剪辑模式下且已选择视频时允许拖动
                if (!this.isEditMode || !this.selectedVideoUri) {
                  return;
                }
                let newLeftWidth = this.leftWidthOrigin + event.offsetX
                let newStartTime = this.offsetToTime(newLeftWidth)

                // 只在剪辑模式下应用时长限制
                if (this.isEditMode) {
                  // 限制最大时长
                  if (this.endTime - newStartTime > MAX_DURATION) {
                    newStartTime = this.endTime - MAX_DURATION
                    newLeftWidth = this.timeToOffset(newStartTime)
                  }

                  // 限制最小时长
                  if (this.endTime - newStartTime < MIN_DURATION) {
                    newStartTime = this.endTime - MIN_DURATION
                    newLeftWidth = this.timeToOffset(newStartTime)
                  }
                }

                if (newLeftWidth >= 0 &&
                  newLeftWidth + this.oneSecondWidth <= this.rightWidth &&
                this.canDrag) {
                  this.canDrag = false
                  this.leftWidth = newLeftWidth
                  this.startTime = newStartTime
                  this.currentTime = this.startTime
                  this.videoController.pause()
                  this.isVideoStart = false
                  this.videoController.setCurrentTime(Math.round(this.currentTime / 1000), SeekMode.Accurate)
                  this.currentOffset = this.timeToOffset(this.currentTime)
                  this.currentTimeShow = videoCropUtil.formatDuration(this.currentTime)
                  if (!this.isPlayed) {
                    this.pixelMapShow = await this.fetchFrameByTime(this.currentTime * 1000, false)
                  }
                  this.canDrag = true
                }
              })
              .onActionEnd(() => {
                // 只在剪辑模式下且已选择视频时处理拖动结束
                if (!this.isEditMode || !this.selectedVideoUri) {
                  return;
                }
                this.leftWidthOrigin = this.leftWidth
                this.currentOffsetOrigin = this.currentOffset
                this.showTimePopup = false;
              })
              .onActionCancel(() => {
                // 只在剪辑模式下且已选择视频时处理拖动取消
                if (!this.isEditMode || !this.selectedVideoUri) {
                  return;
                }
                this.leftWidthOrigin = this.leftWidth
                this.currentOffsetOrigin = this.currentOffset
                this.showTimePopup = false;
              })
          )

        // 右边按钮：控制 endTime
        Text('|')
          .fontWeight(800)
          .fontColor(Color.Gray)
          .textAlign(TextAlign.Center)
          .borderRadius({ topRight: 6, bottomRight: 6 })
          .backgroundColor(Color.White)
          .height(THUMBNAIL_HEIGHT)
          .width(16)
          .offset({ x: this.rightWidth })
          .gesture(
            PanGesture({ fingers: 1, distance: 1 })
              .onActionStart(() => {
                // 只在剪辑模式下且已选择视频时允许拖动
                if (!this.isEditMode || !this.selectedVideoUri) {
                  return;
                }
                this.showTimePopup = true;
              })
              .onActionUpdate(async event => {
                // 只在剪辑模式下且已选择视频时允许拖动
                if (!this.isEditMode || !this.selectedVideoUri) {
                  return;
                }
                let newRightWidth = this.rightWidthOrigin + event.offsetX
                let newEndTime = this.offsetToTime(newRightWidth)

                // 只在剪辑模式下应用时长限制
                if (this.isEditMode) {
                  // 限制最大时长
                  if (newEndTime - this.startTime > MAX_DURATION) {
                    newEndTime = this.startTime + MAX_DURATION
                    newRightWidth = this.timeToOffset(newEndTime)
                  }

                  // 限制最小时长
                  if (newEndTime - this.startTime < MIN_DURATION) {
                    newEndTime = this.startTime + MIN_DURATION
                    newRightWidth = this.timeToOffset(newEndTime)
                  }
                }

                if (newRightWidth <= this.getTimelineWidth() &&
                  newRightWidth >= this.leftWidth + this.oneSecondWidth &&
                this.canDrag) {
                  this.canDrag = false
                  this.rightWidth = newRightWidth
                  this.endTime = newEndTime
                  this.currentTime = this.endTime
                  this.videoController.pause()
                  this.isVideoStart = false
                  this.videoController.setCurrentTime(Math.round(this.currentTime / 1000), SeekMode.Accurate)
                  this.currentOffset = this.timeToOffset(this.currentTime)
                  this.currentTimeShow = videoCropUtil.formatDuration(this.currentTime)
                  if (!this.isPlayed) {
                    this.pixelMapShow = await this.fetchFrameByTime(this.currentTime * 1000, false)
                  }
                  this.canDrag = true
                }
              })
              .onActionEnd(() => {
                // 只在剪辑模式下且已选择视频时处理拖动结束
                if (!this.isEditMode || !this.selectedVideoUri) {
                  return;
                }
                this.rightWidthOrigin = this.rightWidth
                this.currentOffsetOrigin = this.currentOffset
                this.showTimePopup = false;
              })
              .onActionCancel(() => {
                // 只在剪辑模式下且已选择视频时处理拖动取消
                if (!this.isEditMode || !this.selectedVideoUri) {
                  return;
                }
                this.rightWidthOrigin = this.rightWidth
                this.currentOffsetOrigin = this.currentOffset
                this.showTimePopup = false;
              })
          )

        Row()
          .backgroundColor(Color.White)
          .width(2)
          .height(THUMBNAIL_HEIGHT)
          .offset({ x: this.currentOffset })
      }
      .width('83%')
      .height(THUMBNAIL_HEIGHT)
      .alignContent(Alignment.TopStart)
      .bindPopup(this.showTimePopup, {
        builder: this.timePopupBuilder,
        placement: Placement.Top,
        maskColor: 0x33000000,
        popupColor: Color.White,
        enableArrow: true,
        showInSubWindow: false,
        onStateChange: (e) => {
          if (!e.isVisible) {
            this.showTimePopup = false
          }
        }
      })
      .onClick(() => {
        // 只有选择视频后才能显示时间popup
        if (this.selectedVideoUri) {
          this.showTimePopup = !this.showTimePopup
        }
      })
    }
    .justifyContent(FlexAlign.Center)
    .width('100%')
    .displayPriority(2)
    .flexBasis('auto')
  }

  //非会员看到的小组件和壁纸的按钮

  /**
   * 在获得SaveButton权限后立即保存GIF（解决权限超时问题）
   */
  async saveAsGifWithPermission() {
    if (!this.selectedVideoUri) {
      promptAction.showToast({ message: '请先选择视频' })
      return
    }

    let destFile: fileIo.File | undefined = undefined;
    let albumUri: string = '';

    try {
      // 显示加载提示
      this.isCreatingGif = true;
      this.dialog.open()
      promptAction.showToast({
        message: '正在创建GIF',
        duration: 2000
      });

      // 立即创建相册资源，利用SaveButton的1分钟权限窗口
      console.info('立即创建相册资源以利用权限窗口')
      albumUri = await this.phAccessHelper.createAsset(photoAccessHelper.PhotoType.IMAGE, 'gif');
      console.info('相册资源创建成功：', albumUri)

      // 打开目标文件，获得文件句柄
      destFile = await fileIo.open(albumUri, fileIo.OpenMode.READ_WRITE | fileIo.OpenMode.CREATE);
      console.info('目标文件已打开，可以开始后台生成GIF')

      let cropValue = this.getCropResult()

      // 生成GIF
      const gifPath = await this.createGifWithFFmpeg(
        this.selectedVideoUri,
        this.startTime,
        this.endTime,
        this.gifSpeed,
        cropValue,
        this.gifCropRatio
      );

      // 直接将生成的GIF写入已打开的相册文件
      await this.writeGifToAlbumFile(gifPath, destFile);

      // 删除临时GIF文件
      fileIo.unlinkSync(gifPath);

      console.info('GIF保存到相册成功')
      promptAction.showToast({ message: 'GIF保存成功！' })

      // 保存成功后重置广告次数和界面状态
      this.VideoEditing = 0
      this.isShowSaveOptions = false
    } catch (error) {
      console.error('保存GIF时出错：', error)
      promptAction.showToast({ message: 'GIF保存失败：' + error })
    } finally {
      // 确保文件句柄被正确关闭
      if (destFile) {
        try {
          fileIo.closeSync(destFile);
          console.info('目标文件句柄已关闭')
        } catch (closeError) {
          console.warn('关闭目标文件句柄失败：', closeError)
        }
      }
      // 隐藏加载提示
      this.isCreatingGif = false;
      this.dialog.close()
    }
  }

  /**
   * 获取时间轴总宽度（带除零保护）
   */
  private getTimelineWidth(): number {
    return this.thumbnailWidth * THUMBNAIL_COUNT
  }

  /**
   * 将时间转换为时间轴位置（带除零保护）
   */
  private timeToOffset(time: number): number {
    if (this.fullTime === 0) {
      return 0
    }
    return (time / this.fullTime) * this.getTimelineWidth()
  }

  /**
   * 将时间轴位置转换为时间（带除零保护）
   */
  private offsetToTime(offset: number): number {
    const timelineWidth = this.getTimelineWidth()
    if (timelineWidth === 0) {
      return 0
    }
    return (offset / timelineWidth) * this.fullTime
  }

  /**
   * 将GIF文件内容写入已打开的相册文件
   * @param gifPath 临时GIF文件路径
   * @param destFile 已打开的目标文件句柄
   */
  private async writeGifToAlbumFile(gifPath: string, destFile: fileIo.File) {
    try {
      // 打开源GIF文件
      const srcFile = fileIo.openSync(gifPath, fileIo.OpenMode.READ_ONLY);

      // 读取源文件内容并写入至目的文件
      const bufSize = 4096;
      let readSize = 0;
      const buf = new ArrayBuffer(bufSize);

      let readOptions: ReadOptions = {
        offset: readSize,
        length: bufSize
      };

      let readLen = fileIo.readSync(srcFile.fd, buf, readOptions);
      while (readLen > 0) {
        readSize += readLen;
        const writeOptions: WriteOptions = {
          length: readLen
        };
        fileIo.writeSync(destFile.fd, buf, writeOptions);
        readOptions.offset = readSize;
        readLen = fileIo.readSync(srcFile.fd, buf, readOptions);
      }

      // 关闭源文件
      fileIo.closeSync(srcFile);
      console.info('GIF内容已成功写入相册文件')
    } catch (error) {
      console.error('写入GIF到相册文件失败：', error)
    }
  }

  // 清理资源的统一方法
  private async cleanupResources() {
    // 释放AVImageGenerator资源
    if (this.avImageGenerator) {
      try {
        await this.avImageGenerator.release()
        this.avImageGenerator = undefined
        console.log('已释放AVImageGenerator资源')
      } catch (err) {
        console.warn('释放AVImageGenerator失败：', err)
      }
    }

    // 关闭视频文件
    if (this.fileAlbum) {
      try {
        fileIo.closeSync(this.fileAlbum)
        this.fileAlbum = undefined
        console.log('已关闭视频文件句柄')
      } catch (err) {
        console.warn('关闭视频文件失败：', err)
      }
    }

    // 清理临时目录中的旧文件
    try {
      const tempDir = this.context.tempDir
      const files = fileIo.listFileSync(tempDir)
      for (const file of files) {
        if (file.startsWith('temp_cover_') && file.endsWith('.jpg')) {
          const filePath = tempDir + '/' + file
          try {
            fileIo.unlinkSync(filePath)
            console.log('已清理临时封面文件：', filePath)
          } catch (cleanupErr) {
            console.warn('清理临时封面文件失败：', filePath, cleanupErr)
          }
        }
      }
    } catch (err) {
      console.warn('清理临时目录失败：', err)
    }

    // 清理剪辑视频文件
    try {
      const outputVideoPath = `${VideoUtils.videoDir}/OutputVideo.mp4`
      if (fileIo.accessSync(outputVideoPath)) {
        fileIo.unlinkSync(outputVideoPath)
        console.log('已清理剪辑视频文件：', outputVideoPath)
      }
    } catch (err) {
      console.warn('清理剪辑视频文件失败：', err)
    }
  }

  // 保存为动态壁纸
  private async saveAsMovingPhoto() {
    promptAction.showToast({
      message: '动态壁纸创建按钮已点击，暂不执行功能',
      duration: 3000
    })
  }

  /**
   * @param srcFilePath 源视频文件路径
   * @param sTime 开始时间（毫秒）
   * @param eTime 结束时间（毫秒）
   */
  private createGifWithFFmpeg(srcFilePath: string, sTime: number, eTime: number, speed: number, cropInfo: videoRect,
    gifCropRatio?: string): Promise<string> {
    return new Promise((resolve, reject) => {
      try {
        // 1. 首先将相册URI复制到沙箱目录（参考VideoCreateGif.ets的做法）
        const copiedFilePath = this.copyVideoToSandbox(srcFilePath);
        if (!copiedFilePath) {
          reject(new Error('复制视频文件到沙箱失败'));
          return;
        }

        let dst = getContext(this).cacheDir + '/output' + Date.now() + '.gif';
        let startTime = getTimeString(sTime);
        let duration = Math.floor((eTime - sTime) / 1000);

        // 添加详细的调试信息
        console.log('=== GIF生成调试信息 ===');
        console.log('原始URI路径：', srcFilePath);
        console.log('复制后文件路径：', copiedFilePath);
        console.log('开始时间（毫秒）：', sTime);
        console.log('结束时间（毫秒）：', eTime);
        console.log('时长（毫秒）：', eTime - sTime);
        console.log('转换后开始时间：', startTime);
        console.log('转换后时长（秒）：', duration);
        console.log('输出文件路径：', dst);

        // 检查参数有效性
        if (duration <= 0) {
          reject(new Error('时长无效：' + duration + '秒，请检查开始和结束时间'));
          return;
        }

        let callBack: ICallBack = {
          callBackResult(code: number) {
            console.log('FFmpeg处理结果代码：', code);
            if (code === 0) {
              console.log('GIF生成成功：', dst);
              resolve(dst);
            } else {
              console.error('FFmpeg处理失败，错误代码：', code);
              reject(new Error('FFmpeg处理失败，错误代码：' + code));
            }
          }
        }

        // 构建视频滤镜链 - 修复滤镜链语法
        let videoFilters = '';

        // 根据清晰度设置最终输出尺寸
        const finalScale = `${this.gifClarity}:-1:flags=lanczos`;

        // 添加按比例剪裁功能 - 使用scale+crop组合确保兼容性
        if (gifCropRatio) {
          let scaleAndCropFilter = '';
          switch (gifCropRatio) {
            case '4:3':
              // 4:3比例 - 根据清晰度动态计算裁剪尺寸
              const crop43Width = Math.round(this.gifClarity * 4 / 3);
              scaleAndCropFilter =
                `scale=${crop43Width}:${this.gifClarity}:force_original_aspect_ratio=increase,crop=${crop43Width}:${this.gifClarity}`;
              break;
            case '16:9':
              // 16:9比例 - 根据清晰度动态计算裁剪尺寸
              const crop169Width = Math.round(this.gifClarity * 16 / 9);
              scaleAndCropFilter =
                `scale=${crop169Width}:${this.gifClarity}:force_original_aspect_ratio=increase,crop=${crop169Width}:${this.gifClarity}`;
              break;
            case '1:1':
              // 1:1正方形 - 正方形裁剪
              scaleAndCropFilter =
                `scale=${this.gifClarity}:${this.gifClarity}:force_original_aspect_ratio=increase,crop=${this.gifClarity}:${this.gifClarity}`;
              break;
            case '9:16':
              // 9:16竖屏比例 - 根据清晰度动态计算裁剪尺寸
              const crop916Width = Math.round(this.gifClarity * 9 / 16);
              scaleAndCropFilter =
                `scale=${crop916Width}:${this.gifClarity}:force_original_aspect_ratio=increase,crop=${crop916Width}:${this.gifClarity}`;
              break;
            case '21:9':
              // 21:9电影比例 - 根据清晰度动态计算裁剪尺寸
              const crop219Width = Math.round(this.gifClarity * 21 / 9);
              scaleAndCropFilter =
                `scale=${crop219Width}:${this.gifClarity}:force_original_aspect_ratio=increase,crop=${crop219Width}:${this.gifClarity}`;
              break;
            default:
            // 自定义比例 - 使用scale+crop组合
              const ratioArray = gifCropRatio.split(':').map(Number);
              const w = ratioArray[0];
              const h = ratioArray[1];
              if (w && h) {
                // 根据清晰度和比例计算裁剪尺寸
                const cropWidth = Math.round(this.gifClarity * w / h);
                const cropHeight = this.gifClarity;
                scaleAndCropFilter =
                  `scale=${cropWidth}:${cropHeight}:force_original_aspect_ratio=increase,crop=${cropWidth}:${cropHeight}`;
              }
          }
          videoFilters =
            `${scaleAndCropFilter},setpts=${speed}*PTS,fps=15,scale=${finalScale},split[s0][s1];[s0]palettegen[p];[s1][p]paletteuse`;
          // 有裁剪时的完整滤镜链：缩放裁剪 -> 帧率 -> 最终缩放 -> 调色板
          // videoFilters =
          //   `${scaleAndCropFilter},[0:v]setpts=${speed}*PTS,fps=15,scale=${finalScale},split[s0][s1];[s0]palettegen[p];[s1][p]paletteuse`;
          console.log("zhao 比例裁切")
        } else if (cropInfo.width != 0) {
          videoFilters =
            `[0:v]crop=${cropInfo.width}:${cropInfo.height}:${cropInfo.x}:${cropInfo.y},setpts=${speed}*PTS,fps=15,scale=${finalScale},split[s0][s1];[s0]palettegen[p];[s1][p]paletteuse`;
        } else {
          // 无裁剪时的滤镜链：帧率 -> 缩放 -> 调色板
          videoFilters =
            `[0:v]setpts=${speed}*PTS,fps=15,scale=${finalScale},split[s0][s1];[s0]palettegen[p];[s1][p]paletteuse`;
        }

        // 使用优化的FFmpeg命令生成高质量GIF
        let command = `ffmpeg -i ${copiedFilePath} -ss ${startTime} -t ${duration} -vf "${videoFilters}" ${dst}`;

        console.log('FFmpeg命令：', command);
        console.log('========================');
        MP4Parser.ffmpegCmd(command, callBack);
      } catch (error) {
        console.error('创建GIF时发生错误：', error);
        reject(error);
      }
    });
  }

  /**
   * 将视频文件复制到沙箱目录（参考VideoCreateGif.ets的copyMediaFile方法）
   * @param sourcePath 源文件路径（相册URI）
   * @returns 沙箱中的文件路径
   */
  private copyVideoToSandbox(sourcePath: string): string {
    try {
      // 生成目标文件路径，使用时间戳避免文件名冲突
      const timestamp = new Date().getTime();
      const filename = `video_${timestamp}.mp4`;
      const targetPath: string = getContext(this).filesDir + "/" + filename;

      // 检查目标路径是否已存在
      if (fileIo.accessSync(targetPath)) {
        return targetPath;
      }

      // 打开源文件
      const sourceFile = fileIo.openSync(sourcePath, fileIo.OpenMode.READ_ONLY);
      // 创建目标文件
      const destFile = fileIo.openSync(targetPath, fileIo.OpenMode.CREATE | fileIo.OpenMode.READ_WRITE);

      const buffSize = 4096;
      const buffer = new ArrayBuffer(buffSize);
      let len = 0;

      // 循环读取和写入数据
      while ((len = fileIo.readSync(sourceFile.fd, buffer, { length: buffSize })) > 0) {
        fileIo.writeSync(destFile.fd, buffer, { length: len });
      }

      // 关闭文件
      fileIo.closeSync(sourceFile.fd);
      fileIo.closeSync(destFile.fd);

      console.log('视频文件复制成功：', targetPath);
      return targetPath;
    } catch (error) {
      console.error('复制视频文件失败:', error);
      return '';
    }
  }
}

@Extend(Text)
function timeText() {
  .fontSize(12)
  .fontColor(Color.White)
  .fontWeight(600)
}

