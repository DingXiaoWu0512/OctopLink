import { ChannelModel, ChannelPluginKindModel, QrPollResult, QrSessionModel } from '../../model/WorkspaceModels';
import { ChannelService } from '../../service/WorkspaceService';
import { OctopApiError } from '../../net/HttpClient';
import { SessionStore } from '../../store/SessionStore';
import { EmptyView } from '../../components/EmptyView';
import { ErrorRetry } from '../../components/ErrorRetry';
import { PageHeader } from '../../components/PageHeader';
import { UiMaterialKit } from '../../components/UiMaterialKit';
import { JsonHelper } from '../../utils/JsonHelper';

/** 内置渠道类型（与扫码向导平台一致） */
class BuiltinChannelKind {
  readonly kind: string;
  readonly label: string;

  constructor(kind: string, label: string) {
    this.kind = kind;
    this.label = label;
  }
}

/** 当前专家的渠道列表：创建/扫码接入/详情/测试/启停/删除 */
@Component
export struct ChannelPage {
  @State channels: Array<ChannelModel> = [];
  @State loading: boolean = true;
  @State errorMsg: string = '';
  @State operating: boolean = false;
  @State createSheetOpen: boolean = false;
  @State kindOptions: Array<BuiltinChannelKind> = [];
  @State kindIndex: number = 0;
  @State nameText: string = '';
  @State configText: string = '{}';
  @State creating: boolean = false;
  @State probing: boolean = false;
  @State qrSheetOpen: boolean = false;
  @State qrPlatformIndex: number = -1;
  @State qrImage: string = '';
  @State qrStatus: string = '';
  @State qrPolling: boolean = false;
  private agentId: string = '';
  private pollToken: string = '';
  private pollCount: number = 0;

  private readonly qrPlatforms: Array<BuiltinChannelKind> = [
    new BuiltinChannelKind('dingtalk', '钉钉'),
    new BuiltinChannelKind('wecom', '企业微信'),
    new BuiltinChannelKind('qq', 'QQ Bot'),
    new BuiltinChannelKind('weixin', '微信'),
    new BuiltinChannelKind('feishu', '飞书机器人'),
    new BuiltinChannelKind('yuanbao', '元宝')
  ];

  private onNavReady(ctx: NavDestinationContext): void {
    this.agentId = AppStorage.get<string>(SessionStore.KEY_AGENT_ID) ?? '';
    this.buildKindOptions();
    if (this.agentId === '') {
      this.loading = false;
      this.errorMsg = '未选择专家，请先在专家页选择';
      return;
    }
    this.load();
  }

  /** 内置类型 + 插件贡献类型（去重合并） */
  private async buildKindOptions(): Promise<void> {
    const options: Array<BuiltinChannelKind> = [];
    for (const platform of this.qrPlatforms) {
      options.push(new BuiltinChannelKind(platform.kind, platform.label));
    }
    try {
      const plugins: Array<ChannelPluginKindModel> = await ChannelService.pluginKinds();
      for (const plugin of plugins) {
        let exists: boolean = false;
        for (const option of options) {
          if (option.kind.toLowerCase() === plugin.kind.toLowerCase()) {
            exists = true;
            break;
          }
        }
        if (!exists) {
          options.push(new BuiltinChannelKind(plugin.kind,
            plugin.label === '' ? plugin.kind : plugin.label));
        }
      }
    } catch (e) {
      // 插件类型加载失败时仅保留内置类型
    }
    this.kindOptions = options;
  }

  private async load(): Promise<void> {
    this.loading = this.channels.length === 0;
    this.errorMsg = '';
    try {
      this.channels = await ChannelService.list(this.agentId);
    } catch (e) {
      this.errorMsg = e instanceof OctopApiError ? e.message : '渠道加载失败';
    } finally {
      this.loading = false;
    }
  }

