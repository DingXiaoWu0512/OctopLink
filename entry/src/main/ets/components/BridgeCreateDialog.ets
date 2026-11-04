import { BridgeService } from '../service/BridgeService';
import { BridgeProbeResultModel } from '../model/BridgeModels';
import { OctopApiError } from '../net/HttpClient';

/** 桥接设备创建对话框：对端地址/账密 + 显示名/备注 + 可选连通性探测 + 创建后立即连接 */
@CustomDialog
export struct BridgeCreateDialog {
  controller?: CustomDialogController;
  onSaved: () => void = (): void => {
  };

  @State baseUrlText: string = '';
  @State usernameText: string = '';
  @State passwordText: string = '';
  @State nameText: string = '';
  @State notesText: string = '';
  @State connectNow: boolean = true;
  @State probing: boolean = false;
  @State probeHint: string = '';
  @State submitting: boolean = false;

  private async testConnection(): Promise<void> {
    if (this.probing || this.submitting) {
      return;
    }
    const baseUrl: string = this.baseUrlText.trim();
    const username: string = this.usernameText.trim();
    const password: string = this.passwordText;
    if (baseUrl === '' || username === '' || password === '') {
      this.getUIContext().getPromptAction().showToast({ message: '请先填写对端地址、账号与密码' });
      return;
    }
    this.probing = true;
    this.probeHint = '';
    try {
      const result: BridgeProbeResultModel = await BridgeService.probe(baseUrl, username, password);
      this.probeHint = `对端「${result.peerDisplayName === '' ? username : result.peerDisplayName}」· ${result.agentCount} 位专家`;
    } catch (e) {
      const message: string = e instanceof OctopApiError ? e.message : '探测失败';
      this.getUIContext().getPromptAction().showToast({ message });
    } finally {
      this.probing = false;
    }
  }

  private async submit(): Promise<void> {
    if (this.submitting || this.probing) {
      return;
    }
    const baseUrl: string = this.baseUrlText.trim();
    const username: string = this.usernameText.trim();
    const password: string = this.passwordText;
    const displayName: string = this.nameText.trim();
    if (baseUrl === '' || username === '' || password === '' || displayName === '') {
      this.getUIContext().getPromptAction().showToast({ message: '请完整填写对端信息与显示名称' });
      return;
    }
    this.submitting = true;
    try {
      await BridgeService.create(baseUrl, username, password, displayName,
        this.notesText.trim(), this.connectNow);
      this.controller?.close();
      this.getUIContext().getPromptAction().showToast({ message: '桥接设备已创建' });
      this.onSaved();
    } catch (e) {
      const message: string = e instanceof OctopApiError ? e.message : '创建失败';
      this.getUIContext().getPromptAction().showToast({ message });
    } finally {
      this.submitting = false;
    }
  }

  build() {
    Column({ space: 14 }) {
      Text('新建桥接设备')
        .fontSize(17)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.text_primary'))
        .width('100%')
        .textAlign(TextAlign.Start)

      TextInput({
        text: this.baseUrlText,
        placeholder: '对端 Octop 地址，如 https://cloud.example'
      })
        .fontSize(14)
        .height(42)
        .backgroundColor($r('app.color.bg_input'))
        .borderRadius(12)
        .onChange((value: string): void => {
          this.baseUrlText = value;
        })

      TextInput({
        text: this.usernameText,
        placeholder: '对端用户名'
      })
        .fontSize(14)
        .height(42)
        .backgroundColor($r('app.color.bg_input'))
        .borderRadius(12)
        .onChange((value: string): void => {
          this.usernameText = value;
        })

      TextInput({
        text: this.passwordText,
        placeholder: '对端密码'
      })
        .fontSize(14)
        .height(42)
        .backgroundColor($r('app.color.bg_input'))
        .borderRadius(12)
        .type(InputType.Password)
        .onChange((value: string): void => {
          this.passwordText = value;
        })

      Row() {
        Text(this.probing ? '探测中...' : '测试连接')
          .fontSize(13)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.brand'))
          .height(30)
          .padding({ left: 14, right: 14 })
          .borderRadius(15)
          .backgroundColor($r('app.color.brand_light'))
          .enabled(!this.probing && !this.submitting)
          .onClick((): void => {
            this.testConnection();
          })
        if (this.probeHint !== '') {
          Text(this.probeHint)
            .fontSize(12)
            .fontColor($r('app.color.success'))
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .layoutWeight(1)
        }
      }
      .width('100%')

      TextInput({
        text: this.nameText,
        placeholder: '显示名称（聊天切换时区分对端）'
      })
        .fontSize(14)
        .height(42)
        .backgroundColor($r('app.color.bg_input'))
        .borderRadius(12)
        .onChange((value: string): void => {
          this.nameText = value;
        })

      TextArea({
        text: this.notesText,
        placeholder: '备注（可选）'
      })
        .fontSize(14)
        .height(64)
        .backgroundColor($r('app.color.bg_input'))
        .borderRadius(12)
        .onChange((value: string): void => {
          this.notesText = value;
        })

      Row() {
        Column({ space: 3 }) {
          Text('创建后立即连接')
            .fontSize(14)
            .fontColor($r('app.color.text_primary'))
          Text('关闭后仅保存，稍后可手动拨号')
            .fontSize(11)
            .fontColor($r('app.color.text_tertiary'))
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1)

        Toggle({ type: ToggleType.Switch, isOn: this.connectNow })
          .onChange((isOn: boolean): void => {
            this.connectNow = isOn;
          })
      }
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
          .enabled(!this.submitting && !this.probing)
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
