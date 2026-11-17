import { SsoService } from '../../service/SsoService';
import {
  LdapProviderConfigModel,
  OauthProviderConfigModel,
  OidcProviderConfigModel,
  SsoProviderStatusModel,
  SsoTestResultModel
} from '../../model/AdminModels';
import { OctopApiError } from '../../net/HttpClient';
import { EmptyView } from '../../components/EmptyView';
import { ErrorRetry } from '../../components/ErrorRetry';
import { PageHeader } from '../../components/PageHeader';
import { UiMaterialKit } from '../../components/UiMaterialKit';

/** SSO 提供商编辑对话框：OIDC / OAuth（feishu·dingtalk·wecom）/ LDAP 按实际端点字段 */
@CustomDialog
struct SsoProviderEditDialog {
  controller?: CustomDialogController;
  kind: string = '';
  initialDisplayName: string = '';
  initialIssuer: string = '';
  initialClientId: string = '';
  initialScopes: string = '';
  initialDashboardOrigin: string = '';
  initialHasSecret: boolean = false;
  initialServerUrl: string = '';
  initialBindDn: string = '';
  initialUserBaseDn: string = '';
  initialUserFilter: string = '';
  initialUsernameAttribute: string = '';
  onSaved: () => void = (): void => {
  };

  @State displayNameText: string = '';
  @State issuerText: string = '';
  @State clientIdText: string = '';
  @State secretText: string = '';
  @State scopesText: string = '';
  @State originText: string = '';
  @State serverUrlText: string = '';
  @State bindDnText: string = '';
  @State bindPasswordText: string = '';
  @State userBaseDnText: string = '';
  @State userFilterText: string = '';
  @State usernameAttrText: string = '';
  @State submitting: boolean = false;
  @State testing: boolean = false;

  aboutToAppear(): void {
    this.displayNameText = this.initialDisplayName;
    this.issuerText = this.initialIssuer;
    this.clientIdText = this.initialClientId;
    this.scopesText = this.initialScopes;
    this.originText = this.initialDashboardOrigin;
    this.serverUrlText = this.initialServerUrl;
    this.bindDnText = this.initialBindDn;
    this.userBaseDnText = this.initialUserBaseDn;
    this.userFilterText = this.initialUserFilter;
    this.usernameAttrText = this.initialUsernameAttribute;
  }

  private titleText(): string {
    if (this.kind === 'oidc') {
      return '编辑 OIDC 配置';
    }
    if (this.kind === 'ldap') {
      return '编辑 LDAP 配置';
    }
    return '编辑 OAuth 配置';
  }

  private buildBody(): string {
    const body: Record<string, Object> = {};
    if (this.kind === 'ldap') {
      body['display_name'] = this.displayNameText.trim();
      body['server_url'] = this.serverUrlText.trim();
      const bindDn: string = this.bindDnText.trim();
      if (bindDn !== '') {
        body['bind_dn'] = bindDn;
      }
      const bindPassword: string = this.bindPasswordText.trim();
      if (bindPassword !== '') {
        body['bind_password'] = bindPassword;
      }
      body['user_base_dn'] = this.userBaseDnText.trim();
      body['user_filter'] = this.userFilterText.trim();
      body['username_attribute'] = this.usernameAttrText.trim();
      return JSON.stringify(body);
    }
    body['display_name'] = this.displayNameText.trim();
    body['client_id'] = this.clientIdText.trim();
    const secret: string = this.secretText.trim();
    if (secret !== '') {
      body['client_secret'] = secret;
    }
    if (this.kind === 'oidc') {
      body['issuer'] = this.issuerText.trim();
      body['scopes'] = this.scopesText.trim();
    }
    const origin: string = this.originText.trim();
    if (origin !== '') {
      body['dashboard_origin'] = origin;
    }
    return JSON.stringify(body);
  }

  private async submit(): Promise<void> {
    if (this.submitting) {
      return;
    }
    this.submitting = true;
    try {
      const bodyStr: string = this.buildBody();
      if (this.kind === 'oidc') {
        await SsoService.putOidcConfig(bodyStr);
      } else if (this.kind === 'ldap') {
        await SsoService.putLdapConfig(bodyStr);
      } else {
        await SsoService.putOauthConfig(this.kind, bodyStr);
      }
      this.controller?.close();
      this.getUIContext().getPromptAction().showToast({ message: '配置已保存' });
      this.onSaved();
    } catch (e) {
      const message: string = e instanceof OctopApiError
        ? (e.status === 403 ? '需要管理员权限' : e.message) : '保存失败';
      this.getUIContext().getPromptAction().showToast({ message });
    } finally {
      this.submitting = false;
    }
  }

