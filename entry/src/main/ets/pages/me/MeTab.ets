import { pasteboard } from '@kit.BasicServicesKit';
import { SessionStore } from '../../store/SessionStore';
import { AppearanceStore } from '../../store/AppearanceStore';
import { ChangePasswordDialog } from '../../components/ChangePasswordDialog';
import { SettingsRow } from '../../components/SettingsRow';
import { AuthService } from '../../service/AuthService';
import { HttpClient } from '../../net/HttpClient';
import { Log } from '../../utils/Logger';
import { UiMaterialKit } from '../../components/UiMaterialKit';

@Component
export struct MeTab {
  @StorageProp(SessionStore.KEY_DISPLAY_NAME) displayName: string = '';
  @StorageProp(SessionStore.KEY_USERNAME) username: string = '';
  @StorageProp(SessionStore.KEY_ROLE) role: string = '';
  @StorageProp(SessionStore.KEY_BASE_URL) serverUrl: string = '';
  @StorageProp(SessionStore.KEY_AGENT_NAME) agentName: string = '';
  @StorageProp(AppearanceStore.KEY_APPEARANCE) appearanceMode: string = AppearanceStore.MODE_AUTO;
  @Consume('navStack') navStack: NavPathStack;
  @Prop topInset: number = 0;
  @Prop bottomPad: number = 72;
  @State avatarPath: string = '';
  @State avatarFailed: boolean = false;
  @State hasPassword: boolean = false;
  @State ssoLinked: boolean = false;
  @State permissions: Array<string> = [];
  private passwordController: CustomDialogController | null = null;

  aboutToAppear(): void {
    this.refreshProfile();
  }

  /** 拉取 /auth/me 刷新昵称/用户名/角色/头像/权限展示（fire-and-forget） */
  private refreshProfile(): void {
    AuthService.me().then((user): void => {
      AppStorage.setOrCreate(SessionStore.KEY_DISPLAY_NAME, user.displayName);
      AppStorage.setOrCreate(SessionStore.KEY_USERNAME, user.username);
      AppStorage.setOrCreate(SessionStore.KEY_ROLE, user.role);
      this.avatarPath = user.avatarUrl;
      this.avatarFailed = false;
      this.hasPassword = user.hasPassword;
      this.ssoLinked = user.ssoLinked;
      this.permissions = user.permissions;
    }).catch((): void => {
      Log.debug('auth/me refresh failed, keep cached profile');
    });
  }

  /** 头像绝对地址（相对路径 → baseUrl+token 查询参数；Image 组件无法带 Header） */
  private avatarFullUrl(): string {
    if (this.avatarPath === '' || this.avatarFailed) {
      return '';
    }
    if (this.avatarPath.startsWith('http://') || this.avatarPath.startsWith('https://')) {
      return this.avatarPath;
    }
    const base: string = HttpClient.getInstance().getBaseUrl();
    const token: string = HttpClient.getInstance().getToken();
    const sep: string = this.avatarPath.includes('?') ? '&' : '?';
    return `${base}${this.avatarPath}${sep}access_token=${token}`;
  }

  /** 是否显示用户管理入口（admin 或持 users 权限） */
  private canManageUsers(): boolean {
    if (this.role === 'admin') {
      return true;
    }
    for (const item of this.permissions) {
      if (item === 'users') {
        return true;
      }
    }
    return false;
  }

  private showChangePassword(): void {
    this.passwordController = new CustomDialogController({
      builder: ChangePasswordDialog(),
      autoCancel: true
    });
    this.passwordController.open();
  }

  private goExpert(): void {
    AppStorage.setOrCreate(SessionStore.KEY_MAIN_TAB, 0);
  }

  /** 切换外观：浅色 / 深色 / 跟随系统（全局生效并持久化） */
  private setAppearance(mode: string): void {
    if (this.appearanceMode === mode) {
      return;
    }
    AppearanceStore.setMode(mode, getContext(this)).catch((): void => {
      Log.debug('appearance persist failed');
    });
  }

  @Builder
  private appearanceOption(label: string, mode: string) {
    Button(label)
      .fontSize(13)
      .fontWeight(this.appearanceMode === mode ? FontWeight.Medium : FontWeight.Normal)
      .fontColor(this.appearanceMode === mode ? $r('app.color.brand') : $r('app.color.text_secondary'))
      .backgroundColor(this.appearanceMode === mode ? $r('app.color.brand_light') : $r('app.color.bg_input'))
      .borderRadius(12)
      .height(36)
      .layoutWeight(1)
      .onClick((): void => {
        this.setAppearance(mode);
      })
  }

