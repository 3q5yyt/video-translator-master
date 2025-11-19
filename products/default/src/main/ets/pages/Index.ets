import { BreakpointSystem, BreakpointTypeEnum } from '@hamo/tools';

import { curves } from '@kit.ArkUI';
import { common } from '@kit.AbilityKit';


import { toolPage, VideoToAnimation } from 'toolbox';
import { myBreakpoint } from 'globalclass';


// 通过getShared接口获取stage共享的LocalStorage实例
let storage = LocalStorage.getShared()

const snapShotName = 'homePage'

@Entry(storage)
@Component
struct Index {
  bottomRectHeight: string = AppStorage.get<number>('bottomRectHeight') + 'px';
  topRectHeight: string = AppStorage.get<number>('topRectHeight') + 'px';
  @State currentIndex: number = 0;
  @Provide('stackMode') stackMode: boolean = true;
  // 页面路由栈
  @Provide('nimblePathStack') @Watch('cheakPath') nimblePathStack: NavPathStack = new NavPathStack();
  @LocalStorageLink('needResetLocation') needResetLocation: boolean = false;
  // 从AppStorage获取当前断点值
  @StorageProp('currentBreakpoint') currentBreakpoint: string = BreakpointTypeEnum.MD;
  @StorageProp('todayNumber') todayNumber: number = 0 //记录日期，日期变更时触发刷新
  @State isEnabled: boolean = true;
  // @StorageProp('wallpaperView') wallpaperView: boolean = false //壁纸的转场动画有没有执行
  @State Stabilization: number = -1 //定时器防抖
  @StorageProp('allowShake') allowShake: boolean = true //判断震动有没有开启
  @StorageProp('myBreakPointData') @Watch('myBreakPoint') breakPointData: string = '' //获取自定义断点
  @State isOnlineNetwork: boolean = true; //断网管理
  @State mainWidth: Length = '100%'; //nav的宽度
  private context: common.UIAbilityContext = getContext(this) as common.UIAbilityContext;
  private tabsController: TabsController = new TabsController();
  //断点监听器
  private breakpointSystem: BreakpointSystem = new BreakpointSystem(); //自定义弹窗

  myBreakPoint() {
    if (this.breakPointData == myBreakpoint.half || this.breakPointData == myBreakpoint.oneQuarter) {
      animateTo({ duration: 300, curve: Curve.EaseInOut }, () => {
        this.tabsController.setTabBarTranslate({ x: 0, y: 80 })
      })
    } else {
      animateTo({ duration: 300, curve: Curve.EaseInOut }, () => {
        this.tabsController.setTabBarTranslate({ x: 0, y: 0 })
      })
    }
  }

  cheakPath() {

    let cardEditPagePath = this.nimblePathStack.getIndexByName('cardEditPage')
    let bannerPreviewPath = this.nimblePathStack.getIndexByName('bannerPreviewPage')
    let searchPage = this.nimblePathStack.getIndexByName('searchPage')
    console.log('检测页面栈' + JSON.stringify(cardEditPagePath))
    if (cardEditPagePath.indexOf(0) != -1 || bannerPreviewPath.indexOf(0) != -1 || searchPage.indexOf(0) != -1) {
      this.getUIContext().animateTo({
        duration: 300,
        curve: curves.cubicBezierCurve(0.50, 0.00, 0.77, 1)
      }, () => {
        if (this.currentIndex == 0) {
          this.mainWidth = '50%'
        } else {
          this.mainWidth = '100%'

        }
      })
    } else {
      this.getUIContext().animateTo({
        duration: 300,
        curve: curves.cubicBezierCurve(0.50, 0.00, 0.77, 1)
      }, () => {
        this.mainWidth = '100%'
      })
    }


  }

  @Builder
  nimblePageRouter(name: string) {
    if (name === 'VideoToAnimation') {
      VideoToAnimation()
    }


  }

  aboutToAppear() {
    this.breakpointSystem.register();
  }

  aboutToDisappear(): void {
    this.breakpointSystem.unregister();
  }

