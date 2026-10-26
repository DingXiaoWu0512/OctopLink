import { HitlSettings, MobileCapability, CaptchaSettingsModel, CaptchaProviderEntry } from '../../model/WorkspaceModels';
import { SettingsService } from '../../service/WorkspaceService';
import { OctopUserModel } from '../../model/AuthModels';
import { AuthService } from '../../service/AuthService';
import { SessionStore } from '../../store/SessionStore';
import { AppPrefs } from '../../store/AppPrefs';
import { HttpClient, OctopApiError } from '../../net/HttpClient';
import { UrlUtil } from '../../utils/UrlUtil';
import { PageHeader } from '../../components/PageHeader';
import { SettingsRow } from '../../components/SettingsRow';
import { UiMaterialKit } from '../../components/UiMaterialKit';

/** 服务器设置：服务器地址（可编辑）/只读服务器信息/HITL/移动端能力/验证码（管理员） */
@Component
export struct SettingsPage {
  @StorageProp(SessionStore.KEY_BASE_URL) baseUrl: string = '';
  @State loading: boolean = true;
  @State timezone: string = '…';
  @State uploadLimit: string = '…';
  @State hitlEnabled: string = '…';
  @State hitlGuard: string = '…';
  @State hitlApprovalUi: string = '…';
  @State mobileStatus: string = '…';
  @State serverSheetOpen: boolean = false;
  @State serverUrlDraft: string = '';
  @State canCaptcha: boolean = false;
  @State captcha: CaptchaSettingsModel | null = null;
  @State captchaLoading: boolean = false;
  @State savingCaptcha: boolean = false;
  @State captSiteKeys: Record<string, string> = {};
  @State captSecrets: Record<string, string> = {};
  @State captCamIds: Record<string, string> = {};
  @State captCamSecrets: Record<string, string> = {};

  private static readonly FAILED: string = '获取失败';

  private async load(): Promise<void> {
    this.loading = true;
    try {
      const tz: string = await SettingsService.getTimezone();
      this.timezone = tz === '' ? SettingsPage.FAILED : tz;
    } catch (e) {
      this.timezone = SettingsPage.FAILED;
    }
    try {
      const mb: number = await SettingsService.getMaxUploadMb();
      this.uploadLimit = mb > 0 ? `${mb} MiB` : SettingsPage.FAILED;
    } catch (e) {
      this.uploadLimit = SettingsPage.FAILED;
    }
    try {
      const hitl: HitlSettings = await SettingsService.getHitl();
      this.hitlEnabled = hitl.enabled ? '已启用' : '未启用';
      this.hitlGuard = hitl.toolGuardRequireApproval ? '需要' : '不需要';
      this.hitlApprovalUi = hitl.showApprovalUi ? '显示' : '隐藏';
    } catch (e) {
      this.hitlEnabled = SettingsPage.FAILED;
      this.hitlGuard = SettingsPage.FAILED;
      this.hitlApprovalUi = SettingsPage.FAILED;
    }
    try {
      const mobile: MobileCapability = await SettingsService.getMobileCapability();
      this.mobileStatus = mobile.enabled ? `已启用（${mobile.backend}）` : '未启用';
    } catch (e) {
      this.mobileStatus = SettingsPage.FAILED;
    }
    this.loading = false;
    this.checkCaptchaPermission();
  }

  /** 仅持 captcha 权限（admin 全量）时展示验证码管理节 */
  private checkCaptchaPermission(): void {
    AuthService.me().then((user: OctopUserModel): void => {
      if (user.hasPermission('captcha')) {
        this.canCaptcha = true;
        this.loadCaptcha();
      }
    }).catch((): void => {
      this.canCaptcha = false;
    });
  }

