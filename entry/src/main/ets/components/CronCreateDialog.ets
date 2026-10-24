import { CronService } from '../service/WorkspaceService';
import { OctopApiError } from '../net/HttpClient';

/** 定时任务创建对话框：触发器类型切换 + 提示词 */
@CustomDialog
export struct CronCreateDialog {
  controller?: CustomDialogController;
  onCreated: () => void = (): void => {
  };
  agentId: string = '';
  @State triggerKind: number = 0;
  @State nameText: string = '';
  @State valueText: string = '';
  @State promptText: string = '';
  @State submitting: boolean = false;

  private triggerPlaceholder(): string {
    if (this.triggerKind === 0) {
      return 'Cron 表达式，如 0 9 * * *';
    }
    if (this.triggerKind === 1) {
      return '间隔秒数，如 3600';
    }
    return '时间，如 2030-01-01T08:00:00';
  }

  private buildTrigger(): string {
    if (this.triggerKind === 0) {
      return `cron:${this.valueText.trim()}`;
    }
    if (this.triggerKind === 1) {
      return `interval:${this.valueText.trim()}`;
    }
    return `date:${this.valueText.trim()}`;
  }

  private async submit(): Promise<void> {
    if (this.submitting) {
      return;
    }
    const value: string = this.valueText.trim();
    const prompt: string = this.promptText.trim();
    if (value === '' || prompt === '') {
      this.getUIContext().getPromptAction().showToast({ message: '请填写触发条件与提示词' });
      return;
    }
    if (this.triggerKind === 1) {
      const seconds: number = Number(value);
      if (Number.isNaN(seconds) || seconds <= 0) {
        this.getUIContext().getPromptAction().showToast({ message: '间隔必须为正整数秒' });
        return;
      }
    }
    this.submitting = true;
    try {
      await CronService.create(this.agentId, this.nameText.trim(), this.buildTrigger(), prompt);
      this.controller?.close();
      this.getUIContext().getPromptAction().showToast({ message: '任务已创建' });
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
      Text('新建定时任务')
        .fontSize(17)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.text_primary'))
        .width('100%')
        .textAlign(TextAlign.Start)

      TextInput({
        text: this.nameText,
        placeholder: '任务名称（可选）'
      })
        .fontSize(14)
        .height(42)
        .backgroundColor($r('app.color.bg_input'))
        .borderRadius(12)
        .onChange((value: string): void => {
          this.nameText = value;
        })

      Row({ space: 8 }) {
        Text('Cron')
          .fontSize(13)
          .fontColor(this.triggerKind === 0 ? $r('app.color.text_on_brand') : $r('app.color.text_secondary'))
          .height(30)
          .padding({ left: 12, right: 12 })
          .borderRadius(15)
          .backgroundColor(this.triggerKind === 0 ? $r('app.color.brand') : $r('app.color.bg_input'))
          .onClick((): void => {
            this.triggerKind = 0;
          })
        Text('间隔')
          .fontSize(13)
          .fontColor(this.triggerKind === 1 ? $r('app.color.text_on_brand') : $r('app.color.text_secondary'))
          .height(30)
          .padding({ left: 12, right: 12 })
          .borderRadius(15)
          .backgroundColor(this.triggerKind === 1 ? $r('app.color.brand') : $r('app.color.bg_input'))
          .onClick((): void => {
            this.triggerKind = 1;
          })
        Text('定时一次')
          .fontSize(13)
          .fontColor(this.triggerKind === 2 ? $r('app.color.text_on_brand') : $r('app.color.text_secondary'))
          .height(30)
          .padding({ left: 12, right: 12 })
          .borderRadius(15)
          .backgroundColor(this.triggerKind === 2 ? $r('app.color.brand') : $r('app.color.bg_input'))
          .onClick((): void => {
            this.triggerKind = 2;
          })
      }
      .width('100%')

      TextInput({
        text: this.valueText,
        placeholder: this.triggerPlaceholder()
      })
        .fontSize(14)
        .height(42)
        .backgroundColor($r('app.color.bg_input'))
        .borderRadius(12)
        .onChange((value: string): void => {
          this.valueText = value;
        })

      TextArea({
        text: this.promptText,
        placeholder: '触发时执行的提示词'
      })
        .fontSize(14)
        .height(80)
        .backgroundColor($r('app.color.bg_input'))
        .borderRadius(12)
        .onChange((value: string): void => {
          this.promptText = value;
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
