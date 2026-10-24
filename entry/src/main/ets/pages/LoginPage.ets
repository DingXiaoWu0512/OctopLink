import { LoginResultModel } from '../model/AuthModels';
import { OctopApiError } from '../net/HttpClient';
import { AuthService } from '../service/AuthService';
import { SessionStore } from '../store/SessionStore';
import { UrlUtil } from '../utils/UrlUtil';
import { UiMaterialKit } from '../components/UiMaterialKit';

@Component
export struct LoginPage {
  @State serverUrl: string = '';
  @State username: string = '';
  @State password: string = '';
  @State showPassword: boolean = false;
  @State loading: boolean = false;
  @State errorMsg: string = '';

  aboutToAppear(): void {
    const saved: string = AppStorage.get<string>(SessionStore.KEY_BASE_URL) ?? '';
    this.serverUrl = saved;
  }

  private async doLogin(): Promise<void> {
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
      const result: LoginResultModel = await AuthService.login(url, username, this.password);
      SessionStore.applyLogin(url, result);
    } catch (e) {
      if (e instanceof OctopApiError) {
        if (e.code === 'AUTH_FAILED') {
          this.errorMsg = '用户名或密码错误';
        } else if (e.code === 'CAPTCHA_REQUIRED') {
          this.errorMsg = '该服务器开启了登录验证码，请先在 Web 端登录后再使用 App';
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

  build() {
    Column() {
      Scroll() {
        Column({ space: 14 }) {
          Column({ space: 12 }) {
            Text('O')
              .fontSize(38)
              .fontWeight(FontWeight.Bold)
              .fontColor($r('app.color.text_on_brand'))
              .width(84)
              .height(84)
              .textAlign(TextAlign.Center)
              .borderRadius(26)
              .linearGradient({
                angle: 140,
                colors: [[$r('app.color.brand_grad_start'), 0], [$r('app.color.brand_grad_end'), 1]]
              })
              .shadow({ radius: 20, color: '#330A59F7', offsetX: 0, offsetY: 8 })
            Column({ space: 6 }) {
              Text('Octop Link')
                .fontSize(30)
                .fontWeight(FontWeight.Bold)
                .fontColor($r('app.color.text_primary'))
              Text($r('app.string.app_slogan'))
                .fontSize(14)
                .fontColor($r('app.color.text_secondary'))
            }
          }
          .margin({ top: 60, bottom: 44 })
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
            .systemMaterial(UiMaterialKit.button())
            .margin({ top: 10 })
            .enabled(!this.loading)
            .onClick((): void => {
              this.doLogin();
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
        .padding({ left: 28, right: 28 })
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
