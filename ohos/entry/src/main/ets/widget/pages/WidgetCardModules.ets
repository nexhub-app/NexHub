import { image } from '@kit.ImageKit';

let storage: LocalStorage = new LocalStorage();

/** 分模块统计卡（2*4）：小说 / 漫画 / 影视 本周时长。 */
@Entry(storage)
@Component
export struct WidgetCardModules {
  @LocalStorageProp('bg') bg: image.PixelMap | null = null;
  @LocalStorageProp('bg_color') bgColor: string = '#FFFFFF';
  @LocalStorageProp('label_stats') label: string = '统计';
  @LocalStorageProp('label_novel') novelLabel: string = '小说';
  @LocalStorageProp('label_comic') comicLabel: string = '漫画';
  @LocalStorageProp('label_media') mediaLabel: string = '媒体';
  @LocalStorageProp('novel_week_minutes') novel: string = '0';
  @LocalStorageProp('comic_week_minutes') comic: string = '0';
  @LocalStorageProp('media_week_minutes') media: string = '0';
  @LocalStorageProp('minute_unit') unit: string = '分钟';
  @LocalStorageProp('sessions_text') sessions: string = '';

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
        Text(this.novelLabel + ' · ' + this.novel + ' ' + this.unit)
          .fontSize(16)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.card_text_primary'))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .width('100%')
          .margin({ top: 12 })
        Text(this.comicLabel + ' · ' + this.comic + ' ' + this.unit)
          .fontSize(16)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.card_text_primary'))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .width('100%')
          .margin({ top: 10 })
        Text(this.mediaLabel + ' · ' + this.media + ' ' + this.unit)
          .fontSize(16)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.card_text_primary'))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .width('100%')
          .margin({ top: 10 })
        Text(this.sessions)
          .fontSize(12)
          .fontColor($r('app.color.card_text_secondary'))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .width('100%')
          .margin({ top: 10 })
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
