import { AuthService } from '../service/AuthService';
import { OctopApiError } from '../net/HttpClient';

/** 修改密码对话框（懒创建） */
@CustomDialog
export struct ChangePasswordDialog {
  controller?: CustomDialogController;
  @State oldPassword: string = '';
  @State newPassword: string = '';
  @State confirmPassword: string = '';
  @State submitting: boolean = false;

  private async submit(): Promise<void> {
    if (this.submitting) {
      return;
    }
    if (this.oldPassword === '' || this.newPassword === '') {
      this.getUIContext().getPromptAction().showToast({ message: '请填写完整' });
      return;
    }
    if (this.newPassword.length < 6) {
      this.getUIContext().getPromptAction().showToast({ message: '新密码至少 6 位' });
      return;
    }
    if (this.newPassword !== this.confirmPassword) {
      this.getUIContext().getPromptAction().showToast({ message: '两次输入的新密码不一致' });
      return;
    }
    this.submitting = true;
    try {
      await AuthService.changePassword(this.oldPassword, this.newPassword);
      this.controller?.close();
      this.getUIContext().getPromptAction().showToast({ message: '密码修改成功' });
    } catch (e) {
      const message: string = e instanceof OctopApiError ? e.message : '修改失败，请重试';
      this.getUIContext().getPromptAction().showToast({ message });
    } finally {
      this.submitting = false;
    }
  }

  build() {
    Column({ space: 14 }) {
      Text('修改密码')
        .fontSize(17)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.text_primary'))
        .width('100%')
        .textAlign(TextAlign.Start)
      TextInput({
        text: this.oldPassword,
        placeholder: '当前密码'
      })
        .fontSize(15)
        .height(44)
        .backgroundColor($r('app.color.bg_input'))
        .borderRadius(12)
        .type(InputType.Password)
        .onChange((value: string): void => {
          this.oldPassword = value;
        })
      TextInput({
        text: this.newPassword,
        placeholder: '新密码（至少 6 位）'
      })
        .fontSize(15)
        .height(44)
        .backgroundColor($r('app.color.bg_input'))
        .borderRadius(12)
        .type(InputType.Password)
        .onChange((value: string): void => {
          this.newPassword = value;
        })
      TextInput({
        text: this.confirmPassword,
        placeholder: '确认新密码'
      })
        .fontSize(15)
        .height(44)
        .backgroundColor($r('app.color.bg_input'))
        .borderRadius(12)
        .type(InputType.Password)
        .onChange((value: string): void => {
          this.confirmPassword = value;
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
        Button(this.submitting ? '提交中...' : '确认修改')
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
