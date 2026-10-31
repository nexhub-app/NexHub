import { image } from '@kit.ImageKit';

let storage: LocalStorage = new LocalStorage();

/**
 * 统计卡（2*4 / 4*4）：照 App 内「统计 → 概览」的视觉做。
 *
 * 统计页每个指标是「大号彩色数字 + 同色图标 + 小标签」（见 `_StatMetric`），
 * 这里同样：图标 + 彩色数值 + 标签三列，下面再压一张热力图缩略图，
 * 避免卡片变成纯文字列表。
 */
@Entry(storage)
@Component
export struct WidgetCardStats {
  @LocalStorageProp('bg') bg: image.PixelMap | null = null;
  @LocalStorageProp('bg_color') bgColor: string = '#FFFFFF';
  @LocalStorageProp('label_stats') label: string = '统计';
  @LocalStorageProp('trend_text') trend: string = '';
  @LocalStorageProp('trend_up') trendUp: string = '0';
  @LocalStorageProp('color_primary') colorPrimary: string = '#0EA5E9';
  @LocalStorageProp('color_tertiary') colorTertiary: string = '#0EA5E9';
  @LocalStorageProp('color_secondary') colorSecondary: string = '#0EA5E9';
  @LocalStorageProp('label_total') labelTotal: string = '总时长';
  @LocalStorageProp('label_works') labelWorks: string = '作品数';
  @LocalStorageProp('label_sessions') labelSessions: string = '会话';
  @LocalStorageProp('stats_total_hours') totalHours: string = '0';
  @LocalStorageProp('stats_work_count') workCount: string = '0';
  @LocalStorageProp('stats_sessions') sessions: string = '0';
  @LocalStorageProp('heatmap_b64') heatmap: string = '';

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
          Text('📊').fontSize(12)
          Text(this.label)
            .fontSize(12)
            .fontColor($r('app.color.card_text_secondary'))
            .margin({ left: 4 })
          Blank()
          Text(this.trend)
            .fontSize(12)
            .fontColor(this.trendUp === '1' ? '#E5484D' : '#30A46C')
        }
        .width('100%')

        // ── 三个指标：图标 + 彩色数值 + 标签（对齐统计页 _StatMetric）──
        Row() {
          Column() {
            Text('⏱').fontSize(14)
            Text(this.totalHours + ' h')
              .fontSize(20)
              .fontWeight(FontWeight.Bold)
              .fontColor(this.colorPrimary)
              .maxLines(1)
              .margin({ top: 2 })
            Text(this.labelTotal)
              .fontSize(12)
              .fontColor($r('app.color.card_text_secondary'))
              .maxLines(1)
              .margin({ top: 2 })
          }
          .layoutWeight(1)
          .alignItems(HorizontalAlign.Center)

          Column() {
            Text('📖').fontSize(14)
            Text(this.workCount)
              .fontSize(20)
              .fontWeight(FontWeight.Bold)
              .fontColor(this.colorTertiary)
              .maxLines(1)
              .margin({ top: 2 })
            Text(this.labelWorks)
              .fontSize(12)
              .fontColor($r('app.color.card_text_secondary'))
              .maxLines(1)
              .margin({ top: 2 })
          }
          .layoutWeight(1)
          .alignItems(HorizontalAlign.Center)

          Column() {
            Text('🔁').fontSize(14)
            Text(this.sessions)
              .fontSize(20)
              .fontWeight(FontWeight.Bold)
              .fontColor(this.colorSecondary)
              .maxLines(1)
              .margin({ top: 2 })
            Text(this.labelSessions)
              .fontSize(12)
              .fontColor($r('app.color.card_text_secondary'))
              .maxLines(1)
              .margin({ top: 2 })
          }
          .layoutWeight(1)
          .alignItems(HorizontalAlign.Center)
        }
        .width('100%')
        .margin({ top: 8 })

        // ── 当月打卡月历（与统计页热力图同源预渲染 PNG）：
        //    有剩余高度就显示（4*4 更舒展，2*4 收紧），无数据时不占位。──
        if (this.heatmap.length > 0) {
          Image(this.heatmap)
            .width('100%')
            .layoutWeight(1)
            .objectFit(ImageFit.Contain)
            .margin({ top: 8 })
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
        params: { 'nexhub_card_route': 'stats' }
      });
    })
  }
}
