import { curves } from '@kit.ArkUI';
import { LoginResultModel } from '../model/AuthModels';
import { OctopApiError } from '../net/HttpClient';
import { AuthService } from '../service/AuthService';
import { SessionStore } from '../store/SessionStore';
import { UrlUtil } from '../utils/UrlUtil';
import { CaptchaDialog } from '../components/CaptchaDialog';
import { UiMaterialKit } from '../components/UiMaterialKit';

/**
 * 登录页：账号密码登录（含验证码流程）+ 会动的吉祥物 Logo。
 * SSO 登录与邀请码注册的完整链路保留在 SsoService / InviteService 服务层，按需再接 UI。
 */
@Component
export struct LoginPage {
  @State serverUrl: string = '';
  @State username: string = '';
  @State password: string = '';
  @State showPassword: boolean = false;
  @State loading: boolean = false;
  @State errorMsg: string = '';

  // 登录页 Logo 吉祥物动效（待机呼吸 + 浮动 + 轻摆，进场弹性放大）
  @State logoBreathe: number = 1;
  @State logoBob: number = 0;
  @State logoTilt: number = 0;
  @State logoPop: number = 0.6;

  private captchaController: CustomDialogController | null = null;

  aboutToAppear(): void {
    const saved: string = AppStorage.get<string>(SessionStore.KEY_BASE_URL) ?? '';
    this.serverUrl = saved;
    this.startLogoMotion();
  }

  /** Logo 待机动效：进场弹性放大，随后呼吸/浮动/轻摆无限循环（与聊天页宠物同款节奏） */
  private startLogoMotion(): void {
    const ui = this.getUIContext();
    ui.animateTo({
      duration: 600,
      curve: curves.springMotion(0.34, 0.6)
    }, () => {
      this.logoPop = 1;
    });
    ui.animateTo({
      duration: 2600,
      curve: Curve.EaseInOut,
      iterations: -1,
      playMode: PlayMode.Alternate
    }, () => {
      this.logoBreathe = 1.035;
      this.logoBob = -3;
      this.logoTilt = 3;
    });
  }

  private async doLogin(captchaToken: string = ''): Promise<void> {
    if (this.loading) {
      return;
    }
    const url: string = UrlUtil.normalizeServerUrl(this.serverUrl);
    const username: string = this.username.trim();
    if (this.serverUrl.trim() === '' || username === '' || this.password === '') {
      this.errorMsg = '请填写服务器地址、用户名和密码';
      return;
    }
    this.loading = true;
    this.errorMsg = '';
    try {
      const result: LoginResultModel =
        await AuthService.login(url, username, this.password, captchaToken);
      SessionStore.applyLogin(url, result);
    } catch (e) {
      if (e instanceof OctopApiError) {
        if (e.code === 'AUTH_FAILED') {
          this.errorMsg = '用户名或密码错误';
        } else if (e.code === 'CAPTCHA_REQUIRED') {
          if (captchaToken === '') {
            this.startCaptchaFlow();
          } else {
            this.errorMsg = '验证未通过，请重新登录并再次完成验证';
          }
        } else if (e.code === 'CAPTCHA_FAILED') {
          this.errorMsg = '验证码校验失败，请重新完成验证';
        } else if (e.code === 'SETUP_REQUIRED') {
          this.errorMsg = '服务器尚未初始化，请先在 Web 端完成管理员设置';
        } else if (e.code === 'LOGIN_LOCKED') {
          this.errorMsg = '登录尝试次数过多，请稍后再试';
        } else if (e.code === 'NETWORK_ERROR') {
          this.errorMsg = '无法连接服务器，请检查地址与网络';
        } else {
          this.errorMsg = e.message;
        }
      } else {
        this.errorMsg = '登录失败，请重试';
      }
    } finally {
      this.loading = false;
    }
  }

  /** 登录被要求验证码：拉取配置，slider 直接重试，强 provider 弹 Web 验证 */
  private async startCaptchaFlow(): Promise<void> {
    try {
      const config = await AuthService.captchaConfig();
      if (config.noChallengeNeeded) {
        this.errorMsg = '该服务器开启了登录验证，请在 Web 端完成一次登录后再使用 App';
        return;
      }
      this.captchaController = new CustomDialogController({
        builder: CaptchaDialog({
          provider: config.provider,
          siteKey: config.siteKey,
          onVerified: (token: string): void => {
            this.doLogin(token);
          }
        }),
        autoCancel: false,
        systemMaterial: UiMaterialKit.sheet()
      });
      this.captchaController.open();
    } catch (e) {
      this.errorMsg = '无法获取验证码配置，请检查服务器地址与网络';
    }
  }

