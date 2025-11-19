
import { AdActionType } from 'globalclass';


const TAG = 'DreamShip FreeUse Button,基于鲸鸿动能';


/**
 * 点击看激励广告的按钮
 */
@Preview
@Component
export struct AdFreeUseButton {
  // 观看使用按钮组件参数
  // @Link _id: string //= 'btn'
  _width?: string | number = 190
  _height?: string | number = 50
  _borderRadius?: number = 30
  // @State _current: number = 0
  @Link _total: number // = 2
  _fontSize?: number | string | Resource = 16
  @Prop AdAction_Type: AdActionType
  @StorageLink(`adType_${AdActionType.VideoEditing}`) VideoEditing: number = 0



  // 观看使用按钮组件回调
  _click?: () => void = () => {

  }



  build() {
    Row() {
      // 左边图标
      Column() {
        Image($r('app.media.icon_freeUse'))
          .height('33%')
          .aspectRatio(1)
          .objectFit(ImageFit.Contain)
      }
      .margin({ left: (this._borderRadius ?? 20) / 2 })
      .justifyContent(FlexAlign.Center)
      .height('100%')
      .displayPriority(3)

      Blank()
        .displayPriority(1)
      // 中间文本
      Text('观看使用')
        .fontColor('#017CFE')
        .textAlign(TextAlign.Center)
        .fontWeight(500)
        .fontSize(this._fontSize)
        .displayPriority(2)
      Blank()
        .displayPriority(1)
      // 右边文本
      Text(`(${this.VideoEditing}/${this._total})`)
        .fontColor('#017CFE')
        .margin({ right: (this._borderRadius ?? 20) / 2 })
        .fontWeight(500)
        .fontSize(this._fontSize)
        .height('100%')
        .displayPriority(3)

    }
    .width(this._width)
    .height(this._height)
    .borderRadius(this._borderRadius)
    .alignItems(VerticalAlign.Center)
    .justifyContent(FlexAlign.Center)
    // .padding(5)
    .backgroundColor('#F0F7FF')
    .onClick(() => {
      this.VideoEditing++
    })
  }
}