  private async toggle(channel: ChannelModel, on: boolean): Promise<void> {
    if (this.operating) {
      return;
    }
    this.operating = true;
    try {
      await ChannelService.setEnabled(this.agentId, channel.id, on);
      await this.load();
    } catch (e) {
      const message: string = e instanceof OctopApiError ? e.message : '操作失败';
      this.getUIContext().getPromptAction().showToast({ message });
    } finally {
      this.operating = false;
    }
  }

  /** 长按渠道菜单 */
  private showChannelMenu(channel: ChannelModel): void {
    this.getUIContext().showActionSheet({
      title: channel.name,
      message: '选择要执行的操作',
      sheets: [
        {
          title: '查看配置',
          action: (): void => {
            this.showChannelDetail(channel);
          }
        },
        {
          title: '测试连通性',
          action: (): void => {
            this.testChannel(channel);
          }
        },
        {
          title: channel.enabled ? '停用渠道' : '启用渠道',
          action: (): void => {
            this.toggle(channel, !channel.enabled);
          }
        },
        {
          title: '删除渠道',
          action: (): void => {
            this.confirmDelete(channel);
          }
        }
      ]
    });
  }

  /** 详情：展示 config JSON */
  private async showChannelDetail(channel: ChannelModel): Promise<void> {
    if (this.operating) {
      return;
    }
    this.operating = true;
    try {
      const raw: string = await ChannelService.getChannel(this.agentId, channel.id);
      const rec = JsonHelper.parse(raw);
      const config: Record<string, Object> | null =
        rec === null ? null : JsonHelper.getRecord(rec, 'config');
      const configText: string = config === null ? '（无配置）' : JSON.stringify(config, null, 2);
      this.getUIContext().showAlertDialog({
        title: `${channel.name}（${channel.kind}）`,
        message: `运行状态：${channel.runtime === '' ? '未知' : channel.runtime}\n\n${configText}`,
        confirm: {
          value: $r('app.string.common_confirm'),
          action: (): void => {
          }
        }
      });
    } catch (e) {
      const message: string = e instanceof OctopApiError ? e.message : '详情加载失败';
      this.getUIContext().getPromptAction().showToast({ message });
    }
    this.operating = false;
  }

  private async testChannel(channel: ChannelModel): Promise<void> {
    if (this.operating) {
      return;
    }
    this.operating = true;
    try {
      await ChannelService.testChannel(this.agentId, channel.id);
      this.getUIContext().getPromptAction().showToast({ message: '连通性正常' });
    } catch (e) {
      const message: string = e instanceof OctopApiError ? e.message : '测试失败';
      this.getUIContext().getPromptAction().showToast({ message });
    }
    this.operating = false;
  }

  // ---- 创建渠道 ----

  private openCreateSheet(): void {
    this.nameText = '';
    this.configText = '{}';
    this.kindIndex = 0;
    this.createSheetOpen = true;
  }

  private selectedKind(): string {
    if (this.kindIndex < 0 || this.kindIndex >= this.kindOptions.length) {
      return this.kindOptions.length > 0 ? this.kindOptions[0].kind : '';
    }
    return this.kindOptions[this.kindIndex].kind;
  }

  private validConfig(): boolean {
    const rec: Record<string, Object> | null = JsonHelper.parse(this.configText);
    return rec !== null;
  }

  /** 测试草稿配置（probe） */
  private async probeConfig(): Promise<void> {
    if (this.probing) {
      return;
    }
    if (!this.validConfig()) {
      this.getUIContext().getPromptAction().showToast({ message: 'config 不是合法 JSON 对象' });
      return;
    }
    this.probing = true;
    try {
      await ChannelService.probe(this.agentId, this.selectedKind(), this.configText);
      this.getUIContext().getPromptAction().showToast({ message: '配置可用' });
    } catch (e) {
      const message: string = e instanceof OctopApiError ? e.message : '配置不可用';
      this.getUIContext().getPromptAction().showToast({ message });
    }
    this.probing = false;
  }

