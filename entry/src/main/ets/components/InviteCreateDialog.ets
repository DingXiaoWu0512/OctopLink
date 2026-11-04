import { pasteboard } from '@kit.BasicServicesKit';
import { InviteService } from '../service/InviteService';
import { InviteModel } from '../model/InviteModels';
import { OctopApiError } from '../net/HttpClient';

/** 邀请码创建对话框：备注 + 有效期（1-90 天），创建成功后自动复制邀请链接 */
@CustomDialog
export struct InviteCreateDialog {
  controller?: CustomDialogController;
  onSaved: () => void = (): void => {
  };

  @State noteText: string = '';
  @State daysText: string = '7';
  @State submitting: boolean = false;

  private async submit(): Promise<void> {
    if (this.submitting) {
      return;
    }
    const note: string = this.noteText.trim();
    const days: number = Number(this.daysText.trim());
    if (Number.isNaN(days) || days < 1 || days > 90) {
      this.getUIContext().getPromptAction().showToast({ message: '有效期需为 1-90 天' });
      return;
    }
    this.submitting = true;
    try {
      const invite: InviteModel = await InviteService.create(note, days);
      await this.copyInviteUrl(invite.inviteUrl);
      this.controller?.close();
      this.onSaved();
    } catch (e) {
      const message: string = e instanceof OctopApiError ? e.message : '创建失败';
      this.getUIContext().getPromptAction().showToast({ message });
    } finally {
      this.submitting = false;
    }
  }

  /** 创建后复制邀请链接（失败时降级为普通提示） */
  private async copyInviteUrl(url: string): Promise<void> {
    if (url === '') {
      this.getUIContext().getPromptAction().showToast({ message: '邀请码已创建' });
      return;
    }
    try {
      const board = pasteboard.getSystemPasteboard();
      const data = pasteboard.createData(pasteboard.MIMETYPE_TEXT_PLAIN, url);
      await board.setData(data);
      this.getUIContext().getPromptAction().showToast({ message: '邀请码已创建，链接已复制' });
    } catch (e) {
      this.getUIContext().getPromptAction().showToast({ message: '邀请码已创建' });
    }
  }

  build() {
    Column({ space: 14 }) {
      Text('新建邀请码')
        .fontSize(17)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.text_primary'))
        .width('100%')
        .textAlign(TextAlign.Start)

      TextInput({
        text: this.noteText,
        placeholder: '备注（可选，如：新同事入职）'
      })
        .fontSize(14)
        .height(42)
        .backgroundColor($r('app.color.bg_input'))
        .borderRadius(12)
        .onChange((value: string): void => {
          this.noteText = value;
        })

      TextInput({
        text: this.daysText,
        placeholder: '有效期（天）'
      })
        .fontSize(14)
        .height(42)
        .backgroundColor($r('app.color.bg_input'))
        .borderRadius(12)
        .type(InputType.Number)
        .onChange((value: string): void => {
          this.daysText = value;
        })

      Text('有效期范围 1-90 天，超时未使用将自动过期')
        .fontSize(11)
        .fontColor($r('app.color.text_tertiary'))
        .width('100%')

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
          .backgroundColor($r('app.color.brand'))
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
