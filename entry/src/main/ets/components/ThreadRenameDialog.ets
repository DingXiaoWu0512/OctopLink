/** 会话重命名对话框（懒创建：由调用方在方法内 new CustomDialogController） */
@CustomDialog
export struct ThreadRenameDialog {
  controller?: CustomDialogController;
  initialName: string = '';
  onCancel: () => void = (): void => {
  };
  onConfirm: (name: string) => void = (name: string) => {
  };
  @State nameText: string = '';

  aboutToAppear(): void {
    this.nameText = this.initialName;
  }

  build() {
    Column({ space: 16 }) {
      Text('重命名会话')
        .fontSize(17)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.text_primary'))
        .width('100%')
        .textAlign(TextAlign.Start)
      TextInput({
        text: this.nameText,
        placeholder: '请输入会话名称'
      })
        .fontSize(15)
        .height(44)
        .backgroundColor($r('app.color.bg_input'))
        .borderRadius(12)
        .onChange((value: string): void => {
          this.nameText = value;
        })
      Row({ space: 12 }) {
        Button($r('app.string.common_cancel'))
          .fontSize(14)
          .height(38)
          .layoutWeight(1)
          .borderRadius(19)
          .backgroundColor($r('app.color.bg_input'))
          .fontColor($r('app.color.text_secondary'))
          .onClick((): void => {
            this.controller?.close();
            this.onCancel();
          })
        Button($r('app.string.common_confirm'))
          .fontSize(14)
          .height(38)
          .layoutWeight(1)
          .borderRadius(19)
          .linearGradient({
            angle: 140,
            colors: [[$r('app.color.brand_grad_start'), 0], [$r('app.color.brand_grad_end'), 1]]
          })
          .shadow({ radius: 10, color: '#260A59F7', offsetY: 4 })
          .fontColor($r('app.color.text_on_brand'))
          .onClick((): void => {
            const name: string = this.nameText.trim();
            if (name === '') {
              this.getUIContext().getPromptAction().showToast({ message: '名称不能为空' });
              return;
            }
            this.controller?.close();
            this.onConfirm(name);
          })
      }
      .width('100%')
    }
    .padding(20)
    .width('100%')
  }
}