  private async runTest(): Promise<void> {
    if (this.testing) {
      return;
    }
    this.testing = true;
    try {
      const result: SsoTestResultModel = await this.testCurrent();
      const detail: string = result.detail === '' ? (result.ok ? 'OK' : '失败') : result.detail;
      this.getUIContext().getPromptAction().showToast({
        message: result.ok ? `连接成功：${detail}` : `连接失败：${detail}`
      });
    } catch (e) {
      const message: string = e instanceof OctopApiError
        ? (e.status === 403 ? '需要管理员权限' : e.message) : '测试失败';
      this.getUIContext().getPromptAction().showToast({ message });
    } finally {
      this.testing = false;
    }
  }

  private async testCurrent(): Promise<SsoTestResultModel> {
    if (this.kind === 'oidc') {
      return await SsoService.testOidc();
    }
    if (this.kind === 'ldap') {
      return await SsoService.testLdap();
    }
    return await SsoService.testOauth(this.kind);
  }

  build() {
    Column({ space: 14 }) {
      Text(this.titleText())
        .fontSize(17)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.text_primary'))
        .width('100%')
        .textAlign(TextAlign.Start)

      TextInput({
        text: this.displayNameText,
        placeholder: '显示名称'
      })
        .fontSize(14)
        .height(42)
        .backgroundColor($r('app.color.bg_input'))
        .borderRadius(12)
        .onChange((value: string): void => {
          this.displayNameText = value;
        })

      if (this.kind === 'oidc') {
        TextInput({
          text: this.issuerText,
          placeholder: 'Issuer，如 https://sso.example.com'
        })
          .fontSize(14)
          .height(42)
          .backgroundColor($r('app.color.bg_input'))
          .borderRadius(12)
          .onChange((value: string): void => {
            this.issuerText = value;
          })

        TextInput({
          text: this.clientIdText,
          placeholder: 'Client ID'
        })
          .fontSize(14)
          .height(42)
          .backgroundColor($r('app.color.bg_input'))
          .borderRadius(12)
          .onChange((value: string): void => {
            this.clientIdText = value;
          })

        TextInput({
          text: this.secretText,
          placeholder: this.initialHasSecret ? 'Client Secret（已配置，留空保持不变）' : 'Client Secret'
        })
          .fontSize(14)
          .height(42)
          .type(InputType.Password)
          .backgroundColor($r('app.color.bg_input'))
          .borderRadius(12)
          .onChange((value: string): void => {
            this.secretText = value;
          })

        TextInput({
          text: this.scopesText,
          placeholder: 'Scopes，如 openid profile email'
        })
          .fontSize(14)
          .height(42)
          .backgroundColor($r('app.color.bg_input'))
          .borderRadius(12)
          .onChange((value: string): void => {
            this.scopesText = value;
          })

        TextInput({
          text: this.originText,
          placeholder: 'Dashboard Origin（可选）'
        })
          .fontSize(14)
          .height(42)
          .backgroundColor($r('app.color.bg_input'))
          .borderRadius(12)
          .onChange((value: string): void => {
            this.originText = value;
          })
      } else if (this.kind === 'ldap') {
        TextInput({
          text: this.serverUrlText,
          placeholder: '服务器地址，如 ldap://ldap.example.com'
        })
          .fontSize(14)
          .height(42)
          .backgroundColor($r('app.color.bg_input'))
          .borderRadius(12)
          .onChange((value: string): void => {
            this.serverUrlText = value;
          })

        TextInput({
          text: this.bindDnText,
          placeholder: 'Bind DN（服务账号，空为匿名搜索）'
        })
          .fontSize(14)
          .height(42)
          .backgroundColor($r('app.color.bg_input'))
          .borderRadius(12)
          .onChange((value: string): void => {
            this.bindDnText = value;
          })

        TextInput({
          text: this.bindPasswordText,
          placeholder: this.initialHasSecret ? 'Bind 密码（已配置，留空保持不变）' : 'Bind 密码（可选）'
        })
          .fontSize(14)
          .height(42)
          .type(InputType.Password)
          .backgroundColor($r('app.color.bg_input'))
          .borderRadius(12)
          .onChange((value: string): void => {
            this.bindPasswordText = value;
          })

        TextInput({
          text: this.userBaseDnText,
          placeholder: '用户 Base DN'
        })
          .fontSize(14)
          .height(42)
          .backgroundColor($r('app.color.bg_input'))
          .borderRadius(12)
          .onChange((value: string): void => {
            this.userBaseDnText = value;
          })

        TextInput({
          text: this.userFilterText,
          placeholder: '用户过滤器，如 (uid={username})'
        })
          .fontSize(14)
          .height(42)
          .backgroundColor($r('app.color.bg_input'))
          .borderRadius(12)
          .onChange((value: string): void => {
            this.userFilterText = value;
          })

        TextInput({
          text: this.usernameAttrText,
          placeholder: '用户名属性，如 uid'
        })
          .fontSize(14)
          .height(42)
          .backgroundColor($r('app.color.bg_input'))
          .borderRadius(12)
          .onChange((value: string): void => {
            this.usernameAttrText = value;
          })
      } else {
        TextInput({
          text: this.clientIdText,
          placeholder: 'Client ID（App ID）'
        })
          .fontSize(14)
          .height(42)
          .backgroundColor($r('app.color.bg_input'))
          .borderRadius(12)
          .onChange((value: string): void => {
            this.clientIdText = value;
          })

        TextInput({
          text: this.secretText,
          placeholder: this.initialHasSecret ? 'Client Secret（已配置，留空保持不变）' : 'Client Secret'
        })
          .fontSize(14)
          .height(42)
          .type(InputType.Password)
          .backgroundColor($r('app.color.bg_input'))
          .borderRadius(12)
          .onChange((value: string): void => {
            this.secretText = value;
          })

        TextInput({
          text: this.originText,
          placeholder: 'Dashboard Origin（可选）'
        })
          .fontSize(14)
          .height(42)
          .backgroundColor($r('app.color.bg_input'))
          .borderRadius(12)
          .onChange((value: string): void => {
            this.originText = value;
          })
      }

      Text('Secret 仅在保存时提交，服务器不会回显已存值')
        .fontSize(11)
        .fontColor($r('app.color.text_tertiary'))
        .width('100%')

      Row({ space: 12 }) {
        Button(this.testing ? '测试中...' : '测试连接')
          .fontSize(14)
          .height(38)
          .layoutWeight(1)
          .borderRadius(19)
          .backgroundColor($r('app.color.bg_input'))
          .fontColor($r('app.color.text_secondary'))
          .enabled(!this.testing)
          .onClick((): void => {
            this.runTest();
          })
        Button(this.submitting ? '保存中...' : '保存')
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

/**
 * SSO 配置（路由 'sso'）：
 * - 提供商列表（oidc / feishu / dingtalk / wecom / ldap，kind 徽章 oauth·oidc·ldap）
 * - 启用 Toggle（PUT .../config {enabled}）
 * - 点击卡片编辑配置弹窗（client_id/secret/端点等按 API 字段，secret 用密码输入）
 */
@Component
export struct SsoPage {
  @State providers: Array<SsoProviderStatusModel> = [];
  @State loading: boolean = true;
  @State refreshing: boolean = false;
  @State errorMsg: string = '';
  @State operating: boolean = false;
  @State editorOpening: boolean = false;
  private editorController: CustomDialogController | null = null;

  onNavReady(ctx: NavDestinationContext): void {
    this.load();
  }

  /** 统一错误文案：403/权限不足给专门提示 */
  private errorMessage(e: Object, fallback: string): string {
    if (e instanceof OctopApiError) {
      if (e.status === 403) {
        return '需要管理员权限';
      }
      return e.message;
    }
    return fallback;
  }

  private async load(): Promise<void> {
    this.loading = this.providers.length === 0;
    this.errorMsg = '';
    try {
      const oauthProviders: Array<SsoProviderStatusModel> = await SsoService.oauthStatus();
      const list: Array<SsoProviderStatusModel> = oauthProviders;
      try {
        list.push(await SsoService.ldapStatus());
      } catch (e) {
        list.push(new SsoProviderStatusModel('ldap', '', false));
      }
      this.providers = list;
    } catch (e) {
      this.errorMsg = this.errorMessage(e, 'SSO 状态加载失败');
    }
    this.loading = false;
  }

  private kindLabel(kind: string): string {
    if (kind === 'oidc') {
      return 'OIDC';
    }
    if (kind === 'ldap') {
      return 'LDAP';
    }
    if (kind === 'feishu') {
      return '飞书';
    }
    if (kind === 'dingtalk') {
      return '钉钉';
    }
    if (kind === 'wecom') {
      return '企业微信';
    }
    return kind;
  }

  private kindBadge(kind: string): string {
    if (kind === 'oidc' || kind === 'ldap') {
      return kind.toUpperCase();
    }
    return 'OAUTH';
  }

  private kindIcon(kind: string): Resource {
    if (kind === 'ldap') {
      return $r('sys.symbol.person_2');
    }
    if (kind === 'feishu' || kind === 'dingtalk' || kind === 'wecom') {
      return $r('sys.symbol.link');
    }
    return $r('sys.symbol.lock');
  }

  private displayTitle(provider: SsoProviderStatusModel): string {
    if (provider.displayName !== '') {
      return provider.displayName;
    }
    return this.kindLabel(provider.kind);
  }

  /** 启停提供商：OIDC/OAuth/LDAP 各自的 PUT .../config {enabled} */
  private async toggleProvider(provider: SsoProviderStatusModel, on: boolean): Promise<void> {
    if (this.operating) {
      return;
    }
    this.operating = true;
    const body: Record<string, Object> = { 'enabled': on };
    const bodyStr: string = JSON.stringify(body);
    try {
      if (provider.kind === 'oidc') {
        await SsoService.putOidcConfig(bodyStr);
      } else if (provider.kind === 'ldap') {
        await SsoService.putLdapConfig(bodyStr);
      } else {
        await SsoService.putOauthConfig(provider.kind, bodyStr);
      }
      await this.load();
    } catch (e) {
      const message: string = this.errorMessage(e, '操作失败');
      this.getUIContext().getPromptAction().showToast({ message });
      await this.load();
    } finally {
      this.operating = false;
    }
  }

  /** 点击卡片：按 kind 拉取完整配置后打开编辑弹窗 */
  private async openEditor(provider: SsoProviderStatusModel): Promise<void> {
    if (this.editorOpening) {
      return;
    }
    this.editorOpening = true;
    try {
      if (provider.kind === 'oidc') {
        const config: OidcProviderConfigModel = await SsoService.getOidcConfig();
        this.editorController = new CustomDialogController({
          builder: SsoProviderEditDialog({
            kind: 'oidc',
            initialDisplayName: config.displayName,
            initialIssuer: config.issuer,
            initialClientId: config.clientId,
            initialScopes: config.scopes,
            initialDashboardOrigin: config.dashboardOrigin,
            initialHasSecret: config.hasClientSecret,
            onSaved: (): void => {
              this.load();
            }
          }),
          autoCancel: true,
          systemMaterial: UiMaterialKit.sheet()
        });
        this.editorController.open();
      } else if (provider.kind === 'ldap') {
        const config: LdapProviderConfigModel = await SsoService.getLdapConfig();
        this.editorController = new CustomDialogController({
          builder: SsoProviderEditDialog({
            kind: 'ldap',
            initialDisplayName: config.displayName,
            initialServerUrl: config.serverUrl,
            initialBindDn: config.bindDn,
            initialUserBaseDn: config.userBaseDn,
            initialUserFilter: config.userFilter,
            initialUsernameAttribute: config.usernameAttribute,
            initialHasSecret: config.hasBindPassword,
            onSaved: (): void => {
              this.load();
            }
          }),
          autoCancel: true,
          systemMaterial: UiMaterialKit.sheet()
        });
        this.editorController.open();
      } else {
        const config: OauthProviderConfigModel =
          await SsoService.getOauthConfig(provider.kind);
        this.editorController = new CustomDialogController({
          builder: SsoProviderEditDialog({
            kind: provider.kind,
            initialDisplayName: config.displayName,
            initialClientId: config.clientId,
            initialDashboardOrigin: config.dashboardOrigin,
            initialHasSecret: config.hasClientSecret,
            onSaved: (): void => {
              this.load();
            }
          }),
          autoCancel: true,
          systemMaterial: UiMaterialKit.sheet()
        });
        this.editorController.open();
      }
    } catch (e) {
      const message: string = this.errorMessage(e, '配置加载失败');
      this.getUIContext().getPromptAction().showToast({ message });
    } finally {
      this.editorOpening = false;
    }
  }

  build() {
    NavDestination() {
      Column() {
        PageHeader({ title: 'SSO 配置' })

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
        } else if (this.errorMsg !== '') {
          Column() {
            ErrorRetry({
              message: this.errorMsg,
              onRetry: (): void => {
                this.load();
              }
            })
          }
          .layoutWeight(1)
          .width('100%')
          .justifyContent(FlexAlign.Center)
        } else if (this.providers.length === 0) {
          Column() {
            EmptyView({
              title: '暂无 SSO 提供商',
              subtitle: '服务器未返回任何登录提供商',
              icon: $r('sys.symbol.lock')
            })
          }
          .layoutWeight(1)
          .width('100%')
          .justifyContent(FlexAlign.Center)
        } else {
          Refresh({ refreshing: $$this.refreshing }) {
            List({ space: 12 }) {
              ForEach(this.providers, (provider: SsoProviderStatusModel) => {
                ListItem() {
                  Row({ space: 12 }) {
                    Column() {
                      SymbolGlyph(this.kindIcon(provider.kind))
                        .fontSize(20)
                        .fontColor([$r('app.color.brand')])
                    }
                    .width(42)
                    .height(42)
                    .borderRadius(13)
                    .backgroundColor($r('app.color.brand_light'))
                    .justifyContent(FlexAlign.Center)

                    Column({ space: 6 }) {
                      Row({ space: 8 }) {
                        Text(this.kindBadge(provider.kind))
                          .fontSize(10)
                          .fontWeight(FontWeight.Medium)
                          .fontColor(provider.kind === 'ldap' ? $r('app.color.warning')
                            : (provider.kind === 'oidc' ? $r('app.color.brand')
                              : $r('app.color.success')))
                          .backgroundColor(provider.kind === 'ldap' ? $r('app.color.warning_soft')
                            : (provider.kind === 'oidc' ? $r('app.color.brand_light')
                              : $r('app.color.success_soft')))
                          .borderRadius(6)
                          .padding({ left: 6, right: 6, top: 2, bottom: 2 })
                        Text(this.displayTitle(provider))
                          .fontSize(15)
                          .fontWeight(FontWeight.Medium)
                          .fontColor($r('app.color.text_primary'))
                          .maxLines(1)
                          .textOverflow({ overflow: TextOverflow.Ellipsis })
                          .layoutWeight(1)
                      }
                      .width('100%')

                      Row({ space: 6 }) {
                        if (provider.enabled) {
                          Text('已启用')
                            .fontSize(11)
                            .fontColor($r('app.color.success'))
                        } else {
                          Text('未启用')
                            .fontSize(11)
                            .fontColor($r('app.color.text_tertiary'))
                        }
                        Text('点击卡片编辑配置')
                          .fontSize(11)
                          .fontColor($r('app.color.text_tertiary'))
                      }
                      .width('100%')
                    }
                    .layoutWeight(1)
                    .alignItems(HorizontalAlign.Start)
                    .onClick((): void => {
                      this.openEditor(provider);
                    })

                    Toggle({ type: ToggleType.Switch, isOn: provider.enabled })
                      .onChange((isOn: boolean): void => {
                        this.toggleProvider(provider, isOn);
                      })

                    SymbolGlyph($r('sys.symbol.chevron_right'))
                      .fontSize(14)
                      .fontColor([$r('app.color.text_tertiary')])
                      .onClick((): void => {
                        this.openEditor(provider);
                      })
                  }
                  .width('100%')
                  .padding(14)
                  .borderRadius(16)
                  .backgroundColor($r('app.color.bg_card'))
                  .border({ width: 1, color: $r('app.color.divider') })
                }
              }, (provider: SsoProviderStatusModel) => provider.kind)

              ListItem() {
                Text('Secret / Bind 密码为只写字段，留空表示保持服务器已存值；测试连接使用服务器当前保存的配置')
                  .fontSize(11)
                  .fontColor($r('app.color.text_tertiary'))
                  .width('100%')
                  .textAlign(TextAlign.Start)
              }
            }
            .width('100%')
            .height('100%')
            .padding({ left: 14, right: 14, top: 4 })
            .scrollBar(BarState.Off)
          }
          .layoutWeight(1)
          .width('100%')
          .onRefreshing((): void => {
            this.load();
          })
        }
      }
      .width('100%')
      .height('100%')
    }
    .hideTitleBar(true)
    .backgroundColor($r('app.color.bg_page'))
    .onReady((ctx: NavDestinationContext): void => {
      this.onNavReady(ctx);
    })
  }
}
