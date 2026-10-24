@Component
export struct ErrorRetry {
  message: string = '';
  onRetry: () => void = (): void => {
  };

  build() {
    Column({ space: 12 }) {
      Column() {
        SymbolGlyph($r('sys.symbol.wifi'))
          .fontSize(28)
          .fontColor([$r('app.color.text_secondary')])
      }
      .width(64)
      .height(64)
      .borderRadius(32)
      .backgroundColor($r('app.color.bg_input'))
      .justifyContent(FlexAlign.Center)
      Text(this.message === '' ? '加载失败，请重试' : this.message)
        .fontSize(14)
        .fontColor($r('app.color.text_secondary'))
        .textAlign(TextAlign.Center)
      Button($r('app.string.chat_retry'))
        .fontSize(14)
        .fontWeight(FontWeight.Medium)
        .height(38)
        .borderRadius(19)
        .padding({ left: 28, right: 28 })
        .backgroundColor($r('app.color.brand'))
        .fontColor($r('app.color.text_on_brand'))
        .onClick((): void => {
          if (this.onRetry !== null) {
            this.onRetry();
          }
        })
    }
    .width('100%')
    .padding(32)
    .alignItems(HorizontalAlign.Center)
    .justifyContent(FlexAlign.Center)
  }
}
