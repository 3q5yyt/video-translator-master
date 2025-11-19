import { AbilityConstant, errorManager, UIAbility, Want } from '@kit.AbilityKit';
import { FaultLogger, hilog } from '@kit.PerformanceAnalysisKit';
import { display, window } from '@kit.ArkUI';
import { BusinessError } from '@kit.BasicServicesKit';

import { ImageKnife } from '@ohos/imageknife';
import { MemoryLruCache } from '@ohos/imageknife/src/main/ets/cache/MemoryLruCache';
import { DefaultEngineKey } from '@ohos/imageknife/src/main/ets/key/DefaultEngineKey';
import { myBreakpoint } from 'globalclass';


//初始化持久化
PersistentStorage.persistProp<number>('myFishNumber', 0) //缓存用户的的摸鱼数量


let errorManagerID = -1


export default class EntryAbility extends UIAbility {
  private currentWindowStage: window.WindowStage | null = null;
  //保存断点的值
  private curBp: string = ''

  //卡片带过来的信息
  private JumpInformation: string = ''

  //判断设备是不是pc
  private isPc: boolean = false


  onCreate(want: Want, launchParam: AbilityConstant.LaunchParam): void {


    if (want.parameters?.params) {
      let params: Record<string, string> = JSON.parse(want.parameters.params as string);
      this.JumpInformation = params.targetPage as string
      console.log('卡片上面的信息为：', this.JumpInformation);




    }


    //错误观测器,遇到未知的ArkTs错误,程序不会闪退
    errorManagerID = errorManager.on('error', {
      async onUnhandledException(errMsg) {
        const list = await FaultLogger.query(FaultLogger.FaultType.JS_CRASH)
        const item = list[0]
        // AlertDialog.show({
        //   message: '程序发生未知错误,请重启软件,并联系我们~' + JSON.stringify(errMsg, null, 2)
        // })
        // AlertDialog.show({
        //   message: '错误信息为:' + JSON.stringify(item, null, 2)
        // })
      }
    })


    hilog.info(0x0000, 'testTag', '%{public}s', 'Ability onCreate');


    AppStorage.setOrCreate('context', this.context) //保存上下文信息，便于初始化首选项，储存历史记录

    // 初始化图片加载库
    let memoryCache = new MemoryLruCache(2000, 1024 * 1024 * 1024);
    ImageKnife.getInstance().initMemoryCache(memoryCache)
    ImageKnife.getInstance().setEngineKeyImpl(new DefaultEngineKey())
  }


  onNewWant(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    if (want.parameters?.params) {
      let params: Record<string, string> = JSON.parse(want.parameters.params as string);
      this.JumpInformation = params.targetPage as string
      console.log('卡片上面的信息为：', this.JumpInformation);


    }


  }

  onDestroy(): void {
    hilog.info(0x0000, 'testTag', '%{public}s', 'Ability onDestroy');
    errorManager.off('error', errorManagerID)
  }

  onWindowStageCreate(windowStage: window.WindowStage) {

    //判断设备是否为pc
    if (this.hasEverBeenLargeDevice()) {
      this.isPc = true
      AppStorage.setOrCreate('myBreakPointData', myBreakpoint.full)
    } else {
      this.isPc = false
    }

    /*pages/Splash*/
    windowStage.getMainWindow().then((windowObj) => {
      // 获取应用启动时的窗口尺寸
      this.updateBreakpoint(windowObj.getWindowProperties().windowRect.width)


      // 注册回调函数，监听窗口尺寸变化
      windowObj.on('windowSizeChange', (windowSize) => {
        const res = this.updateBreakpoint(windowSize.width)
        console.log('当前的断点是', res, '当前设备是否为pc', this.isPc);
        if (this.isPc == false) {
          this.updateBreakpointByHeight(Number(windowSize.height))
        }
        console.log('窗口变化了', windowSize.width, windowSize.height);
      })
    })


    // Main window is created, set main page for this ability
    hilog.info(0x0000, 'testTag', '%{public}s', 'Ability onWindowStageCreate');


    // 全屏显示
    requestFullScreen(windowStage, this.context);
    // 设置手机和平板的屏幕显示状态
    // changeWindow(this.context)
    AppStorage.setOrCreate<window.WindowStage>("windowStage", windowStage) //as window.WindowStage;

    if (this.currentWindowStage === null) {
      this.currentWindowStage = windowStage;
      AppStorage.setOrCreate('windowsStageForAd', windowStage) //广告需要此windowsStage
    }

    //有formID，是卡片二次点击，进入编辑页
    let storage: LocalStorage | null = null


    /*pages/Splash*/
    windowStage.loadContent('pages/Splash', storage == null ? null : storage, (err) => {
      if (err.code) {
        hilog.error(0x0000, 'testTag', 'Failed to load the content. Cause: %{public}s', JSON.stringify(err) ?? '');
        return;
      }
      hilog.info(0x0000, 'testTag', 'Succeeded in loading the content.');

    });

    ImageKnife.getInstance().initFileCache(this.context, 200, 256 * 1024 * 1024)
    // if(FormId!=null){
    //   console.log('进入启动节点')
    //   let para:Record<string, string|number> = { 'cardEditType':cardEditType.secondEdit,'formId': FormId };
    //   let storage: LocalStorage = new LocalStorage(para);
    //   windowStage.loadContent('pages/Index',storage==null?null:storage, (err) => {
    //     if (err.code) {
    //       hilog.error(0x0000, 'testTag', 'Failed to load the content. Cause: %{public}s', JSON.stringify(err) ?? '');
    //       return;
    //     }
    //     hilog.info(0x0000, 'testTag', 'Succeeded in loading the content.');
    //   });
    // }else{    //没有formID，是新开版本，直接进入报错页
    //   console.log('进入普通节点')
    //   windowStage.loadContent('pages/Splash', (err) => {
    //     if (err.code) {
    //       hilog.error(0x0000, 'testTag', 'Failed to load the content. Cause: %{public}s', JSON.stringify(err) ?? '');
    //       return;
    //     }
    //     hilog.info(0x0000, 'testTag', 'Succeeded in loading the content.');
    //   });
    // }
  }

