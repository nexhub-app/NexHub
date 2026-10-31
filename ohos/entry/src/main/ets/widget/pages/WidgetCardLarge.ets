import { image } from '@kit.ImageKit';

let storage: LocalStorage = new LocalStorage();

/**
 * 概览卡（4*4）：标题顶到最上、「本周…」压到最下，中间是多条记录。
 *
 * 多条用 Swiper 左右翻页（官方文档标注 Swiper 自 API 7 起支持 ArkTS 卡片）。
 * 八页全部按「标题非空」条件渲染，所以用户在设置里选 3~8 条都能翻到，
 * 空槽位不会出现空白页。
 */
@Entry(storage)
@Component
export struct WidgetCardLarge {
  @LocalStorageProp('bg') bg: image.PixelMap | null = null;
  @LocalStorageProp('bg_color') bgColor: string = '#FFFFFF';
  @LocalStorageProp('label_continue') label: string = '继续观看';
  @LocalStorageProp('stats_text') footer: string = '';
  @LocalStorageProp('continue_0_title') title0: string = '';
  @LocalStorageProp('continue_0_subtitle') sub0: string = '';
  @LocalStorageProp('continue_0_cover_b64') cover0: string = '';
  @LocalStorageProp('continue_1_title') title1: string = '';
  @LocalStorageProp('continue_1_subtitle') sub1: string = '';
  @LocalStorageProp('continue_1_cover_b64') cover1: string = '';
  @LocalStorageProp('continue_2_title') title2: string = '';
  @LocalStorageProp('continue_2_subtitle') sub2: string = '';
  @LocalStorageProp('continue_2_cover_b64') cover2: string = '';
  @LocalStorageProp('continue_3_title') title3: string = '';
  @LocalStorageProp('continue_3_subtitle') sub3: string = '';
  @LocalStorageProp('continue_3_cover_b64') cover3: string = '';
  @LocalStorageProp('continue_4_title') title4: string = '';
  @LocalStorageProp('continue_4_subtitle') sub4: string = '';
  @LocalStorageProp('continue_4_cover_b64') cover4: string = '';
  @LocalStorageProp('continue_5_title') title5: string = '';
  @LocalStorageProp('continue_5_subtitle') sub5: string = '';
  @LocalStorageProp('continue_5_cover_b64') cover5: string = '';
  @LocalStorageProp('continue_6_title') title6: string = '';
  @LocalStorageProp('continue_6_subtitle') sub6: string = '';
  @LocalStorageProp('continue_6_cover_b64') cover6: string = '';
  @LocalStorageProp('continue_7_title') title7: string = '';
  @LocalStorageProp('continue_7_subtitle') sub7: string = '';
  @LocalStorageProp('continue_7_cover_b64') cover7: string = '';

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

