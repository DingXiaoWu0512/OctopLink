import { webview } from '@kit.ArkWeb';
import { UiMaterialKit } from './UiMaterialKit';

/** H5 → ArkTS 验证码桥（window.octopCaptcha） */
export class CaptchaJsBridge {
  private provider: string = '';
  private siteKey: string = '';
  private tokenArrived: ((token: string) => void) | null = null;
  private errorOccurred: (() => void) | null = null;

  setConfig(provider: string, siteKey: string): void {
    this.provider = provider;
    this.siteKey = siteKey;
  }

  setHandlers(tokenArrived: (token: string) => void, errorOccurred: () => void): void {
    this.tokenArrived = tokenArrived;
    this.errorOccurred = errorOccurred;
  }

  /** H5 读取 provider/site_key 配置 */
  getConfig(): string {
    const rec: Record<string, Object> = {
      'provider': this.provider,
      'site_key': this.siteKey
    };
    return JSON.stringify(rec);
  }

  /** H5 验证成功回调 */
  onToken(token: string): void {
    const handler = this.tokenArrived;
    if (handler !== null) {
      handler(token);
    }
  }

  /** H5 加载/验证失败回调 */
  onError(): void {
    const handler = this.errorOccurred;
    if (handler !== null) {
      handler();
    }
  }
}

/**
 * 登录验证码挑战弹窗（强 provider：tencent/turnstile/hcaptcha/recaptcha/recaptcha-v3/geetest-v4）。
 * Web 组件加载 rawfile/captcha.html，通过 javaScriptProxy 桥获取验证 token；
 * token 格式与 Web 端一致（tencent=“ticket:randstr”，geetest=getValidate JSON）。
 */
@CustomDialog
export struct CaptchaDialog {
  controller?: CustomDialogController;
  provider: string = '';
  siteKey: string = '';
  onVerified: (token: string) => void = (token: string): void => {
  };

  @State verifiedToken: string = '';
  @State errorMsg: string = '';
  private webController: webview.WebviewController = new webview.WebviewController();
  private bridge: CaptchaJsBridge = new CaptchaJsBridge();

  aboutToAppear(): void {
    this.bridge.setConfig(this.provider, this.siteKey);
    this.bridge.setHandlers(
      (token: string): void => {
        this.verifiedToken = token;
        this.errorMsg = '';
      },
      (): void => {
        if (this.verifiedToken === '') {
          this.errorMsg = '验证码加载或校验失败，请检查网络后重试';
        }
      }
    );
  }

  private confirm(): void {
    if (this.verifiedToken === '') {
      return;
    }
    const token: string = this.verifiedToken;
    this.controller?.close();
    this.onVerified(token);
  }

  build() {
    Column({ space: 14 }) {
      Text('安全验证')
        .fontSize(17)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.text_primary'))
        .width('100%')
        .textAlign(TextAlign.Start)

      Web({ src: $rawfile('captcha.html'), controller: this.webController })
        .javaScriptProxy({
          object: this.bridge,
          name: 'octopCaptcha',
          methodList: ['getConfig', 'onToken', 'onError'],
          controller: this.webController
        })
        .javaScriptAccess(true)
        .domStorageAccess(true)
        .fileAccess(true)
        .height(280)
        .width('100%')
        .borderRadius(12)
        .backgroundColor($r('app.color.bg_input'))

      if (this.errorMsg !== '') {
        Text(this.errorMsg)
          .fontSize(12)
          .fontColor($r('app.color.danger'))
          .width('100%')
          .textAlign(TextAlign.Start)
      }

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
        Button('完成验证')
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
          .enabled(this.verifiedToken !== '')
          .opacity(this.verifiedToken !== '' ? 1 : 0.5)
          .onClick((): void => {
            this.confirm();
          })
      }
      .width('100%')
    }
    .padding(20)
    .width('100%')
    .systemMaterial(UiMaterialKit.sheet())
  }
}