  private async createChannel(): Promise<void> {
    if (this.creating) {
      return;
    }
    const name: string = this.nameText.trim();
    if (name === '') {
      this.getUIContext().getPromptAction().showToast({ message: '请填写渠道名称' });
      return;
    }
    if (!this.validConfig()) {
      this.getUIContext().getPromptAction().showToast({ message: 'config 不是合法 JSON 对象' });
      return;
    }
    this.creating = true;
    try {
      await ChannelService.create(this.agentId, this.selectedKind(), name, this.configText);
      this.createSheetOpen = false;
      this.getUIContext().getPromptAction().showToast({ message: '渠道已创建' });
      this.load();
    } catch (e) {
      const message: string = e instanceof OctopApiError ? e.message : '创建失败';
      this.getUIContext().getPromptAction().showToast({ message });
    }
    this.creating = false;
  }

  // ---- 扫码接入向导 ----

  private async startQr(index: number): Promise<void> {
    this.qrPlatformIndex = index;
    this.qrImage = '';
    this.qrStatus = '正在生成二维码…';
    this.qrPolling = false;
    this.qrSheetOpen = true;
    const platform: string = index >= 0 && index < this.qrPlatforms.length ?
      this.qrPlatforms[index].kind : '';
    try {
      const session: QrSessionModel = await this.generateSession(platform);
      if (session.qrcodeUrl === '' && session.token === '') {
        this.qrStatus = '二维码生成失败';
        return;
      }
      this.qrImage = session.qrcodeUrl;
      this.qrStatus = session.userCode === '' ? '请使用平台 App 扫码' : `请扫码，验证码：${session.userCode}`;
      this.pollToken = session.token;
      this.pollCount = 0;
      this.qrPolling = true;
      this.schedulePoll(platform, session.token);
    } catch (e) {
      this.qrStatus = e instanceof OctopApiError ? e.message : '二维码生成失败';
    }
  }

  private async generateSession(platform: string): Promise<QrSessionModel> {
    if (platform === 'dingtalk') {
      return await ChannelService.dingtalkQrcodeGenerate(this.agentId);
    }
    if (platform === 'wecom') {
      return await ChannelService.wecomQrcodeGenerate(this.agentId);
    }
    if (platform === 'qq') {
      return await ChannelService.qqQrcodeGenerate(this.agentId);
    }
    if (platform === 'weixin') {
      return await ChannelService.weixinQrcodeGenerate(this.agentId);
    }
    if (platform === 'feishu') {
      return await ChannelService.feishuBotStart(this.agentId);
    }
    return await ChannelService.yuanbaoBotStart(this.agentId);
  }

  /** 轮询：sheet 关闭 / 超 3 分钟自动停止 */
  private schedulePoll(platform: string, token: string): void {
    const myToken: string = this.pollToken;
    setTimeout((): void => {
      this.pollOnce(platform, token, myToken);
    }, 2000);
  }

  private async pollOnce(platform: string, token: string, myToken: string): Promise<void> {
    if (!this.qrPolling || !this.qrSheetOpen || myToken !== this.pollToken) {
      return;
    }
    if (this.pollCount > 90) {
      this.qrStatus = '等待超时，请关闭后重试';
      this.qrPolling = false;
      return;
    }
    this.pollCount += 1;
    try {
      const result = await this.pollPlatform(platform, token);
      if (!this.qrPolling || myToken !== this.pollToken) {
        return;
      }
      if (result.status === 'success') {
        this.qrPolling = false;
        this.qrStatus = '接入成功';
        this.getUIContext().getPromptAction().showToast({ message: '渠道接入成功' });
        this.stopBot(platform, token);
        this.qrSheetOpen = false;
        this.load();
        return;
      }
      if (result.status === 'expired' || result.status === 'failed') {
        this.qrPolling = false;
        this.qrStatus = result.message === '' ? '已过期或失败，请重试' : result.message;
        this.stopBot(platform, token);
        return;
      }
      this.schedulePoll(platform, token);
    } catch (e) {
      if (!this.qrPolling) {
        return;
      }
      this.schedulePoll(platform, token);
    }
  }