        Swiper() {
          if (this.title0.length > 0) {
            Column() {
              if (this.cover0.length > 0) {
                Row() {
                  Image(this.cover0).width(120).height(160).borderRadius(10).objectFit(ImageFit.Cover)
                    .interpolation(ImageInterpolation.High)
                }
                .width('100%').justifyContent(FlexAlign.Center)
              }
              Text(this.title0).fontSize(15).fontWeight(FontWeight.Bold)
                .fontColor($r('app.color.card_text_primary'))
                .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
                .width('100%').margin({ top: 8 })
              Text(this.sub0).fontSize(12)
                .fontColor($r('app.color.card_text_secondary'))
                .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
                .width('100%').margin({ top: 2 })
            }
            .width('100%').height('100%').alignItems(HorizontalAlign.Start).clip(false)
          }

          if (this.title1.length > 0) {
            Column() {
              if (this.cover1.length > 0) {
                Row() {
                  Image(this.cover1).width(120).height(160).borderRadius(10).objectFit(ImageFit.Cover)
                    .interpolation(ImageInterpolation.High)
                }
                .width('100%').justifyContent(FlexAlign.Center)
              }
              Text(this.title1).fontSize(15).fontWeight(FontWeight.Bold)
                .fontColor($r('app.color.card_text_primary'))
                .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
                .width('100%').margin({ top: 8 })
              Text(this.sub1).fontSize(12)
                .fontColor($r('app.color.card_text_secondary'))
                .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
                .width('100%').margin({ top: 2 })
            }
            .width('100%').height('100%').alignItems(HorizontalAlign.Start).clip(false)
          }

          if (this.title2.length > 0) {
            Column() {
              if (this.cover2.length > 0) {
                Row() {
                  Image(this.cover2).width(120).height(160).borderRadius(10).objectFit(ImageFit.Cover)
                    .interpolation(ImageInterpolation.High)
                }
                .width('100%').justifyContent(FlexAlign.Center)
              }
              Text(this.title2).fontSize(15).fontWeight(FontWeight.Bold)
                .fontColor($r('app.color.card_text_primary'))
                .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
                .width('100%').margin({ top: 8 })
              Text(this.sub2).fontSize(12)
                .fontColor($r('app.color.card_text_secondary'))
                .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
                .width('100%').margin({ top: 2 })
            }
            .width('100%').height('100%').alignItems(HorizontalAlign.Start).clip(false)
          }

          if (this.title3.length > 0) {
            Column() {
              if (this.cover3.length > 0) {
                Row() {
                  Image(this.cover3).width(120).height(160).borderRadius(10).objectFit(ImageFit.Cover)
                    .interpolation(ImageInterpolation.High)
                }
                .width('100%').justifyContent(FlexAlign.Center)
              }
              Text(this.title3).fontSize(15).fontWeight(FontWeight.Bold)
                .fontColor($r('app.color.card_text_primary'))
                .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
                .width('100%').margin({ top: 8 })
              Text(this.sub3).fontSize(12)
                .fontColor($r('app.color.card_text_secondary'))
                .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
                .width('100%').margin({ top: 2 })
            }
            .width('100%').height('100%').alignItems(HorizontalAlign.Start).clip(false)
          }

          if (this.title4.length > 0) {
            Column() {
              if (this.cover4.length > 0) {
                Row() {
                  Image(this.cover4).width(120).height(160).borderRadius(10).objectFit(ImageFit.Cover)
                    .interpolation(ImageInterpolation.High)
                }
                .width('100%').justifyContent(FlexAlign.Center)
              }
              Text(this.title4).fontSize(15).fontWeight(FontWeight.Bold)
                .fontColor($r('app.color.card_text_primary'))
                .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
                .width('100%').margin({ top: 8 })
              Text(this.sub4).fontSize(12)
                .fontColor($r('app.color.card_text_secondary'))
                .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
                .width('100%').margin({ top: 2 })
            }
            .width('100%').height('100%').alignItems(HorizontalAlign.Start).clip(false)
          }

          if (this.title5.length > 0) {
            Column() {
              if (this.cover5.length > 0) {
                Row() {
                  Image(this.cover5).width(120).height(160).borderRadius(10).objectFit(ImageFit.Cover)
                    .interpolation(ImageInterpolation.High)
                }
                .width('100%').justifyContent(FlexAlign.Center)
              }
              Text(this.title5).fontSize(15).fontWeight(FontWeight.Bold)
                .fontColor($r('app.color.card_text_primary'))
                .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
                .width('100%').margin({ top: 8 })
              Text(this.sub5).fontSize(12)
                .fontColor($r('app.color.card_text_secondary'))
                .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
                .width('100%').margin({ top: 2 })
            }
            .width('100%').height('100%').alignItems(HorizontalAlign.Start).clip(false)
          }

          if (this.title6.length > 0) {
            Column() {
              if (this.cover6.length > 0) {
                Row() {
                  Image(this.cover6).width(120).height(160).borderRadius(10).objectFit(ImageFit.Cover)
                    .interpolation(ImageInterpolation.High)
                }
                .width('100%').justifyContent(FlexAlign.Center)
              }
              Text(this.title6).fontSize(15).fontWeight(FontWeight.Bold)
                .fontColor($r('app.color.card_text_primary'))
                .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
                .width('100%').margin({ top: 8 })
              Text(this.sub6).fontSize(12)
                .fontColor($r('app.color.card_text_secondary'))
                .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
                .width('100%').margin({ top: 2 })
            }
            .width('100%').height('100%').alignItems(HorizontalAlign.Start).clip(false)
          }

          if (this.title7.length > 0) {
            Column() {
              if (this.cover7.length > 0) {
                Row() {
                  Image(this.cover7).width(120).height(160).borderRadius(10).objectFit(ImageFit.Cover)
                    .interpolation(ImageInterpolation.High)
                }
                .width('100%').justifyContent(FlexAlign.Center)
              }
              Text(this.title7).fontSize(15).fontWeight(FontWeight.Bold)
                .fontColor($r('app.color.card_text_primary'))
                .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
                .width('100%').margin({ top: 8 })
              Text(this.sub7).fontSize(12)
                .fontColor($r('app.color.card_text_secondary'))
                .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
                .width('100%').margin({ top: 2 })
            }
            .width('100%').height('100%').alignItems(HorizontalAlign.Start).clip(false)
          }
        }
        .layoutWeight(1)
        .width('100%')
        .loop(false)
        .indicator(false)
        .margin({ top: 6, bottom: 6 })

        Text(this.footer)
          .fontSize(12)
          .fontColor($r('app.color.card_text_secondary'))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .width('100%')
      }
      .width('100%')
      .height('100%')
      .padding(16)
      .alignItems(HorizontalAlign.Start)
      .justifyContent(FlexAlign.SpaceBetween)
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