  private async loadCaptcha(): Promise<void> {
    this.captchaLoading = true;
    try {
      const captcha: CaptchaSettingsModel = await SettingsService.getCaptcha();
      this.captcha = captcha;
      const siteKeys: Record<string, string> = {};
      const secrets: Record<string, string> = {};
      const camIds: Record<string, string> = {};
      const camSecrets: Record<string, string> = {};
      for (const entry of captcha.providers) {
        siteKeys[entry.kind] = entry.provider.siteKey;
        secrets[entry.kind] = '';
        camIds[entry.kind] = entry.provider.camSecretId;
        camSecrets[entry.kind] = '';
      }
      this.captSiteKeys = siteKeys;
      this.captSecrets = secrets;
      this.captCamIds = camIds;
      this.captCamSecrets = camSecrets;
    } catch (e) {
      this.captcha = null;
    }
    this.captchaLoading = false;
  }

  /** 切换启用的验证码 Provider：PUT {active: kind} */
  private async activateCaptcha(kind: string): Promise<void> {
    if (this.savingCaptcha) {
      return;
    }
    this.savingCaptcha = true;
    try {
      const body: Record<string, Object> = { 'active': kind };
      await SettingsService.putCaptcha(JSON.stringify(body));
      this.getUIContext().getPromptAction().showToast({ message: '验证码已切换' });
      await this.loadCaptcha();
    } catch (e) {
      const message: string = e instanceof OctopApiError ? e.message : '切换失败';
      this.getUIContext().getPromptAction().showToast({ message });
    }
    this.savingCaptcha = false;
  }

  /** 保存单个 Provider 配置：PUT {providers: {kind: {...}}}（空 secret 保留已存值） */
  private async saveCaptchaProvider(entry: CaptchaProviderEntry): Promise<void> {
    if (this.savingCaptcha) {
      return;
    }
    const provider: Record<string, Object> = {};
    const siteKey: string = (this.captSiteKeys[entry.kind] ?? '').trim();
    const secret: string = (this.captSecrets[entry.kind] ?? '').trim();
    const camId: string = (this.captCamIds[entry.kind] ?? '').trim();
    const camSecret: string = (this.captCamSecrets[entry.kind] ?? '').trim();
    if (siteKey !== '') {
      provider['site_key'] = siteKey;
    }
    if (secret !== '') {
      provider['secret'] = secret;
    }
    if (camId !== '') {
      provider['cam_secret_id'] = camId;
    }
    if (camSecret !== '') {
      provider['cam_secret'] = camSecret;
    }
    if (siteKey === '' && entry.provider.siteKey === '') {
      this.getUIContext().getPromptAction().showToast({ message: '请填写 site_key' });
      return;
    }
    this.savingCaptcha = true;
    try {
      const providersWrap: Record<string, Object> = {};
      providersWrap[entry.kind] = provider;
      const body: Record<string, Object> = { 'providers': providersWrap };
      await SettingsService.putCaptcha(JSON.stringify(body));
      this.getUIContext().getPromptAction().showToast({ message: '配置已保存' });
      await this.loadCaptcha();
    } catch (e) {
      const message: string = e instanceof OctopApiError ? e.message : '保存失败';
      this.getUIContext().getPromptAction().showToast({ message });
    }
    this.savingCaptcha = false;
  }

  /** 保存服务器地址：持久化 + 切 HttpClient + 清会话回登录页重新登录 */
  private saveServerUrl(): void {
    const normalized: string = UrlUtil.normalizeServerUrl(this.serverUrlDraft);
    if (normalized === '') {
      this.getUIContext().getPromptAction().showToast({ message: '请输入服务器地址' });
      return;
    }
    this.getUIContext().showAlertDialog({
      title: '切换服务器',
      message: '切换服务器后将退出当前登录，需要在登录页重新登录新服务器，确定吗？',
      primaryButton: {
        value: $r('app.string.common_cancel'),
        action: (): void => {
        }
      },
      secondaryButton: {
        value: $r('app.string.common_confirm'),
        action: (): void => {
          this.serverSheetOpen = false;
          AppPrefs.getInstance().setServerUrl(normalized);
          HttpClient.getInstance().setBaseUrl(normalized);
          AppStorage.setOrCreate(SessionStore.KEY_BASE_URL, normalized);
          SessionStore.handleUnauthorized();
        }
      },
      alignment: DialogAlignment.Bottom
    });
  }