  private async pollPlatform(platform: string, token: string): Promise<QrPollResult> {
    if (platform === 'dingtalk') {
      return await ChannelService.dingtalkQrcodePoll(this.agentId, token);
    }
    if (platform === 'wecom') {
      return await ChannelService.wecomQrcodePoll(this.agentId, token);
    }
    if (platform === 'qq') {
      return await ChannelService.qqQrcodePoll(this.agentId, token);
    }
    if (platform === 'weixin') {
      return await ChannelService.weixinQrcodePoll(this.agentId, token);
    }
    if (platform === 'feishu') {
      return await ChannelService.feishuBotPoll(this.agentId);
    }
    return await ChannelService.yuanbaoBotPoll(this.agentId);
  }

  /** bot-creator 类平台退出时停止会话 */
  private async stopBot(platform: string, token: string): Promise<void> {
    if (platform === 'feishu') {
      try {
        await ChannelService.feishuBotStop(this.agentId);
      } catch (e) {
        // 忽略停止失败
      }
    } else if (platform === 'yuanbao') {
      try {
        await ChannelService.yuanbaoBotStop(this.agentId);
      } catch (e) {
        // 忽略停止失败
      }
    }
  }

  private confirmDelete(channel: ChannelModel): void {
    this.getUIContext().showAlertDialog({
      title: '删除渠道',
      message: `删除「${channel.name}」后将无法通过该渠道收发消息，确定吗？`,
      primaryButton: {
        value: $r('app.string.common_cancel'),
        action: (): void => {
        }
      },
      secondaryButton: {
        value: $r('app.string.common_confirm'),
        action: (): void => {
          this.deleteChannel(channel);
        }
      },
      alignment: DialogAlignment.Bottom
    });
  }

  private async deleteChannel(channel: ChannelModel): Promise<void> {
    if (this.operating) {
      return;
    }
    this.operating = true;
    try {
      await ChannelService.remove(this.agentId, channel.id);
      await this.load();
    } catch (e) {
      const message: string = e instanceof OctopApiError ? e.message : '删除失败';
      this.getUIContext().getPromptAction().showToast({ message });
    } finally {
      this.operating = false;
    }
  }

  @Builder
  private createSheetBuilder() {
    Column({ space: 12 }) {
      Text('创建渠道')
        .fontSize(17)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.text_primary'))
        .width('100%')
      Select(this.kindOptions.map((option: BuiltinChannelKind): SelectOption => {
        return { value: option.label };
      }))
        .selected(this.kindIndex)
        .value(this.selectedKind() === '' ? '请选择类型' : this.selectedKind())
        .font({ size: 14 })
        .fontColor($r('app.color.text_primary'))
        .selectedOptionFont({ size: 14 })
        .optionFont({ size: 14 })
        .backgroundColor($r('app.color.bg_input'))
        .borderRadius(12)
        .width('100%')
        .onSelect((index: number, text: string): void => {
          this.kindIndex = index;
        })
      TextInput({ text: this.nameText, placeholder: '渠道名称' })
        .fontSize(14)
        .height(42)
        .backgroundColor($r('app.color.bg_input'))
        .borderRadius(12)
        .onChange((value: string): void => {
          this.nameText = value;
        })
      TextArea({ text: this.configText, placeholder: 'config（JSON 对象）' })
        .fontSize(12)
        .fontFamily('monospace')
        .constraintSize({ minHeight: 110, maxHeight: 220 })
        .backgroundColor($r('app.color.bg_input'))
        .borderRadius(12)
        .width('100%')
        .onChange((value: string): void => {
          this.configText = value;
        })
      Row({ space: 10 }) {
        Button(this.probing ? '测试中…' : '测试配置')
          .fontSize(14)
          .height(42)
          .layoutWeight(1)
          .borderRadius(16)
          .backgroundColor($r('app.color.bg_input'))
          .fontColor($r('app.color.text_secondary'))
          .enabled(!this.probing)
          .onClick((): void => {
            this.probeConfig();
          })
        Button(this.creating ? '创建中…' : '创建')
          .fontSize(15)
          .fontWeight(FontWeight.Bold)
          .height(42)
          .layoutWeight(1)
          .borderRadius(16)
          .backgroundColor($r('app.color.brand'))
          .fontColor($r('app.color.text_on_brand'))
          .enabled(!this.creating)
          .onClick((): void => {
            this.createChannel();
          })
      }
      .width('100%')
    }
    .padding({ left: 18, right: 18, top: 18, bottom: 30 })
    .width('100%')
  }

