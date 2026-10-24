import { UiMaterialKit } from './UiMaterialKit';

/** 空会话欢迎卡片：欢迎语 + 快捷提示 chips */
@Component
export struct WelcomeCard {
  message: string = '';
  prompts: Array<string> = [];
  onPromptClick: (prompt: string) => void = (prompt: string) => {
  };

  build() {
    Column({ space: 16 }) {
      Column({ space: 12 }) {
        Column() {
          Image($r('app.media.octop_logo'))
            .width(36)
            .height(36)
            .borderRadius(18)
        }
        .width(64)
        .height(64)
        .borderRadius(32)
        .linearGradient({
          angle: 140,
          colors: [[$r('app.color.brand_grad_start'), 0], [$r('app.color.brand_grad_end'), 1]]
        })
        .justifyContent(FlexAlign.Center)
        .alignItems(HorizontalAlign.Center)
        Text(this.message === '' ? '你好，有什么可以帮你？' : this.message)
          .fontSize(15)
          .fontColor($r('app.color.text_primary'))
          .textAlign(TextAlign.Center)
          .lineHeight(24)
      }
      .width('100%')
      .alignItems(HorizontalAlign.Center)

      if (this.prompts.length > 0) {
        Flex({ direction: FlexDirection.Row, wrap: FlexWrap.Wrap, justifyContent: FlexAlign.Center }) {
          ForEach(this.prompts, (prompt: string) => {
            Button({ type: ButtonType.Normal, stateEffect: true }) {
              Row({ space: 5 }) {
                SymbolGlyph($r('sys.symbol.paperplane'))
                  .fontSize(13)
                  .fontColor([$r('app.color.brand')])
                Text(prompt)
                  .fontSize(13)
                  .fontColor($r('app.color.brand'))
                  .maxLines(1)
                  .textOverflow({ overflow: TextOverflow.Ellipsis })
                  .constraintSize({ maxWidth: '80%' })
              }
            }
            .backgroundColor($r('app.color.brand_light'))
            .borderRadius(18)
            .padding({ left: 14, right: 14, top: 8, bottom: 8 })
            .margin(4)
            .systemMaterial(UiMaterialKit.button())
            .onClick((): void => {
              this.onPromptClick(prompt);
            })
          }, (prompt: string, index: number) => `${index}_${prompt}`)
        }
        .width('100%')
      }
    }
    .width('100%')
    .padding({ left: 20, right: 20, top: 28, bottom: 24 })
    .borderRadius(20)
    .backgroundColor($r('app.color.bg_card'))
    .alignItems(HorizontalAlign.Center)
  }
}