  build() {
    Column() {
      Scroll() {
        Column({ space: 14 }) {
          Column({ space: 14 }) {
            Column() {
              Image($rawfile('pet/peek.webp'))
                .width(96)
                .height(96)
                .objectFit(ImageFit.Contain)
                .scale({
                  x: this.logoPop * this.logoBreathe,
                  y: this.logoPop * this.logoBreathe
                })
                .translate({ y: this.logoBob })
                .rotate({ angle: this.logoTilt })
            }
            .width(116)
            .height(116)
            .justifyContent(FlexAlign.Center)
            .alignItems(HorizontalAlign.Center)
            .borderRadius(34)
            .linearGradient({
              angle: 140,
              colors: [[$r('app.color.brand_grad_start'), 0], [$r('app.color.brand_grad_end'), 1]]
            })
            .shadow({ radius: 24, color: '#330A59F7', offsetX: 0, offsetY: 10 })
            .margin({ top: 120 })
            .onClick((): void => {
              // 点一下：弹跳互动
              const ui = this.getUIContext();
              this.logoPop = 0.86;
              ui.animateTo({
                duration: 500,
                curve: curves.springMotion(0.34, 0.6)
              }, () => {
                this.logoPop = 1;
              });
            })
            .opacity(this.logoPop > 0 ? 1 : 1)

            Column({ space: 6 }) {
              Text('Octop Link')
                .fontSize(30)
                .fontWeight(FontWeight.Bold)
                .fontColor($r('app.color.text_primary'))
              Text($r('app.string.app_slogan'))
                .fontSize(14)
                .fontColor($r('app.color.text_secondary'))
            }
            .alignItems(HorizontalAlign.Center)
          }
          .width('100%')
          .margin({ bottom: 30 })
          .alignItems(HorizontalAlign.Center)

          Column({ space: 8 }) {
            Text($r('app.string.login_server_url'))
              .fontSize(14)
              .fontWeight(FontWeight.Medium)
              .fontColor($r('app.color.text_primary'))
            TextInput({ text: this.serverUrl, placeholder: $r('app.string.login_server_url_placeholder') })
              .fontSize(15)
              .height(48)
              .backgroundColor($r('app.color.bg_input'))
              .borderRadius(14)
              .padding({ left: 14, right: 14 })
              .onChange((value: string): void => {
                this.serverUrl = value;
              })
          }
          .width('100%')
          .alignItems(HorizontalAlign.Start)

          Column({ space: 8 }) {
            Text($r('app.string.login_username'))
              .fontSize(14)
              .fontWeight(FontWeight.Medium)
              .fontColor($r('app.color.text_primary'))
            TextInput({ text: this.username, placeholder: $r('app.string.login_username_placeholder') })
              .fontSize(15)
              .height(48)
              .backgroundColor($r('app.color.bg_input'))
              .borderRadius(14)
              .padding({ left: 14, right: 14 })
              .onChange((value: string): void => {
                this.username = value;
              })
          }
          .width('100%')
          .alignItems(HorizontalAlign.Start)

          Column({ space: 8 }) {
            Text($r('app.string.login_password'))
              .fontSize(14)
              .fontWeight(FontWeight.Medium)
              .fontColor($r('app.color.text_primary'))
            TextInput({ text: this.password, placeholder: $r('app.string.login_password_placeholder') })
              .fontSize(15)
              .height(48)
              .backgroundColor($r('app.color.bg_input'))
              .borderRadius(14)
              .padding({ left: 14, right: 14 })
              .type(InputType.Password)
              .showPasswordIcon(true)
              .onChange((value: string): void => {
                this.password = value;
              })
          }
          .width('100%')
          .alignItems(HorizontalAlign.Start)

          Button(this.loading ? '正在登录...' : '登 录')
            .width('100%')
            .height(48)
            .fontSize(16)
            .fontWeight(FontWeight.Bold)
            .borderRadius(24)
            .backgroundColor($r('app.color.brand_light'))
            .fontColor($r('app.color.brand'))
            .margin({ top: 10 })
            .enabled(!this.loading)
            .onClick((): void => {
              this.doLogin();
            })

          Button('试用 App（无任何数据，只有界面）')
            .width('100%')
            .height(48)
            .fontSize(16)
            .fontWeight(FontWeight.Bold)
            .borderRadius(24)
            .backgroundColor($r('app.color.bg_input'))
            .fontColor($r('app.color.text_secondary'))
            .margin({ top: 12 })
            .enabled(!this.loading)
            .onClick((): void => {
              SessionStore.enterTrial();
            })

          if (this.errorMsg !== '') {
            Text(this.errorMsg)
              .fontSize(13)
              .fontColor($r('app.color.danger'))
              .textAlign(TextAlign.Center)
              .width('100%')
              .margin({ top: 4 })
          }
        }
        .width('100%')
        .padding({ left: 28, right: 28, bottom: 40 })
        .alignItems(HorizontalAlign.Start)
      }
      .layoutWeight(1)
      .width('100%')
      .align(Alignment.Top)
      .scrollBar(BarState.Off)
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.bg_card'))
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
  }
}