  @Builder
  sectionTitle(title: string) {
    Text(title)
      .fontSize(13)
      .fontWeight(FontWeight.Medium)
      .fontColor($r('app.color.text_tertiary'))
      .width('100%')
      .padding({ left: 20, right: 20, top: 18, bottom: 8 })
  }

  @Builder
  serverSheetBuilder() {
    Column({ space: 14 }) {
      Text('服务器地址')
        .fontSize(17)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.text_primary'))
        .width('100%')

      TextInput({ text: this.serverUrlDraft, placeholder: '如 http://192.168.3.2:8088' })
        .fontSize(14)
        .height(44)
        .backgroundColor($r('app.color.bg_input'))
        .borderRadius(12)
        .onChange((value: string): void => {
          this.serverUrlDraft = value;
        })

      Text('切换服务器后将退出当前登录，需要在登录页重新登录新服务器')
        .fontSize(11)
        .fontColor($r('app.color.text_tertiary'))
        .width('100%')

      Button('保存并重新登录')
        .fontSize(15)
        .fontWeight(FontWeight.Bold)
        .height(42)
        .width('100%')
        .borderRadius(16)
        .backgroundColor($r('app.color.brand'))
        .fontColor($r('app.color.text_on_brand'))
        .onClick((): void => {
          this.saveServerUrl();
        })
    }
    .padding({ left: 18, right: 18, top: 18, bottom: 30 })
    .width('100%')
  }

  @Builder
  captchaProviderCard(entry: CaptchaProviderEntry) {
    Column({ space: 10 }) {
      Row({ space: 8 }) {
        Text(entry.kind)
          .fontSize(15)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.text_primary'))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .constraintSize({ maxWidth: 180 })
        if (this.captcha !== null && this.captcha.active === entry.kind) {
          Text('已启用')
            .fontSize(10)
            .fontColor($r('app.color.brand'))
            .backgroundColor($r('app.color.brand_light'))
            .borderRadius(6)
            .padding({ left: 8, right: 8, top: 2, bottom: 2 })
        }
        Blank()
        if (this.captcha !== null && this.captcha.active !== entry.kind) {
          Button(this.savingCaptcha ? '...' : '启用')
            .fontSize(12)
            .height(28)
            .borderRadius(14)
            .padding({ left: 14, right: 14 })
            .backgroundColor($r('app.color.brand_light'))
            .fontColor($r('app.color.brand'))
            .enabled(!this.savingCaptcha)
            .onClick((): void => {
              this.activateCaptcha(entry.kind);
            })
        }
      }
      .width('100%')

      TextInput({ text: this.captSiteKeys[entry.kind] ?? '', placeholder: 'site_key' })
        .fontSize(13)
        .height(40)
        .backgroundColor($r('app.color.bg_input'))
        .borderRadius(10)
        .onChange((value: string): void => {
          this.captSiteKeys[entry.kind] = value;
        })

      TextInput({
        text: this.captSecrets[entry.kind] ?? '',
        placeholder: entry.provider.hasSecret ? 'secret（已配置，留空保持不变）' : 'secret'
      })
        .fontSize(13)
        .height(40)
        .type(InputType.Password)
        .backgroundColor($r('app.color.bg_input'))
        .borderRadius(10)
        .onChange((value: string): void => {
          this.captSecrets[entry.kind] = value;
        })

      TextInput({ text: this.captCamIds[entry.kind] ?? '', placeholder: 'cam_secret_id' })
        .fontSize(13)
        .height(40)
        .backgroundColor($r('app.color.bg_input'))
        .borderRadius(10)
        .onChange((value: string): void => {
          this.captCamIds[entry.kind] = value;
        })

      TextInput({
        text: this.captCamSecrets[entry.kind] ?? '',
        placeholder: entry.provider.camSecret !== '' ? 'cam_secret（已配置，留空保持不变）' : 'cam_secret'
      })
        .fontSize(13)
        .height(40)
        .type(InputType.Password)
        .backgroundColor($r('app.color.bg_input'))
        .borderRadius(10)
        .onChange((value: string): void => {
          this.captCamSecrets[entry.kind] = value;
        })

      Button(this.savingCaptcha ? '保存中…' : '保存配置')
        .fontSize(13)
        .height(36)
        .width('100%')
        .borderRadius(14)
        .backgroundColor($r('app.color.brand_light'))
        .fontColor($r('app.color.brand'))
        .enabled(!this.savingCaptcha)
        .onClick((): void => {
          this.saveCaptchaProvider(entry);
        })
    }
    .padding(14)
    .borderRadius(16)
    .backgroundColor($r('app.color.bg_card'))
    .border({ width: 1, color: $r('app.color.card_stroke') })
    .margin({ left: 14, right: 14 })
  }

