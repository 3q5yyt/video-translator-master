import { BreakpointTypeEnum } from '@hamo/tools';

/**
 * @author: qhj
 * @date: 2024/8/1 23:31
 * @description:
 * @version:
* @ 跳转登录检测Vip状态，或跳转到VIP付款页面
 */

@Preview
@Component
export struct OpenMemberVIP {
  @StorageProp('currentBreakpoint') currentBreakpoint: string = BreakpointTypeEnum.MD;
  _width?: string | number;
  _height?: string | number;
  _fontSize?: number | string | Resource = 16
  _borderRadius?: number = 30
  _click?: () => void = () => {
  }

  aboutToAppear(): void {
  }

  build() {
    Stack() {
      Image($r("app.media.openVipButton_back"))
        .width('100%')
        .height('100%')
        .objectFit(ImageFit.Fill)
      Row() {
        Image($r("app.media.openVipButton_left"))
          .height('100%')
          .objectFit(ImageFit.Contain)
        Text() {
          Span('开通VIP会员\n')
            .fontSize(this._fontSize)
            .fontColor('#232321')
          Span('丰富组件、壁纸任意用')
            .fontSize(8)
            .fontColor('#866649')
        }
        .textAlign(TextAlign.Start)

        // Blank()
        Row() {
          Image($r("app.media.openVipButton_right"))
            .height('35%')
            .objectFit(ImageFit.Contain)
          Image($r("app.media.openVipButton_right"))
            .height('35%')
            .objectFit(ImageFit.Contain)
            .visibility(Visibility.Hidden)
        }

      }
      .width('100%')
      .height('100%')
      .alignItems(VerticalAlign.Center)
      .justifyContent(FlexAlign.SpaceBetween)

    }
    .width(this._width)
    .height(this._height)

    .borderRadius(this._borderRadius)
    .clip(true)

    .onClick(() => {
      if (this._click) {
        this._click()
      }
    })
  }
}