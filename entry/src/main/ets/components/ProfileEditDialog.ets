import { AuthService } from '../service/AuthService';
import { OctopApiError } from '../net/HttpClient';
import { UiMaterialKit } from './UiMaterialKit';

/** 个人资料编辑（昵称 + 界面语言，PATCH /api/auth/me） */
@CustomDialog
export struct ProfileEditDialog {
  controller?: CustomDialogController;
  initialDisplayName: string = '';
  initialLocale: string = '';
  onSaved: () => void = (): void => {
  };

  @State nameText: string = '';
  @State localeKind: number = 0; // 0=不修改 1=zh 2=en
  @State submitting: boolean = false;

  aboutToAppear(): void {
    this.nameText = this.initialDisplayName;
    if (this.initialLocale === 'zh') {
      this.localeKind = 1;
    } else if (this.initialLocale === 'en') {
      this.localeKind = 2;
    }
  }

  private localeValue(): string {
    if (this.localeKind === 1) {
      return 'zh';
    }
    if (this.localeKind === 2) {
      return 'en';
    }
    return '';
  }

  private async submit(): Promise<void> {
    if (this.submitting) {
      return;
    }
    const name: string = this.nameText.trim();
    const locale: string = this.localeValue();
    if (name === '' && locale === '') {
      this.getUIContext().getPromptAction().showToast({ message: '请至少填写昵称或选择语言' });
      return;
    }
    this.submitting = true;
    try {
      await AuthService.updateMe(name, locale);
      this.controller?.close();
      this.getUIContext().getPromptAction().showToast({ message: '资料已更新' });
      this.onSaved();
    } catch (e) {
      const message: string = e instanceof OctopApiError ? e.message : '保存失败';
      this.getUIContext().getPromptAction().showToast({ message });
    } finally {
      this.submitting = false;
    }
  }

  @Builder
  localeOption(label: string, kind: number) {
    Text(label)
      .fontSize(13)
      .fontWeight(FontWeight.Medium)
      .fontColor(this.localeKind === kind ? $r('app.color.text_on_brand') : $r('app.color.text_secondary'))
      .height(32)
      .padding({ left: 14, right: 14 })
      .borderRadius(16)
      .backgroundColor(this.localeKind === kind ? $r('app.color.brand') : $r('app.color.bg_input'))
      .onClick((): void => {
        this.localeKind = kind;
      })
  }

  build() {
    Column({ space: 14 }) {
      Text('编辑个人资料')
        .fontSize(17)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.text_primary'))
        .width('100%')
        .textAlign(TextAlign.Start)

      Column({ space: 8 }) {
        Text('昵称')
          .fontSize(14)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.text_primary'))
        TextInput({
          text: this.nameText,
          placeholder: '对外展示的名称'
        })
          .fontSize(14)
          .height(42)
          .backgroundColor($r('app.color.bg_input'))
          .borderRadius(12)
          .onChange((value: string): void => {
            this.nameText = value;
          })
      }
      .width('100%')
      .alignItems(HorizontalAlign.Start)

      Column({ space: 8 }) {
        Text('界面语言')
          .fontSize(14)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.text_primary'))
        Row({ space: 6 }) {
          this.localeOption('不修改', 0)
          this.localeOption('简体中文', 1)
          this.localeOption('English', 2)
        }
        .width('100%')
      }
      .width('100%')
      .alignItems(HorizontalAlign.Start)

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
        Button(this.submitting ? '保存中...' : '保存')
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
