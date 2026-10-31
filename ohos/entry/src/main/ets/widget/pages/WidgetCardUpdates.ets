import { image } from '@kit.ImageKit';

let storage: LocalStorage = new LocalStorage();

/** 追更卡（2*4 / 4*4）：收藏总数 + 最近 3 部收藏。点卡回首页书架。 */
@Entry(storage)
@Component
export struct WidgetCardUpdates {
  @LocalStorageProp('bg') bg: image.PixelMap | null = null;
  @LocalStorageProp('bg_color') bgColor: string = '#00000000';
  @LocalStorageProp('label_updates') label: string = '追更';
  @LocalStorageProp('update_text') mainText: string = '';
  @LocalStorageProp('favorite_0') fav0: string = '';
  @LocalStorageProp('favorite_1') fav1: string = '';
  @LocalStorageProp('favorite_2') fav2: string = '';

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
          if (this.fav0.length > 0) {
            Text('· ' + this.fav0)
              .fontSize(13)
              .fontColor($r('app.color.card_text_primary'))
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .width('100%')
              .margin({ top: 12 })
          }
          if (this.fav1.length > 0) {
            Text('· ' + this.fav1)
              .fontSize(13)
              .fontColor($r('app.color.card_text_primary'))
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .width('100%')
              .margin({ top: 6 })
          }
          if (this.fav2.length > 0) {
            Text('· ' + this.fav2)
              .fontSize(13)
              .fontColor($r('app.color.card_text_primary'))
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .width('100%')
              .margin({ top: 6 })
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
        params: { 'nexhub_card_route': 'updates' }
      });
    })
  }
}
