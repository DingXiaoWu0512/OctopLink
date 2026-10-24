import { KnowledgeService } from '../service/WorkspaceService';
import { OctopApiError } from '../net/HttpClient';

/** 知识库创建对话框 */
@CustomDialog
export struct KbCreateDialog {
  controller?: CustomDialogController;
  onCreated: () => void = (): void => {
  };
  @State nameText: string = '';
  @State descText: string = '';
  @State submitting: boolean = false;

  private async submit(): Promise<void> {
    if (this.submitting) {
      return;
    }
    const name: string = this.nameText.trim();
    if (name === '') {
      this.getUIContext().getPromptAction().showToast({ message: '请填写知识库名称' });
      return;
    }
    this.submitting = true;
    try {
      await KnowledgeService.createBase(name, this.descText.trim());
      this.controller?.close();
      this.getUIContext().getPromptAction().showToast({ message: '知识库已创建' });
      this.onCreated();
    } catch (e) {
      const message: string = e instanceof OctopApiError ? e.message : '创建失败';
      this.getUIContext().getPromptAction().showToast({ message });
    } finally {
      this.submitting = false;
    }
  }

  build() {
    Column({ space: 14 }) {
      Text('新建知识库')
        .fontSize(17)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.text_primary'))
        .width('100%')
        .textAlign(TextAlign.Start)
      TextInput({
        text: this.nameText,
        placeholder: '知识库名称（1-200 字符）'
      })
        .fontSize(14)
        .height(42)
        .backgroundColor($r('app.color.bg_input'))
        .borderRadius(12)
        .onChange((value: string): void => {
          this.nameText = value;
        })
      TextArea({
        text: this.descText,
        placeholder: '描述（可选）'
      })
        .fontSize(14)
        .height(64)
        .backgroundColor($r('app.color.bg_input'))
        .borderRadius(12)
        .onChange((value: string): void => {
          this.descText = value;
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
          })
        Button(this.submitting ? '创建中...' : '创建')
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
          .enabled(!this.submitting)
          .onClick((): void => {
            this.submit();
          })
      }
      .width('100%')
    }
    .padding(20)
    .width('100%')
  }
}