  private async copyServerUrl(): Promise<void> {
    if (this.serverUrl === '') {
      return;
    }
    try {
      const board = pasteboard.getSystemPasteboard();
      const data = pasteboard.createData(pasteboard.MIMETYPE_TEXT_PLAIN, this.serverUrl);
      await board.setData(data);
      this.getUIContext().getPromptAction().showToast({ message: '已复制服务器地址' });
    } catch (e) {
    }
  }

  private confirmLogout(): void {
    this.getUIContext().showAlertDialog({
      title: $r('app.string.me_logout'),
      message: $r('app.string.me_logout_confirm'),
      primaryButton: {
        value: $r('app.string.common_cancel'),
        action: (): void => {
        }
      },
      secondaryButton: {
        value: $r('app.string.common_confirm'),
        action: (): void => {
          SessionStore.logout();
        }
      },
      alignment: DialogAlignment.Bottom
    });
  }

  @Builder
  sectionHeader(title: string) {
    Text(title)
      .fontSize(13)
      .fontWeight(FontWeight.Medium)
      .fontColor($r('app.color.text_tertiary'))
      .margin({ left: 4, bottom: 8 })
  }

  @Builder
  heroBuilder() {
    Button({ type: ButtonType.Normal, stateEffect: false }) {
      Row({ space: 12 }) {
        if (this.avatarFullUrl() !== '') {
          Image(this.avatarFullUrl())
            .width(40)
            .height(40)
            .borderRadius(13)
            .autoResize(true)
            .onError((event: ImageError): void => {
              this.avatarFailed = true;
            })
        } else {
          Column() {
            Image($r('app.media.octop_logo'))
              .width(28)
              .height(28)
              .borderRadius(14)
          }
          .width(40)
          .height(40)
          .justifyContent(FlexAlign.Center)
          .alignItems(HorizontalAlign.Center)
          .backgroundColor($r('app.color.bg_input'))
          .borderRadius(13)
        }

        Column({ space: 2 }) {
          Text(this.displayName === '' ? '未登录' : this.displayName)
            .fontSize(15)
            .fontWeight(FontWeight.Bold)
            .fontColor($r('app.color.text_primary'))
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
          Row({ space: 6 }) {
            Text(`@${this.username === '' ? '-' : this.username}`)
              .fontSize(11)
              .fontColor($r('app.color.text_secondary'))
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
            Text(this.role === 'admin' ? '管理员' : '用户')
              .fontSize(9)
              .fontWeight(FontWeight.Medium)
              .fontColor($r('app.color.brand'))
              .backgroundColor($r('app.color.brand_light'))
              .borderRadius(5)
              .padding({ left: 5, right: 5, top: 1, bottom: 1 })
            if (this.ssoLinked) {
              Text('SSO')
                .fontSize(9)
                .fontWeight(FontWeight.Medium)
                .fontColor($r('app.color.success'))
                .backgroundColor($r('app.color.success_soft'))
                .borderRadius(5)
                .padding({ left: 5, right: 5, top: 1, bottom: 1 })
            }
          }
          .width('100%')
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Start)
      }
      .width('100%')
      .padding({ left: 14, right: 14, top: 10, bottom: 10 })
    }
    .width('100%')
    .borderRadius(18)
    .backgroundColor($r('app.color.bg_card'))
    .systemMaterial(UiMaterialKit.card())
  }