  @Builder
  private qrSheetBuilder() {
    Column({ space: 14 }) {
      Text('扫码接入')
        .fontSize(17)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.text_primary'))
        .width('100%')
      if (this.qrPlatformIndex < 0) {
        ForEach(this.qrPlatforms, (platform: BuiltinChannelKind, index: number) => {
          Text(platform.label)
            .fontSize(15)
            .fontColor($r('app.color.text_primary'))
            .width('100%')
            .padding({ top: 12, bottom: 12 })
            .borderRadius(12)
            .backgroundColor($r('app.color.bg_input'))
            .textAlign(TextAlign.Center)
            .onClick((): void => {
              this.startQr(index);
            })
        }, (platform: BuiltinChannelKind) => platform.kind)
      } else {
        Text(this.qrPlatforms[this.qrPlatformIndex].label)
          .fontSize(15)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.text_secondary'))
        if (this.qrImage !== '') {
          Image(this.qrImage)
            .width(210)
            .height(210)
            .objectFit(ImageFit.Contain)
            .borderRadius(12)
            .backgroundColor(Color.White)
            .padding(6)
        } else {
          LoadingProgress()
            .width(40)
            .height(40)
            .color($r('app.color.brand'))
        }
        Text(this.qrStatus)
          .fontSize(13)
          .fontColor($r('app.color.text_secondary'))
          .textAlign(TextAlign.Center)
          .width('100%')
        Button('重新选择平台')
          .fontSize(14)
          .height(38)
          .borderRadius(19)
          .backgroundColor($r('app.color.bg_input'))
          .fontColor($r('app.color.text_secondary'))
          .onClick((): void => {
            this.qrPolling = false;
            this.qrPlatformIndex = -1;
            this.qrImage = '';
            this.qrStatus = '';
          })
      }
    }
    .padding({ left: 18, right: 18, top: 18, bottom: 30 })
    .width('100%')
  }

