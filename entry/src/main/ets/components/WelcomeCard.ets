
/** 空会话欢迎卡片：欢迎语 + 空态引导文案（快捷提示 chips 图标群已按第七批需求移除） */
@Component
export struct WelcomeCard {
  message: string = '';
  prompts: Array<string> = [];
  onPromptClick: (prompt: string) => void = (prompt: string) => {
  };

  build() {
    Column({ space: 12 }) {
      Text(this.message === '' ? '你好，有什么可以帮你？' : this.message)
        .fontSize(15)
        .fontColor($r('app.color.text_primary'))
        .textAlign(TextAlign.Center)
        .lineHeight(24)
      // US5 空态文案：替换原 logo 装饰块与快捷提示 chips 图标群
      Text('开启一段新对话吧，什么都可以说。')
        .fontSize(15)
        .fontColor($r('app.color.text_primary'))
        .textAlign(TextAlign.Center)
        .lineHeight(24)
    }
    .width('100%')
    .padding({ left: 20, right: 20, top: 28, bottom: 24 })
    .borderRadius(20)
    .backgroundColor($r('app.color.bg_card'))
    .alignItems(HorizontalAlign.Center)
  }
}
