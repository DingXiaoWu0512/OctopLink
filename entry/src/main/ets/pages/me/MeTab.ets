import { LengthMetrics } from '@kit.ArkUI';
import { HdsNavigation, HdsNavigationTitleMode, ScrollEffectType, hdsMaterial } from '@kit.UIDesignKit';
import { bundleManager } from '@kit.AbilityKit';
import { pasteboard } from '@kit.BasicServicesKit';
import { fileIo, picker } from '@kit.CoreFileKit';
import { SessionStore } from '../../store/SessionStore';
import { AppearanceStore } from '../../store/AppearanceStore';
import { ChangePasswordDialog } from '../../components/ChangePasswordDialog';
import { ProfileEditDialog } from '../../components/ProfileEditDialog';
import { SettingsRow } from '../../components/SettingsRow';
import { CapsuleSegmentBar, SegmentBarOption } from '../../components/CapsuleSegmentBar';
import { AuthService } from '../../service/AuthService';
import { HttpClient, OctopApiError } from '../../net/HttpClient';
import { Log } from '../../utils/Logger';
import { UiMaterialKit } from '../../components/UiMaterialKit';
import { AppPrefs } from '../../store/AppPrefs';

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
  private scroller: Scroller = new Scroller();
  @State avatarPath: string = '';
  @State avatarFailed: boolean = false;
  @State hasPassword: boolean = false;
  @State ssoLinked: boolean = false;
  @StorageLink('immersive.light.on') immersiveOn: boolean = true;
  /** 聊天页头部宠物显隐（默认开；AppPrefs 持久化） */
  @StorageLink('pet.visible') petOn: boolean = true;
  @State permissions: Array<string> = [];
  @State myLocale: string = '';
  @State avatarUploading: boolean = false;
  @State profileMenuOpen: boolean = false;
  @State feedbackOpen: boolean = false;
  @State appVersion: string = '';
  private passwordController: CustomDialogController | null = null;
  private profileController: CustomDialogController | null = null;

  aboutToAppear(): void {
    this.refreshProfile();
    this.loadVersion();
  }

  /** 动态版本号：bundleManager 取 versionName，与关于页同源；失败回退静态文本 */
  private async loadVersion(): Promise<void> {
    try {
      const info: bundleManager.BundleInfo =
        await bundleManager.getBundleInfoForSelf(bundleManager.BundleFlag.GET_BUNDLE_INFO_DEFAULT);
      const v = info.versionName;
      if (typeof v === 'string' && v !== '') {
        this.appVersion = v;
        return;
      }
    } catch (e) {
      // 取包信息失败：走静态回退
    }
    this.appVersion = '1.0.0';
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
      this.myLocale = user.locale;
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

  /** 是否显示管理员控制台入口（admin 或持 admin_console 权限） */
  private canAdminConsole(): boolean {
    if (this.role === 'admin') {
      return true;
    }
    for (const item of this.permissions) {
      if (item === 'admin_console') {
        return true;
      }
    }
    return false;
  }

  private showChangePassword(): void {
    this.passwordController = new CustomDialogController({
      builder: ChangePasswordDialog(),
      autoCancel: true,
      systemMaterial: UiMaterialKit.sheet()
    });
    this.passwordController.open();
  }

  /** 个人资料菜单（自定义 sheet 面板替代系统 ActionSheet）：编辑资料 / 更换头像 / 删除头像 */
  private showProfileMenu(): void {
    this.profileMenuOpen = true;
  }

  private showProfileEdit(): void {
    this.profileController = new CustomDialogController({
      builder: ProfileEditDialog({
        initialDisplayName: this.displayName,
        initialLocale: this.myLocale,
        onSaved: (): void => {
          this.refreshProfile();
        }
      }),
      autoCancel: true,
      systemMaterial: UiMaterialKit.sheet()
    });
    this.profileController.open();
  }

  private fileNameFromUri(uri: string): string {
    const idx: number = uri.lastIndexOf('/');
    const name: string = idx >= 0 ? uri.substring(idx + 1) : uri;
    if (name === '') {
      return 'avatar';
    }
    try {
      return decodeURIComponent(name);
    } catch (e) {
      return name;
    }
  }

  private contentTypeFor(fileName: string): string {
    const lower: string = fileName.toLowerCase();
    if (lower.endsWith('.png')) {
      return 'image/png';
    }
    if (lower.endsWith('.webp')) {
      return 'image/webp';
    }
    if (lower.endsWith('.gif')) {
      return 'image/gif';
    }
    if (lower.endsWith('.bmp')) {
      return 'image/bmp';
    }
    return 'image/jpeg';
  }

  /** 从相册选图并上传为我的头像（≤5MiB） */
  private async pickAndUploadAvatar(): Promise<void> {
    if (this.avatarUploading) {
      return;
    }
    const photoPicker = new picker.PhotoViewPicker();
    const options = new picker.PhotoSelectOptions();
    options.MIMEType = picker.PhotoViewMIMETypes.IMAGE_TYPE;
    options.maxSelectNumber = 1;
    let uri: string = '';
    try {
      const result = await photoPicker.select(options);
      if (result.photoUris.length === 0) {
        return;
      }
      uri = result.photoUris[0];
    } catch (e) {
      Log.debug('avatar pick cancelled');
      return;
    }
    this.avatarUploading = true;
    try {
      const fileName: string = this.fileNameFromUri(uri);
      const file = fileIo.openSync(uri, fileIo.OpenMode.READ_ONLY);
      let data: ArrayBuffer;
      try {
        const stat = fileIo.statSync(file.fd);
        if (stat.size > 5 * 1024 * 1024) {
          this.getUIContext().getPromptAction().showToast({ message: '头像不能超过 5MB' });
          return;
        }
        data = new ArrayBuffer(stat.size);
        fileIo.readSync(file.fd, data);
      } finally {
        fileIo.closeSync(file);
      }
      await AuthService.uploadMyAvatar(fileName, this.contentTypeFor(fileName), data);
      this.getUIContext().getPromptAction().showToast({ message: '头像已更新' });
      this.refreshProfile();
    } catch (e) {
      const message: string = e instanceof OctopApiError ? e.message : '头像上传失败';
      this.getUIContext().getPromptAction().showToast({ message });
    } finally {
      this.avatarUploading = false;
    }
  }

  private confirmDeleteAvatar(): void {
    this.getUIContext().showAlertDialog({
      title: '删除头像',
      message: '确定删除当前头像吗？',
      primaryButton: {
        value: $r('app.string.common_cancel'),
        action: (): void => {
        }
      },
      secondaryButton: {
        value: $r('app.string.common_confirm'),
        action: (): void => {
          this.deleteMyAvatar();
        }
      },
      alignment: DialogAlignment.Bottom
    });
  }

  private async deleteMyAvatar(): Promise<void> {
    try {
      await AuthService.deleteMyAvatar();
      this.getUIContext().getPromptAction().showToast({ message: '头像已删除' });
      this.refreshProfile();
    } catch (e) {
      const message: string = e instanceof OctopApiError ? e.message : '删除失败';
      this.getUIContext().getPromptAction().showToast({ message });
    }
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

  /** appearanceMode → 分段索引：light=0 / dark=1 / auto=2 */
  private appearanceIndex(): number {
    if (this.appearanceMode === AppearanceStore.MODE_LIGHT) {
      return 0;
    }
    if (this.appearanceMode === AppearanceStore.MODE_DARK) {
      return 1;
    }
    return 2;
  }

  /** 分段索引 → 模式，复用 setAppearance（含去重与持久化） */
  private onAppearanceSelect(index: number): void {
    const modes: Array<string> =
      [AppearanceStore.MODE_LIGHT, AppearanceStore.MODE_DARK, AppearanceStore.MODE_AUTO];
    if (index < 0 || index >= modes.length) {
      return;
    }
    this.setAppearance(modes[index]);
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

  /** 反馈模板：含动态版本号 + 服务器 + 用户名，便于问题定位 */
  private buildFeedbackTemplate(): string {
    return '【Octop Link 反馈】\n' +
      `版本：v${this.appVersion}\n` +
      `服务器：${this.serverUrl === '' ? '-' : this.serverUrl}\n` +
      `用户：@${this.username === '' ? '-' : this.username}\n` +
      '问题描述：\n';
  }

  /** 复制反馈信息到粘贴板（仿 copyServerUrl 模式） */
  private async copyFeedback(): Promise<void> {
    try {
      const board = pasteboard.getSystemPasteboard();
      const data = pasteboard.createData(pasteboard.MIMETYPE_TEXT_PLAIN, this.buildFeedbackTemplate());
      await board.setData(data);
      this.feedbackOpen = false;
      this.getUIContext().getPromptAction().showToast({ message: '反馈模板已复制，请粘贴到邮件或群聊' });
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

  /** 个人资料操作面板：头像预览 + 编辑资料/更换头像/删除头像（替代系统 ActionSheet） */
  @Builder
  private profileMenuBuilder() {
    Column({ space: 14 }) {
      Column({ space: 10 }) {
        if (this.avatarFullUrl() !== '') {
          Image(this.avatarFullUrl())
            .width(88)
            .height(88)
            .borderRadius(28)
            .autoResize(true)
        } else {
          Column() {
            Image($r('app.media.octop_logo'))
              .width(56)
              .height(56)
              .borderRadius(28)
          }
          .width(88)
          .height(88)
          .justifyContent(FlexAlign.Center)
          .alignItems(HorizontalAlign.Center)
          .backgroundColor($r('app.color.bg_input'))
          .borderRadius(28)
        }
        Text(this.displayName === '' ? this.username : this.displayName)
          .fontSize(17)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.text_primary'))
      }
      .width('100%')
      .alignItems(HorizontalAlign.Center)
      .padding({ top: 20, bottom: 4 })

      Button({ type: ButtonType.Normal, stateEffect: true }) {
        Row() {
          Text('编辑资料')
            .fontSize(15)
            .fontWeight(FontWeight.Medium)
            .fontColor($r('app.color.text_primary'))
          Blank()
          SymbolGlyph($r('sys.symbol.chevron_right'))
            .fontSize(14)
            .fontColor([$r('app.color.text_tertiary')])
        }
        .width('100%')
        .padding({ left: 16, right: 16 })
      }
      .width('100%')
      .height(48)
      .borderRadius(16)
      .backgroundColor(UiMaterialKit.glassBg($r('app.color.bg_input')))
      .systemMaterial(UiMaterialKit.pill())
      .border({ width: 1, color: $r('app.color.card_stroke') })
      .onClick((): void => {
        this.profileMenuOpen = false;
        this.showProfileEdit();
      })

      Button({ type: ButtonType.Normal, stateEffect: true }) {
        Row() {
          Text(this.avatarUploading ? '上传中…' : '更换头像')
            .fontSize(15)
            .fontWeight(FontWeight.Medium)
            .fontColor($r('app.color.text_primary'))
          Blank()
          SymbolGlyph($r('sys.symbol.person'))
            .fontSize(16)
            .fontColor([$r('app.color.text_tertiary')])
        }
        .width('100%')
        .padding({ left: 16, right: 16 })
      }
      .width('100%')
      .height(48)
      .borderRadius(16)
      .backgroundColor(UiMaterialKit.glassBg($r('app.color.bg_input')))
      .systemMaterial(UiMaterialKit.pill())
      .border({ width: 1, color: $r('app.color.card_stroke') })
      .enabled(!this.avatarUploading)
      .onClick((): void => {
        this.profileMenuOpen = false;
        this.pickAndUploadAvatar();
      })

      if (this.avatarPath !== '') {
        Button({ type: ButtonType.Normal, stateEffect: true }) {
          Row() {
            Text('删除头像')
              .fontSize(15)
              .fontWeight(FontWeight.Medium)
              .fontColor($r('app.color.danger'))
            Blank()
            SymbolGlyph($r('sys.symbol.trash'))
              .fontSize(16)
              .fontColor([$r('app.color.danger')])
          }
          .width('100%')
          .padding({ left: 16, right: 16 })
        }
        .width('100%')
        .height(48)
        .borderRadius(16)
        .backgroundColor(UiMaterialKit.glassBg($r('app.color.bg_input')))
        .systemMaterial(UiMaterialKit.pill())
        .border({ width: 1, color: $r('app.color.card_stroke') })
        .onClick((): void => {
          this.profileMenuOpen = false;
          this.confirmDeleteAvatar();
        })
      }
    }
    .width('100%')
    .padding({ left: 20, right: 20, bottom: 30 })
  }

  /** 反馈与建议面板：说明文案 + 一键复制含版本号的反馈模板 */
  @Builder
  private feedbackSheetBuilder() {
    Column({ space: 14 }) {
      Text('反馈与建议')
        .fontSize(17)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.text_primary'))
        .width('100%')

      Text('你的反馈能帮助 Octop Link 变得更好。\n' +
        '点击下方按钮复制反馈模板（自动附带版本号、服务器与账号信息），\n' +
        '粘贴到邮件或群聊中补充问题描述后发送给开发团队。')
        .fontSize(13)
        .lineHeight(21)
        .fontColor($r('app.color.text_secondary'))
        .width('100%')

      Text(this.buildFeedbackTemplate())
        .fontSize(12)
        .fontFamily('monospace')
        .fontColor($r('app.color.text_tertiary'))
        .width('100%')
        .padding(12)
        .borderRadius(12)
        .backgroundColor($r('app.color.bg_input'))

      Button('复制反馈信息')
        .fontSize(15)
        .fontWeight(FontWeight.Medium)
        .height(44)
        .borderRadius(22)
        .width('100%')
        .backgroundColor($r('app.color.brand'))
        .fontColor($r('app.color.text_on_brand'))
        .onClick((): void => {
          this.copyFeedback();
        })
    }
    .width('100%')
    .padding({ left: 20, right: 20, top: 18, bottom: 30 })
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
    .backgroundColor($r('app.color.card_glass'))
    .backgroundBlurStyle(BlurStyle.COMPONENT_THIN)
    .onClick((): void => {
      this.showProfileMenu();
    })
    .bindSheet($$this.profileMenuOpen, this.profileMenuBuilder, {
      detents: [SheetSize.FIT_CONTENT],
      systemMaterial: UiMaterialKit.sheet()
    })
  }

  build() {
    HdsNavigation() {
      Column() {
        List({ scroller: this.scroller }) {
        // 头部占位项：静止时避开标题栏区域（contentStartOffset 滚动回顶后会失效，真机实测）。
        // 高度 = 状态栏避让（topInset）+ MINI 标题行 56vp + 8vp 间隙；固定 60vp 时用户卡与
        // 标题文字重叠（实测 bounds：卡顶 245px < 标题底 287px），随设备避让区自适应
        ListItem()
          .height(this.topInset + 64)
          .width('100%')
          .hitTestBehavior(HitTestMode.None)
        ListItem() {
        Column({ space: 14 }) {
          this.heroBuilder()

          Column() {
            this.sectionHeader('外观')
            Column({ space: 12 }) {
              CapsuleSegmentBar({
                options: [
                  new SegmentBarOption('浅色', AppearanceStore.MODE_LIGHT),
                  new SegmentBarOption('深色', AppearanceStore.MODE_DARK),
                  new SegmentBarOption('跟随系统', AppearanceStore.MODE_AUTO)
                ],
                selectedIndex: this.appearanceIndex(),
                onSelect: (index: number): void => {
                  this.onAppearanceSelect(index);
                }
              })

              Row({ space: 12 }) {
                Column() {
                  SymbolGlyph(this.immersiveOn ? $r('sys.symbol.sun') : $r('sys.symbol.moon'))
                    .fontSize(18)
                    .fontColor([$r('app.color.brand')])
                }
                .width(38)
                .height(38)
                .borderRadius(12)
                .backgroundColor($r('app.color.brand_light'))
                .justifyContent(FlexAlign.Center)

                Column({ space: 2 }) {
                  Text('沉浸光感')
                    .fontSize(14)
                    .fontWeight(FontWeight.Medium)
                    .fontColor($r('app.color.text_primary'))
                  Text(this.immersiveOn ? '沉浸材质光感已开启，界面通透' : '已关闭，使用常规纯色底面')
                    .fontSize(11)
                    .fontColor($r('app.color.text_tertiary'))
                    .maxLines(1)
                    .textOverflow({ overflow: TextOverflow.Ellipsis })
                }
                .layoutWeight(1)
                .alignItems(HorizontalAlign.Start)

                Text(this.immersiveOn ? '已开启' : '已关闭')
                  .fontSize(10)
                  .fontWeight(FontWeight.Medium)
                  .fontColor(this.immersiveOn ? $r('app.color.brand') : $r('app.color.text_tertiary'))
                  .backgroundColor(this.immersiveOn ? $r('app.color.brand_light') : $r('app.color.bg_input'))
                  .borderRadius(9)
                  .padding({ left: 8, right: 8, top: 3, bottom: 3 })

                Toggle({ type: ToggleType.Switch, isOn: $$this.immersiveOn })
                  .selectedColor($r('app.color.brand'))
                  .systemMaterial(UiMaterialKit.button())
                  .onChange((on: boolean): void => {
                    UiMaterialKit.setImmersiveLight(on, getContext(this));
                  })
              }
              .width('100%')

              Row({ space: 12 }) {
                Column() {
                  SymbolGlyph($r('sys.symbol.pawprint'))
                    .fontSize(18)
                    .fontColor([$r('app.color.brand')])
                }
                .width(38)
                .height(38)
                .borderRadius(12)
                .backgroundColor($r('app.color.brand_light'))
                .justifyContent(FlexAlign.Center)

                Column({ space: 2 }) {
                  Text('聊天宠物')
                    .fontSize(14)
                    .fontWeight(FontWeight.Medium)
                    .fontColor($r('app.color.text_primary'))
                  Text(this.petOn ? '聊天页顶部显示宠物，随任务状态变化' : '已关闭，聊天页头部不显示宠物')
                    .fontSize(11)
                    .fontColor($r('app.color.text_tertiary'))
                    .maxLines(1)
                    .textOverflow({ overflow: TextOverflow.Ellipsis })
                }
                .layoutWeight(1)
                .alignItems(HorizontalAlign.Start)

                Text(this.petOn ? '已开启' : '已关闭')
                  .fontSize(10)
                  .fontWeight(FontWeight.Medium)
                  .fontColor(this.petOn ? $r('app.color.brand') : $r('app.color.text_tertiary'))
                  .backgroundColor(this.petOn ? $r('app.color.brand_light') : $r('app.color.bg_input'))
                  .borderRadius(9)
                  .padding({ left: 8, right: 8, top: 3, bottom: 3 })

                Toggle({ type: ToggleType.Switch, isOn: $$this.petOn })
                  .selectedColor($r('app.color.brand'))
                  .systemMaterial(UiMaterialKit.button())
                  .onChange((on: boolean): void => {
                    AppPrefs.getInstance().setPetVisible(on);
                  })
              }
              .width('100%')
            }
            .width('100%')
            .padding({ left: 14, right: 14, top: 12, bottom: 14 })
            .borderRadius(16)
            .backgroundColor($r('app.color.card_glass'))
            .backgroundBlurStyle(BlurStyle.COMPONENT_THIN)
            .border({ width: 1, color: $r('app.color.card_stroke') })
            .shadow({ radius: 10, color: '#0A000000', offsetY: 3 })
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
            .backgroundColor($r('app.color.card_glass'))
            .backgroundBlurStyle(BlurStyle.COMPONENT_THIN)
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

              Divider()
                .color($r('app.color.divider'))
                .margin({ left: 62 })

              SettingsRow({
                icon: $r('sys.symbol.speaker'),
                iconColor: $r('app.color.brand'),
                iconBg: $r('app.color.brand_light'),
                title: '语音设置',
                subtitle: '语音识别与合成服务配置',
                onTap: (): void => {
                  this.navStack.pushPath(new NavPathInfo('voiceSettings', null));
                }
              })

              Divider()
                .color($r('app.color.divider'))
                .margin({ left: 62 })

              SettingsRow({
                icon: $r('sys.symbol.square_stack_3d'),
                iconColor: $r('app.color.brand'),
                iconBg: $r('app.color.brand_light'),
                title: '模型配置',
                subtitle: '全局默认模型与 Provider 管理',
                onTap: (): void => {
                  this.navStack.pushPath(new NavPathInfo('providers', null));
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

              if (this.canAdminConsole()) {
                Divider()
                  .color($r('app.color.divider'))
                  .margin({ left: 62 })

                SettingsRow({
                  icon: $r('sys.symbol.bolt'),
                  iconColor: $r('app.color.brand'),
                  iconBg: $r('app.color.brand_light'),
                  title: '管理员控制台',
                  subtitle: '系统概览、审计日志与用户治理',
                  onTap: (): void => {
                    this.navStack.pushPath(new NavPathInfo('admin', null));
                  }
                })
              }

              Divider()
                .color($r('app.color.divider'))
                .margin({ left: 62 })

              SettingsRow({
                icon: $r('sys.symbol.lock_shield'),
                title: 'SSO 配置',
                subtitle: 'OIDC / OAuth / LDAP 登录',
                onTap: (): void => {
                  this.navStack.pushPath(new NavPathInfo('sso', null));
                }
              })
            }
            .width('100%')
            .borderRadius(16)
            .backgroundColor($r('app.color.card_glass'))
            .backgroundBlurStyle(BlurStyle.COMPONENT_THIN)
            .border({ width: 1, color: $r('app.color.card_stroke') })
            .shadow({ radius: 10, color: '#0A000000', offsetY: 3 })
          }
          .width('100%')
          .alignItems(HorizontalAlign.Start)

          Column() {
            this.sectionHeader('支持')
            Column() {
              SettingsRow({
                icon: $r('sys.symbol.book'),
                iconColor: $r('app.color.brand'),
                iconBg: $r('app.color.brand_light'),
                title: '使用说明',
                subtitle: '快速上手与功能指引',
                onTap: (): void => {
                  this.navStack.pushPath(new NavPathInfo('help', null));
                }
              })

              Divider()
                .color($r('app.color.divider'))
                .margin({ left: 62 })

              SettingsRow({
                icon: $r('sys.symbol.envelope'),
                iconColor: $r('app.color.brand'),
                iconBg: $r('app.color.brand_light'),
                title: '反馈与建议',
                subtitle: '复制反馈模板发送给开发团队',
                onTap: (): void => {
                  this.feedbackOpen = true;
                }
              })

              Divider()
                .color($r('app.color.divider'))
                .margin({ left: 62 })

              SettingsRow({
                icon: $r('sys.symbol.info_circle'),
                iconColor: $r('app.color.brand'),
                iconBg: $r('app.color.brand_light'),
                title: '关于',
                subtitle: '版本信息',
                onTap: (): void => {
                  this.navStack.pushPath(new NavPathInfo('about', null));
                }
              })
            }
            .width('100%')
            .borderRadius(16)
            .backgroundColor($r('app.color.card_glass'))
            .backgroundBlurStyle(BlurStyle.COMPONENT_THIN)
            .border({ width: 1, color: $r('app.color.card_stroke') })
            .shadow({ radius: 10, color: '#0A000000', offsetY: 3 })
            .bindSheet($$this.feedbackOpen, this.feedbackSheetBuilder, {
              detents: [SheetSize.FIT_CONTENT],
              showClose: true,
              systemMaterial: UiMaterialKit.sheet()
            })
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

          Text(`Octop Link v${this.appVersion}`)
            .fontSize(12)
            .fontColor($r('app.color.text_tertiary'))
            .margin({ top: 8 })
        }
        .width('100%')
        .padding({ left: 16, right: 16, bottom: this.bottomPad + 16 })
        .alignItems(HorizontalAlign.Start)
        }
      }
      .width('100%')
      .height('100%')
      .clip(false)
      .cachedCount(3, true)
      .scrollBar(BarState.Off)
      }
      .width('100%')
      .height('100%')
      // 内容延伸进状态栏区（与聊天页一致）：滚动正文从标题栏/状态栏下穿过，由 GRADUAL_BLUR 提供光感
      .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
    }
    .titleBar({
      avoidLayoutSafeArea: true,
      style: {
        scrollEffectOpts: {
          enableScrollEffect: this.immersiveOn,
          scrollEffectType: ScrollEffectType.IMMERSIVE_GRADIENT_BLUR,
          blurEffectiveStartOffset: LengthMetrics.vp(0),
          blurEffectiveEndOffset: LengthMetrics.vp(20)
        },
        systemMaterialEffect: {
          materialType: this.immersiveOn ? hdsMaterial.MaterialType.IMMERSIVE : hdsMaterial.MaterialType.NONE,
          materialLevel: hdsMaterial.MaterialLevel.ADAPTIVE
        },
        originalStyle: {
          contentStyle: {
            titleStyle: {
              mainTitleColor: $r('app.color.text_primary'),
              subTitleColor: $r('app.color.text_secondary')
            },
            menuStyle: {
              iconColor: $r('app.color.icon_secondary'),
              textColor: $r('app.color.text_primary')
            }
          }
        },
        scrollEffectStyle: {
          contentStyle: {
            titleStyle: {
              mainTitleColor: $r('app.color.text_primary'),
              subTitleColor: $r('app.color.text_secondary')
            },
            menuStyle: {
              iconColor: $r('app.color.icon_secondary'),
              textColor: $r('app.color.text_primary')
            }
          }
        }
      },
      content: {
        title: { mainTitle: $r('app.string.me_title') }
      }
    })
    .titleMode(HdsNavigationTitleMode.MINI)
    .hideBackButton(true)
    .bindToScrollable([this.scroller])
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.bg_page'))
  }
}