  build() {
    NavDestination() {
      Stack({ alignContent: Alignment.BottomEnd }) {
        Column() {
          PageHeader({ title: '渠道' })

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
          } else if (this.channels.length === 0) {
            Column() {
              EmptyView({
                title: '暂无渠道',
                subtitle: '点击右下角按钮创建或扫码接入',
                icon: $r('sys.symbol.dot_radiowaves_left_and_right')
              })
            }
            .layoutWeight(1)
            .width('100%')
            .justifyContent(FlexAlign.Center)
          } else {
            List({ space: 10 }) {
              ForEach(this.channels, (channel: ChannelModel) => {
                ListItem() {
                  Row({ space: 12 }) {
                    Column() {
                      SymbolGlyph($r('sys.symbol.dot_radiowaves_left_and_right'))
                        .fontSize(20)
                        .fontColor([channel.enabled ? $r('app.color.success') : $r('app.color.text_tertiary')])
                    }
                    .width(44)
                    .height(44)
                    .justifyContent(FlexAlign.Center)
                    .backgroundColor(channel.enabled ? $r('app.color.success_soft') : $r('app.color.bg_input'))
                    .borderRadius(14)
                    Column({ space: 5 }) {
                      Row({ space: 6 }) {
                        Text(channel.name)
                          .fontSize(16)
                          .fontWeight(FontWeight.Medium)
                          .fontColor($r('app.color.text_primary'))
                          .maxLines(1)
                          .textOverflow({ overflow: TextOverflow.Ellipsis })
                      }
                      .width('100%')
                      Row({ space: 8 }) {
                        Text(channel.kind)
                          .fontSize(12)
                          .fontColor($r('app.color.text_tertiary'))
                        Text(channel.enabled ? '已启用' : '已停用')
                          .fontSize(11)
                          .fontColor(channel.enabled ? $r('app.color.success') : $r('app.color.text_tertiary'))
                          .backgroundColor(channel.enabled
                            ? $r('app.color.success_soft') : $r('app.color.bg_input'))
                          .borderRadius(6)
                          .padding({ left: 8, right: 8, top: 3, bottom: 3 })
                        if (channel.runtime !== '') {
                          Text(channel.runtime)
                            .fontSize(11)
                            .fontColor($r('app.color.brand'))
                            .backgroundColor($r('app.color.brand_light'))
                            .borderRadius(6)
                            .padding({ left: 8, right: 8, top: 3, bottom: 3 })
                        }
                      }
                    }
                    .layoutWeight(1)
                    .alignItems(HorizontalAlign.Start)
                    Toggle({ type: ToggleType.Switch, isOn: channel.enabled })
                      .onChange((isOn: boolean): void => {
                        this.toggle(channel, isOn);
                      })
                  }
                  .width('100%')
                  .padding(14)
                  .borderRadius(16)
                  .backgroundColor($r('app.color.bg_card'))
                  .border({ width: 1, color: $r('app.color.card_stroke') })
                  .shadow({ radius: 10, color: '#0A000000', offsetY: 3 })
                  .gesture(
                    LongPressGesture()
                      .onAction((event: GestureEvent): void => {
                        this.showChannelMenu(channel);
                      })
                  )
                }
              }, (channel: ChannelModel) => channel.id)
            }
            .width('100%')
            .layoutWeight(1)
            .padding({ left: 12, right: 12, top: 4, bottom: 20 })
            .scrollBar(BarState.Off)
          }
        }
        .width('100%')
        .height('100%')
        .bindSheet($$this.createSheetOpen, this.createSheetBuilder, {
          detents: [SheetSize.MEDIUM, SheetSize.LARGE],
          showClose: true
        })
        .bindSheet($$this.qrSheetOpen, this.qrSheetBuilder, {
          detents: [SheetSize.MEDIUM, SheetSize.LARGE],
          showClose: true,
          onDisappear: (): void => {
            this.qrPolling = false;
            this.qrPlatformIndex = -1;
            this.qrImage = '';
            this.qrStatus = '';
          }
        })

        Button({ type: ButtonType.Circle, stateEffect: true }) {
          SymbolGlyph($r('sys.symbol.plus'))
            .fontSize(28)
            .fontWeight(FontWeight.Medium)
            .fontColor([$r('app.color.brand')])
        }
        .width(58)
        .height(58)
        .backgroundColor($r('app.color.bg_card'))
        .border({ width: 1, color: $r('app.color.card_stroke') })
        .systemMaterial(UiMaterialKit.button())
        .margin(22)
        .onClick((): void => {
          this.getUIContext().showActionSheet({
            title: '接入渠道',
            message: '选择接入方式',
            sheets: [
              {
                title: '创建渠道',
                action: (): void => {
                  this.openCreateSheet();
                }
              },
              {
                title: '扫码接入',
                action: (): void => {
                  this.qrPlatformIndex = -1;
                  this.qrImage = '';
                  this.qrStatus = '';
                  this.qrSheetOpen = true;
                }
              }
            ]
          });
        })
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
