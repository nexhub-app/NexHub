import { image } from '@kit.ImageKit';

let storage: LocalStorage = new LocalStorage();

/** 下载卡（2*4 / 2*2）：任务数与整体进度 + 首个任务标题。点卡进下载页。 */
@Entry(storage)
@Component
export struct WidgetCardDownloads {
  @LocalStorageProp('bg') bg: image.PixelMap | null = null;
  @LocalStorageProp('bg_color') bgColor: string = '#00000000';
  @LocalStorageProp('label_downloads') label: string = '下载';
  @LocalStorageProp('download_text') mainText: string = '';
  @LocalStorageProp('download_title') taskTitle: string = '';

  build() {
    // 外层：系统背景色（随深浅色自动切换）；内层：半透明主题色。
    Stack() {
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
          Text(this.mainText)
            .fontSize(16)
            .fontWeight(FontWeight.Bold)
            .fontColor($r('app.color.card_text_primary'))
            .maxLines(2)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .width('100%')
            .margin({ top: 6 })
          if (this.taskTitle.length > 0) {
            Text(this.taskTitle)
              .fontSize(13)
              .fontColor($r('app.color.card_text_secondary'))
              .maxLines(2)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .width('100%')
              .margin({ top: 10 })
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
        params: { 'nexhub_card_route': 'downloads' }
      });
    })
  }
}
