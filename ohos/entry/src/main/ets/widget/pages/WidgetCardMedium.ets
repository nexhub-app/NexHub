import { image } from '@kit.ImageKit';

let storage: LocalStorage = new LocalStorage();

/**
 * 中卡（2*4）：单条「继续观看」（带封面）+ 四行摘要。
 *
 * 封面用 Base64 data URI：鸿蒙卡片进程读不到应用文件、也不支持 PixelMap，
 * 只认 $r() / $rawfile() / Base64 三种图片源。
 */
@Entry(storage)
@Component
export struct WidgetCardMedium {
  @LocalStorageProp('bg') bg: image.PixelMap | null = null;
  @LocalStorageProp('bg_color') bgColor: string = '#FFFFFF';
  @LocalStorageProp('continue_0_title') title0: string = '';
  @LocalStorageProp('continue_0_subtitle') sub0: string = '';
  @LocalStorageProp('continue_0_cover_b64') cover0: string = '';
  @LocalStorageProp('update_text') updateText: string = '';
  @LocalStorageProp('download_text') downloadText: string = '';
  @LocalStorageProp('stats_text') statsText: string = '';
  @LocalStorageProp('today_text') todayText: string = '';
  @LocalStorageProp('has_continue') hasContinue: string = '0';
  @LocalStorageProp('empty_title') emptyTitle: string = '还没有观看记录';
  @LocalStorageProp('empty_hint') emptyHint: string = '打开 NexHub 挑一部开始';

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
        if (this.hasContinue === '1') {
          Row() {
            if (this.cover0.length > 0) {
              Image(this.cover0)
                .width(56)
                .height(74)
                .borderRadius(8)
                .objectFit(ImageFit.Cover)
            }
            Column() {
              Text(this.title0)
                .fontSize(16)
                .fontWeight(FontWeight.Bold)
                .fontColor($r('app.color.card_text_primary'))
                .maxLines(2)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
                .width('100%')
              Text(this.sub0)
                .fontSize(12)
                .fontColor($r('app.color.card_text_secondary'))
                .maxLines(2)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
                .width('100%')
                .margin({ top: 2 })
            }
            .layoutWeight(1)
            .margin({ left: 10 })
            .alignItems(HorizontalAlign.Start)
          }
          .width('100%')

          Text(this.updateText)
            .fontSize(12)
            .fontColor($r('app.color.card_text_secondary'))
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .width('100%')
            .margin({ top: 10 })
          Text(this.downloadText)
            .fontSize(12)
            .fontColor($r('app.color.card_text_secondary'))
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .width('100%')
            .margin({ top: 4 })
          Text(this.statsText)
            .fontSize(12)
            .fontColor($r('app.color.card_text_secondary'))
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .width('100%')
            .margin({ top: 4 })
          Text(this.todayText)
            .fontSize(12)
            .fontColor($r('app.color.card_text_secondary'))
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .width('100%')
            .margin({ top: 4 })
        } else {
          Text(this.emptyTitle)
            .fontSize(16)
            .fontWeight(FontWeight.Bold)
            .fontColor($r('app.color.card_text_primary'))
            .maxLines(2)
            .width('100%')
          Text(this.emptyHint)
            .fontSize(12)
            .fontColor($r('app.color.card_text_secondary'))
            .maxLines(2)
            .width('100%')
            .margin({ top: 4 })
        }
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
        params: { 'nexhub_card_route': 'continue' }
      });
    })
  }
}
