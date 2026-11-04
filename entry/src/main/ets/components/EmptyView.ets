@Component
export struct EmptyView {
  title: string = '';
  subtitle: string = '';
  icon: Resource = $r('sys.symbol.message');
  /** true：图标区渲染探头章鱼动画（默认升级）；false：回退原 SymbolGlyph 圆形徽章 */
  mascot: boolean = true;

  build() {
    Column({ space: 10 }) {
      if (this.mascot) {
        Image($r('app.media.octop_mascot_peek'))
          .width(96)
          .height(64)
          .objectFit(ImageFit.Contain)
          .interpolation(ImageInterpolation.None)
      } else {
        Column() {
          Column() {
            SymbolGlyph(this.icon)
              .fontSize(30)
              .fontColor([$r('app.color.brand')])
          }
          .width(72)
          .height(72)
          .borderRadius(36)
          .backgroundColor($r('app.color.brand_light'))
          .justifyContent(FlexAlign.Center)
        }
        .width(96)
        .height(96)
        .borderRadius(48)
        .border({ width: 1, color: $r('app.color.card_stroke') })
        .backgroundColor($r('app.color.brand_light'))
        .opacity(0.4)
        .justifyContent(FlexAlign.Center)
        .alignItems(HorizontalAlign.Center)
      }
      Text(this.title)
        .fontSize(16)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.text_primary'))
      if (this.subtitle !== '') {
        Text(this.subtitle)
          .fontSize(13)
          .fontColor($r('app.color.text_secondary'))
          .textAlign(TextAlign.Center)
          .lineHeight(20)
      }
    }
    .width('100%')
    .padding({ top: 48, bottom: 48, left: 32, right: 32 })
    .alignItems(HorizontalAlign.Center)
    .justifyContent(FlexAlign.Center)
  }
}