  build() {
    Stack({ alignContent: Alignment.Top }) {
      Scroll() {
        Column({ space: 14 }) {
          this.heroBuilder()

          Column() {
            this.sectionHeader('外观')
            Row({ space: 8 }) {
              this.appearanceOption('浅色', AppearanceStore.MODE_LIGHT)
              this.appearanceOption('深色', AppearanceStore.MODE_DARK)
              this.appearanceOption('跟随系统', AppearanceStore.MODE_AUTO)
            }
            .width('100%')
          }
          .width('100%')
          .alignItems(HorizontalAlign.Start)

          Column() {
            this.sectionHeader('连接')
            Column() {
              SettingsRow({
                icon: $r('sys.symbol.wifi'),
                title: $r('app.string.me_server'),
                subtitle: '点击复制地址',
                trailing: this.serverUrl === '' ? '-' : this.serverUrl,
                showChevron: false,
                onTap: (): void => {
                  this.copyServerUrl();
                }
              })

              Divider()
                .color($r('app.color.divider'))
                .margin({ left: 62 })

              SettingsRow({
                icon: $r('sys.symbol.robot'),
                iconColor: $r('app.color.success'),
                iconBg: $r('app.color.success_soft'),
                title: $r('app.string.me_current_agent'),
                subtitle: this.agentName === '' ? '未选择专家' : this.agentName,
                onTap: (): void => {
                  this.goExpert();
                }
              })
            }
            .width('100%')
            .borderRadius(16)
            .backgroundColor($r('app.color.bg_card'))
            .border({ width: 1, color: $r('app.color.card_stroke') })
            .shadow({ radius: 10, color: '#0A000000', offsetY: 3 })
          }
          .width('100%')
          .alignItems(HorizontalAlign.Start)

          Column() {
            this.sectionHeader('账号')
            Column() {
              SettingsRow({
                icon: $r('sys.symbol.person'),
                title: '账号状态',
                subtitle: this.hasPassword ? '密码已设置' : '未设置密码',
                trailing: this.ssoLinked ? 'SSO 已绑定' : 'SSO 未绑定',
                showChevron: false
              })

              Divider()
                .color($r('app.color.divider'))
                .margin({ left: 62 })

              SettingsRow({
                icon: $r('sys.symbol.lock'),
                iconColor: $r('app.color.warning'),
                iconBg: $r('app.color.warning_soft'),
                title: '修改密码',
                subtitle: '定期更新以保护账号安全',
                onTap: (): void => {
                  this.showChangePassword();
                }
              })

              Divider()
                .color($r('app.color.divider'))
                .margin({ left: 62 })

              SettingsRow({
                icon: $r('sys.symbol.gearshape'),
                title: '服务器设置',
                subtitle: '配置 Octop 服务器地址',
                onTap: (): void => {
                  this.navStack.pushPath(new NavPathInfo('settings', null));
                }
              })

              if (this.canManageUsers()) {
                Divider()
                  .color($r('app.color.divider'))
                  .margin({ left: 62 })

                SettingsRow({
                  icon: $r('sys.symbol.person'),
                  iconColor: $r('app.color.success'),
                  iconBg: $r('app.color.success_soft'),
                  title: '用户管理',
                  subtitle: '用户、角色与权限',
                  onTap: (): void => {
                    this.navStack.pushPath(new NavPathInfo('users', null));
                  }
                })
              }
            }
            .width('100%')
            .borderRadius(16)
            .backgroundColor($r('app.color.bg_card'))
            .border({ width: 1, color: $r('app.color.card_stroke') })
            .shadow({ radius: 10, color: '#0A000000', offsetY: 3 })
          }
          .width('100%')
          .alignItems(HorizontalAlign.Start)

          SettingsRow({
            icon: $r('sys.symbol.arrow_left'),
            title: $r('app.string.me_logout'),
            destructive: true,
            showChevron: false,
            onTap: (): void => {
              this.confirmLogout();
            }
          })

          Text('Octop Link v0.2.0')
            .fontSize(12)
            .fontColor($r('app.color.text_tertiary'))
            .margin({ top: 8 })
        }
        .width('100%')
        .padding({ left: 16, right: 16, top: this.topInset + 112, bottom: this.bottomPad + 16 })
        .alignItems(HorizontalAlign.Start)
      }
      .width('100%')
      .height('100%')
      .scrollBar(BarState.Off)

      // 固定标题层：毛玻璃区 + 无硬边渐隐尾遮罩（标题不随卡片滚动）
      Column() {
        Column({ space: 4 }) {
          Text($r('app.string.me_title'))
            .fontSize(26)
            .fontWeight(FontWeight.Bold)
            .fontColor($r('app.color.text_primary'))
            .width('100%')
            .textAlign(TextAlign.Start)
          Text('账号与服务管理')
            .fontSize(13)
            .fontColor($r('app.color.text_tertiary'))
            .width('100%')
            .textAlign(TextAlign.Start)
        }
        .width('100%')
        .padding({ left: 16, right: 16, top: this.topInset + 10, bottom: 8 })
        .linearGradient({
          angle: 180,
          colors: [[$r('app.color.bar_glass'), 0.0], [$r('app.color.bar_glass'), 1.0]]
        })
        .backgroundBlurStyle(BlurStyle.Thin)

        Column()
          .height(30)
          .width('100%')
          .linearGradient({
            angle: 180,
            colors: [[$r('app.color.scrim_strong'), 0.0], [$r('app.color.scrim_soft'), 0.5], [$r('app.color.scrim_clear'), 1.0]]
          })
          .hitTestBehavior(HitTestMode.None)
      }
      .width('100%')
      .hitTestBehavior(HitTestMode.Transparent)
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.bg_page'))
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
  }
}