  build() {
    Navigation(this.nimblePathStack) {

      Tabs({
        controller: this.tabsController,
        index: this.currentIndex
      }) {


        TabContent() {
          toolPage()
        }
        .tabBar(this.tabBarBuilder('工具', 2, $r('app.media.Toolbox'),
          $r('app.media.UnToolbox')))

      }
      .barOverlap(this.currentBreakpoint == BreakpointTypeEnum.SM ? true : false) //背景模糊
      .barHeight(this.breakPointData == myBreakpoint.threeQuarters || this.breakPointData == myBreakpoint.full ?
      this.getValue() : 0)
      .barWidth(this.breakPointData == myBreakpoint.threeQuarters || this.breakPointData == myBreakpoint.full ?
        this.currentBreakpoint == BreakpointTypeEnum.LG ? 80 : 'auto' : 0)
      // .barHeight(this.getValue())
      // .barWidth(this.currentBreakpoint == BreakpointTypeEnum.LG ? 80 : 'auto')
      .scrollable(false)
      .barPosition(this.currentBreakpoint === BreakpointTypeEnum.SM ? BarPosition.End : BarPosition.Start)
      .vertical(this.currentBreakpoint === BreakpointTypeEnum.SM ? false : true)
      .barBackgroundColor(this.currentBreakpoint === BreakpointTypeEnum.LG ? $r('app.color.assistColor') : '')
      .backgroundColor($r('app.color.assistColor'))
      .height('100%')
      .width('100%')
      .onChange((Index) => {
        AppStorage.setOrCreate('currentTTabIndex', this.currentIndex) //保存tab索引，用来刷新我的页面动画，避免从桌面进入到我的页面的时候动画卡顿
        this.currentIndex = Index
        this.tabsController.changeIndex(Index) //通过控制器来切换tab，提升响应速度
        console.log('当前tab索引为：' + Index)
        this.cheakPath()
        if (Index != 0) {
          this.mainWidth = '100%'
        }
      })
      .onAnimationStart((index: number, targetIndex: number, event: TabsAnimationEvent) => {
        if (index === targetIndex) {
          return
        }
      })

    }
    .id(snapShotName)
    .hideTitleBar(true)
    .onNavigationModeChange((res) => {
      AppStorage.setOrCreate('homePageNavigationMode', res)
    })
    .mode(NavigationMode.Stack)
    .navBarWidth('100%')
    .mode( /*(*/this.currentIndex == 0/* && this.isCardOnTop == true)*/ ? NavigationMode.Auto : NavigationMode.Stack)
    // .navBarWidth('65%')
    .navDestination(this.nimblePageRouter)
    .navBarWidth( /*(this.currentIndex == 0 && this.isCardOnTop == true) ? '50%' : '100%'*/this.mainWidth)
    // .navBarWidth(this.mainWidth)
    // .animation({ duration: 300 })
    .enabled(this.isEnabled)
  }

  @Builder
  tabBarBuilder(title: string, targetIndex: number, selectedIcon: Resource, unselectIcon: Resource) {
    Column(this.currentBreakpoint == BreakpointTypeEnum.LG ? { space: 10 } : { space: 5 }) {

        Image(this.currentIndex === targetIndex ? selectedIcon : unselectIcon)
          .width(this.currentBreakpoint == BreakpointTypeEnum.LG ? 26 : 24)
          .height(this.currentBreakpoint == BreakpointTypeEnum.LG ? 26 : 24)

      Text(title)
        .fontFamily('HarmonyHeiTi-Medium')
        .fontSize(this.currentBreakpoint == BreakpointTypeEnum.LG ? 12 : 10)
        .fontColor(this.currentIndex === targetIndex ? $r('app.color.IconColor_Start') : $r('app.color.IconColor03'))
        .textAlign(TextAlign.Center)
        .lineHeight(14)
        .fontWeight(500)
      // .fontFamily('fontMediumText')
      // .margin({ bottom: 15 })
    }
    .clickEffect({ level: ClickEffectLevel.MIDDLE, scale: 0.7 })
    .padding({ bottom: this.bottomRectHeight, top: 10 })
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
    .onClick(async () => {



      this.stackMode = true;
      this.nimblePathStack.clear()
      this.currentIndex = targetIndex;
      this.tabsController.changeIndex(targetIndex);
    })
  }

  getValue() {
    if (this.currentBreakpoint === BreakpointTypeEnum.SM) { // 外层条件
      return 80
    } else {
      return '50%'; // 非 SM 断点
    }
  }
}