  build() {
    NavDestination() {
      Column() {
        PageHeader({ title: '服务器设置' })

        if (this.loading) {
          Column() {
            LoadingProgress()
              .width(36)
              .height(36)
              .color($r('app.color.brand'))
          }
          .layoutWeight(1)
          .width('100%')
          .justifyContent(FlexAlign.Center)
        } else {
          Scroll() {
            Column() {
              this.sectionTitle('服务器')
              Column() {
                SettingsRow({
                  icon: $r('sys.symbol.gearshape'),
                  title: '服务器地址',
                  subtitle: '修改后需重新登录',
                  trailing: this.baseUrl,
                  showChevron: true,
                  onTap: (): void => {
                    this.serverUrlDraft = this.baseUrl;
                    this.serverSheetOpen = true;
                  }
                })
              }
              .borderRadius(18)
              .backgroundColor($r('app.color.bg_card'))
              .border({ width: 1, color: $r('app.color.card_stroke') })
              .margin({ left: 14, right: 14 })

              this.sectionTitle('服务器信息')
              Column() {
                SettingsRow({
                  icon: $r('sys.symbol.clock'),
                  title: '服务器时区',
                  trailing: this.timezone,
                  trailingFailed: this.timezone === SettingsPage.FAILED,
                  showChevron: false
                })
                Divider()
                  .color($r('app.color.divider'))
                  .margin({ left: 62 })
                SettingsRow({
                  icon: $r('sys.symbol.paperclip'),
                  title: '上传大小上限',
                  trailing: this.uploadLimit,
                  trailingFailed: this.uploadLimit === SettingsPage.FAILED,
                  showChevron: false
                })
              }
              .borderRadius(18)
              .backgroundColor($r('app.color.bg_card'))
              .border({ width: 1, color: $r('app.color.card_stroke') })
              .margin({ left: 14, right: 14 })

              this.sectionTitle('人工审批（HITL）')
              Column() {
                SettingsRow({
                  icon: $r('sys.symbol.face_smiling'),
                  title: '人工审批',
                  trailing: this.hitlEnabled,
                  trailingFailed: this.hitlEnabled === SettingsPage.FAILED,
                  showChevron: false
                })
                Divider()
                  .color($r('app.color.divider'))
                  .margin({ left: 62 })
                SettingsRow({
                  icon: $r('sys.symbol.lock'),
                  iconColor: $r('app.color.warning'),
                  iconBg: $r('app.color.warning_soft'),
                  title: '工具防护需审批',
                  trailing: this.hitlGuard,
                  trailingFailed: this.hitlGuard === SettingsPage.FAILED,
                  showChevron: false
                })
                Divider()
                  .color($r('app.color.divider'))
                  .margin({ left: 62 })
                SettingsRow({
                  icon: $r('sys.symbol.eye'),
                  iconColor: $r('app.color.success'),
                  iconBg: $r('app.color.success_soft'),
                  title: '审批界面',
                  trailing: this.hitlApprovalUi,
                  trailingFailed: this.hitlApprovalUi === SettingsPage.FAILED,
                  showChevron: false
                })
              }
              .borderRadius(18)
              .backgroundColor($r('app.color.bg_card'))
              .border({ width: 1, color: $r('app.color.card_stroke') })
              .margin({ left: 14, right: 14 })

              this.sectionTitle('移动端能力')
              Column() {
                SettingsRow({
                  icon: $r('sys.symbol.dot_radiowaves_left_and_right'),
                  iconColor: $r('app.color.success'),
                  iconBg: $r('app.color.success_soft'),
                  title: '远程移动端',
                  trailing: this.mobileStatus,
                  trailingFailed: this.mobileStatus === SettingsPage.FAILED,
                  showChevron: false
                })
              }
              .borderRadius(18)
              .backgroundColor($r('app.color.bg_card'))
              .border({ width: 1, color: $r('app.color.card_stroke') })
              .margin({ left: 14, right: 14 })

              if (this.canCaptcha) {
                this.sectionTitle('验证码（管理员）')
                if (this.captchaLoading) {
                  Column() {
                    LoadingProgress()
                      .width(24)
                      .height(24)
                      .color($r('app.color.brand'))
                  }
                  .width('100%')
                  .padding({ top: 20, bottom: 20 })
                } else if (this.captcha !== null) {
                  Column() {
                    SettingsRow({
                      icon: $r('sys.symbol.lock'),
                      title: '当前启用',
                      trailing: this.captcha.active === '' ? '未启用' : this.captcha.active,
                      showChevron: false
                    })
                    Divider()
                      .color($r('app.color.divider'))
                      .margin({ left: 62 })
                    SettingsRow({
                      icon: $r('sys.symbol.gearshape'),
                      title: '配置来源',
                      trailing: this.captcha.source === '' ? '-' : this.captcha.source,
                      showChevron: false
                    })
                    Divider()
                      .color($r('app.color.divider'))
                      .margin({ left: 62 })
                    SettingsRow({
                      icon: $r('sys.symbol.checkmark'),
                      title: 'v3 最低分',
                      trailing: `${this.captcha.v3MinScore}`,
                      showChevron: false
                    })
                  }
                  .borderRadius(18)
                  .backgroundColor($r('app.color.bg_card'))
                  .border({ width: 1, color: $r('app.color.card_stroke') })
                  .margin({ left: 14, right: 14 })

                  ForEach(this.captcha.providers, (entry: CaptchaProviderEntry) => {
                    Column() {
                      this.captchaProviderCard(entry)
                    }
                    .margin({ top: 10 })
                  }, (entry: CaptchaProviderEntry) => entry.kind)
                }
              }

              Text('时区/上传上限/HITL/移动端能力为服务器只读配置，如需修改请在 Web 端管理后台操作')
                .fontSize(12)
                .fontColor($r('app.color.text_tertiary'))
                .width('100%')
                .padding({ left: 20, right: 20, top: 16 })
            }
            .width('100%')
            .padding({ bottom: 28 })
          }
          .layoutWeight(1)
          .width('100%')
          .scrollBar(BarState.Off)
          .bindSheet($$this.serverSheetOpen, this.serverSheetBuilder, {
            systemMaterial: UiMaterialKit.sheet(),
            height: 300,
            showClose: true,
            onDisappear: (): void => {
              this.serverUrlDraft = '';
            }
          })
        }
      }
      .width('100%')
      .height('100%')
    }
    .hideTitleBar(true)
    .backgroundColor($r('app.color.bg_page'))
    .onReady((ctx: NavDestinationContext): void => {
      this.load();
    })
  }
}