  onWindowStageDestroy(): void {
    // Main window is destroyed, release UI related resources
    hilog.info(0x0000, 'testTag', '%{public}s', 'Ability onWindowStageDestroy');
  }

  onForeground(): void {
    // Ability has brought to foreground
    hilog.info(0x0000, 'testTag', '%{public}s', 'Ability onForeground');
  }

  onBackground(): void {
    // Ability has back to background
    hilog.info(0x0000, 'testTag', '%{public}s', 'Ability onBackground');

  }


  // 根据当前窗口尺寸更新断点
  private updateBreakpoint(windowWidth: number): string {
    try {
      //  核心代码1: 将长度的单位由px换算为vp，（px除以像素密度得到vp）
      let windowWidthVp = windowWidth / display.getDefaultDisplaySync().densityPixels
      let newBp: string = ''
      //  核心代码2: 基于窗口宽度vp值，判断当前设备属于哪个断点范围
      if (windowWidthVp < 320) {
        newBp = 'xs'
      } else if (windowWidthVp < 600) {
        newBp = 'sm'
      } else if (windowWidthVp < 840) {
        newBp = 'md'
      } else if (windowWidthVp < 1080) {
        newBp = 'lg'
      } else {
        newBp = 'xl'
      }
      if (this.curBp !== newBp) {
        this.curBp = newBp
        // 核心代码3: 使用状态变量记录当前断点值 --暂时不用,避免与项目中的断点冲突
        // AppStorage.setOrCreate('currentBreakpoint', this.curBp)
        // currentBreakpoint
        console.log('窗口的变化为:' + this.curBp);
      }
      return newBp
    } catch (err) {
      return 'sm'
    }
  }

  //根据窗口的高度自定义的断点工具
  private updateBreakpointByHeight(windowHeight: number): void {
    //如果有值才执行
    if (windowHeight) {
      let myBreakPointData: myBreakpoint = myBreakpoint.full
      if (windowHeight < 900) { //屏幕小于1000是1/4屏
        myBreakPointData = myBreakpoint.oneQuarter
      } else if (windowHeight < 1500) { //屏幕高度小于1500是半屏
        myBreakPointData = myBreakpoint.half
      } else if (windowHeight < 2000) { //屏幕高度小于2000是3/4屏
        myBreakPointData = myBreakpoint.threeQuarters
      } else { //其他是全屏
        myBreakPointData = myBreakpoint.full
      }
      AppStorage.setOrCreate('myBreakPointData', myBreakPointData)
      console.log('当前的设备是属于:' + AppStorage.get('myBreakPointData'));
    }
  }

  /**
   * 判断设备是否曾经等于或大于xl断点(xl断点是pc)
   * @returns 如果设备曾经达到过xl断点则返回true，否则返回false
   */
  private hasEverBeenLargeDevice(): boolean {
    try {
      // 获取当前窗口宽度
      const windowWidth = display.getDefaultDisplaySync().width;
      // 将宽度从px转换为vp
      const windowWidthVp = windowWidth / display.getDefaultDisplaySync().densityPixels;
      // 判断是否等于或大于xl断点(1080vp)
      const isCurrentlyLarge = windowWidthVp >= 1080;

      // 如果当前是lg断点，则永久记录这个状态
      if (isCurrentlyLarge) {
        return true;
      }
      // 如果不是lg断点，记录为false（可能以后会变成lg）
      return false;
    } catch (err) {
      console.log("hasEverBeenLargeDevice check failed: " + JSON.stringify(err));
      return false; // 出错时默认返回false
    }
  }
}

/**
 * 设置页面全屏显示，并获取上下的避让区宽度
 * @param windowStage
 * @param context
 */
function requestFullScreen(windowStage: window.WindowStage, context: Context): void {
  windowStage.getMainWindow((err: BusinessError, data: window.Window) => {
    if (err.code) {
      return;
    }
    // 1. 设置窗口全屏
    let windowClass: window.Window = data;
    windowClass.setWindowLayoutFullScreen(true);

    //
    // windowStage: window.windows = AppStorage.get("windowStage") as window.WindowStage;
    // // // 获取主窗口的方式
    // mainWin: window.Window = windowStage.getMainWindowSync();


    // 2. 获取布局避让遮挡的区域
    let toptype = window.AvoidAreaType.TYPE_SYSTEM; // 以导航条避让为例
    let topavoidArea = windowClass.getWindowAvoidArea(toptype);
    // let bottomRectHeight = avoidArea.bottomRect.height; // 获取到导航条区域的高度
    let topRectHeight = topavoidArea.topRect.height; // 获取到导航条区域的高度
    AppStorage.setOrCreate('topRectHeight', topRectHeight);

    let bottomtype = window.AvoidAreaType.TYPE_NAVIGATION_INDICATOR; // 以导航条避让为例
    let bottomavoidArea = windowClass.getWindowAvoidArea(bottomtype);
    let bottomRectHeight = bottomavoidArea.bottomRect.height; // 获取到导航条区域的高度
    AppStorage.setOrCreate('bottomRectHeight', bottomRectHeight);


  });
}




