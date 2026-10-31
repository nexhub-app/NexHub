import { image } from '@kit.ImageKit';

let storage: LocalStorage = new LocalStorage();

/** 大数字卡（2*2）：本周阅读时长，一眼看清。 */
@Entry(storage)
@Component
export struct WidgetCardBigNumber {
  @LocalStorageProp('bg') bg: image.PixelMap | null = null;
  @LocalStorageProp('bg_color') bgColor: string = '#FFFFFF';
  @LocalStorageProp('color_primary') colorPrimary: string = '#0EA5E9';
  @LocalStorageProp('label_stats') label: string = '统计';
  @LocalStorageProp('stats_week_minutes') minutes: string = '0';
  @LocalStorageProp('minute_unit') unit: string = '分钟';
  @LocalStorageProp('stats_text') detail: string = '';
  @LocalStorageProp('lifetime_text') lifetime: string = '';

  build() {
    Stack() {
      // ID_COLOR_BACKGROUND_LAYER：外层用系统背景色，随深浅色自动切换。
      Stack() {
      if (this.bg != null) {
        Image(this.bg)
          .width('100%')
          .height('100%')
          .objectFit(ImageFit.Cover)
      }
      Column() {
        Text(this.label)
          .fontSize(12)
          .fontColor($r('app.color.card_text_secondary'))
          .width('100%')
        Row() {
          Text(this.minutes)
            .fontSize(46)
            .fontWeight(FontWeight.Bold)
            .fontColor(this.colorPrimary)
          Text(this.unit)
            .fontSize(12)
            .fontColor($r('app.color.card_text_secondary'))
            .margin({ left: 4, bottom: 8 })
        }
        .alignItems(VerticalAlign.Bottom)
        .width('100%')
        .margin({ top: 2 })
        Text(this.detail)
          .fontSize(12)
          .fontColor($r('app.color.card_text_secondary'))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .width('100%')
        Text(this.lifetime)
          .fontSize(12)
          .fontColor($r('app.color.card_text_secondary'))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .width('100%')
          .margin({ top: 2 })
      }
      .width('100%')
      .height('100%')
      .padding(16)
      .alignItems(HorizontalAlign.Start)
      .justifyContent(FlexAlign.Center)
      }
      .width('100%')
      .height('100%')
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.card_bg'))
    // 16vp 圆角 + 裁剪：与 App 内卡片（radiusLg）一致，底图也不会漏出方角。
    .borderRadius(16)
    .clip(true)
    .onClick(() => {
      postCardAction(this, {
        action: 'router',
        abilityName: 'EntryAbility',
        params: { 'nexhub_card_route': 'stats' }
      });
    })
  }
}
