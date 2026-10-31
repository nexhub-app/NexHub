import { image } from '@kit.ImageKit';

let storage: LocalStorage = new LocalStorage();

/**
 * 热力图卡（2*4 / 4*4）：真正的 30 天格子图。
 *
 * 图由 Flutter 用 Canvas 画好（5 列 × 6 行、按每天时长分档上色），转成 Base64
 * 交给卡片显示 —— 鸿蒙卡片读不到文件、也不支持 PixelMap，Base64 是唯一通路。
 */
@Entry(storage)
@Component
export struct WidgetCardHeatmap {
  @LocalStorageProp('bg') bg: image.PixelMap | null = null;
  @LocalStorageProp('bg_color') bgColor: string = '#FFFFFF';
  @LocalStorageProp('label_stats') label: string = '统计';
  @LocalStorageProp('heatmap_caption') caption: string = '近 30 天';
  @LocalStorageProp('heatmap_b64') heatmap: string = '';
  @LocalStorageProp('stats_active_days') activeDays: string = '0';
  @LocalStorageProp('stats_text') weekText: string = '';
  @LocalStorageProp('today_text') todayText: string = '';

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
        Row() {
          Text('🔥')
            .fontSize(12)
          Text(this.label + ' · ' + this.caption)
            .fontSize(12)
            .fontColor($r('app.color.card_text_secondary'))
            .margin({ left: 4 })
        }
        .width('100%')

        if (this.heatmap.length > 0) {
          Image(this.heatmap)
            .width('100%')
            .layoutWeight(1)
            .objectFit(ImageFit.Contain)
            .margin({ top: 6, bottom: 6 })
        } else {
          Text(this.activeDays)
            .fontSize(40)
            .fontWeight(FontWeight.Bold)
            .fontColor($r('app.color.card_text_primary'))
            .width('100%')
            .margin({ top: 6 })
        }

        Text(this.weekText)
          .fontSize(12)
          .fontColor($r('app.color.card_text_secondary'))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .width('100%')
        Text(this.todayText)
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
