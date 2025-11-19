
import { mediaquery, router } from '@kit.ArkUI';

import { BreakpointSystem, BreakpointTypeEnum } from '@hamo/tools';
import { ConfigurationConstant } from '@kit.AbilityKit';






PersistentStorage.persistProp(`totalAdRequest`, 2)


PersistentStorage.persistProp('darkModel', 2) //深色模式




/**
 * 开屏的隐私协议弹窗
 */
@Entry
@Component
struct Splash {
  // 从AppStorage获取当前断点值
  @StorageProp('currentBreakpoint') currentBreakpoint: string = BreakpointTypeEnum.MD;

  //深色模式监听器
  listener: mediaquery.MediaQueryListener = mediaquery.matchMediaSync('(dark-mode: false)');
  //断点监听器
  private breakpointSystem: BreakpointSystem = new BreakpointSystem();



  /**
   *   监听深色模式变化
   */

  aboutToAppear(): void {


    //调整颜色模式

    let ColorModeIndex = AppStorage.get<number>('darkModel')
    if (ColorModeIndex == 0) {
      getContext().getApplicationContext().setColorMode(ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT);
    } else if (ColorModeIndex == 1) {
      getContext().getApplicationContext().setColorMode(ConfigurationConstant.ColorMode.COLOR_MODE_DARK);
    } else {
      getContext().getApplicationContext().setColorMode(ConfigurationConstant.ColorMode.COLOR_MODE_NOT_SET);
    }


    //启动对深色模式的监听
    this.listener.on('change', (mediaQueryResult: mediaquery.MediaQueryResult) => {
      this.darkModeListener(mediaQueryResult)
    });

    this.breakpointSystem.register();



      router.replaceUrl({
        url: `pages/Index`
      })
  }

  darkModeListener(mediaQueryResult: mediaquery.MediaQueryResult) {
    if (mediaQueryResult.matches as boolean) { // 若设备为横屏状态，更改相应的页面布局
      AppStorage.setOrCreate('isDarkMode', false)
      console.log('深色模式便成为false')
    } else {
      AppStorage.setOrCreate('isDarkMode', true)
      console.log('深色模式便成为true')
    }
  }

  build() {
    Stack() {
      //用户未同意协议时显示的背景图
      Image((this.currentBreakpoint == BreakpointTypeEnum.SM) ? $r('app.media.welcomePageImage') :
      $r('app.media.welcomePageImageBig'))
        .objectFit(ImageFit.Cover)
        .height('100%')
        .width('100%')

    }
    .backgroundColor('rgba(0,0,0,0.4)')
    .height('100%')
    .width('100%')

  }
}