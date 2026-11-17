import { KnowledgeService } from '../service/WorkspaceService';
import { OctopApiError } from '../net/HttpClient';

/** 知识库 md/txt 在线文档创建对话框 */
@CustomDialog
export struct TextDocCreateDialog {
  controller?: CustomDialogController;
  kbId: string = '';
  onCreated: () => void = (): void => {
  };
  @State nameText: string = '';
  @State formatIndex: number = 0;
  @State contentText: string = '';
  @State submitting: boolean = false;

  private async submit(): Promise<void> {
    if (this.submitting) {
      return;
    }
    const name: string = this.nameText.trim();
    if (name === '') {
      this.getUIContext().getPromptAction().showToast({ message: '请填写文档名称' });
      return;
    }
    this.submitting = true;
    try {
      const format: string = this.formatIndex === 0 ? 'md' : 'txt';
      await KnowledgeService.createTextDoc(this.kbId, name, format, this.contentText);
      this.controller?.close();
      this.getUIContext().getPromptAction().showToast({ message: '文档已创建' });
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
      Text('新建文档')
        .fontSize(17)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.text_primary'))
        .width('100%')
        .textAlign(TextAlign.Start)
      TextInput({
        text: this.nameText,
        placeholder: '文档名称'
      })
        .fontSize(14)
        .height(42)
        .backgroundColor($r('app.color.bg_input'))
        .borderRadius(12)
        .onChange((value: string): void => {
          this.nameText = value;
        })
      Row({ space: 8 }) {
        Text('Markdown (.md)')
          .fontSize(13)
          .fontColor(this.formatIndex === 0 ? $r('app.color.text_on_brand') : $r('app.color.text_secondary'))
          .height(30)
          .padding({ left: 12, right: 12 })
          .borderRadius(15)
          .backgroundColor(this.formatIndex === 0 ? $r('app.color.brand') : $r('app.color.bg_input'))
          .onClick((): void => {
            this.formatIndex = 0;
          })
        Text('纯文本 (.txt)')
          .fontSize(13)
          .fontColor(this.formatIndex === 1 ? $r('app.color.text_on_brand') : $r('app.color.text_secondary'))
          .height(30)
          .padding({ left: 12, right: 12 })
          .borderRadius(15)
          .backgroundColor(this.formatIndex === 1 ? $r('app.color.brand') : $r('app.color.bg_input'))
          .onClick((): void => {
            this.formatIndex = 1;
          })
      }
      .width('100%')
      TextArea({
        text: this.contentText,
        placeholder: '文档内容'
      })
        .fontSize(14)
        .height(120)
        .backgroundColor($r('app.color.bg_input'))
        .borderRadius(12)
        .onChange((value: string): void => {
          this.contentText = value;
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
