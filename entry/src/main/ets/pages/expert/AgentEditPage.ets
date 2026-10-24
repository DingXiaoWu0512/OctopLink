import { AgentModel } from '../../model/AgentModels';
import { AgentService } from '../../service/AgentService';
import { OctopApiError } from '../../net/HttpClient';
import { SessionStore } from '../../store/SessionStore';
import { ErrorRetry } from '../../components/ErrorRetry';
import { ModelPickerSheet } from '../../components/ModelPickerSheet';
import { fileIo, picker } from '@kit.CoreFileKit';
import { PageHeader } from '../../components/PageHeader';
import { UiMaterialKit } from '../../components/UiMaterialKit';

/** 路由参数：待编辑的智能体 */
export class AgentEditNavParam {
  readonly agentId: string;

  constructor(agentId: string) {
    this.agentId = agentId;
  }
}

/** 编辑页头像：url 带版本号，上传/删除后可强制刷新 */
@Component
struct EditAgentAvatar {
  @Prop agentId: string = '';
  @Prop iconUrl: string = '';
  @Prop rev: number = 0;
  @State failed: boolean = false;

  private src(): string {
    if (this.iconUrl !== '') {
      return AgentService.assetUrl(this.iconUrl);
    }
    return `${AgentService.avatarUrl(this.agentId)}&v=${this.rev}`;
  }

  build() {
    if (this.failed) {
      Image($r('app.media.octop_logo'))
        .width(72)
        .height(72)
        .borderRadius(36)
        .backgroundColor($r('app.color.brand_light'))
    } else {
      Image(this.src())
        .width(72)
        .height(72)
        .borderRadius(36)
        .backgroundColor($r('app.color.brand_light'))
        .objectFit(ImageFit.Cover)
        .onError((event: ImageError): void => {
          this.failed = true;
        })
    }
  }
}

@Component
export struct AgentEditPage {
  @State loading: boolean = true;
  @State loadError: string = '';
  @State saving: boolean = false;
  @State operating: boolean = false;
  @State nameText: string = '';
  @State descriptionText: string = '';
  @State personaText: string = '';
  @State modelText: string = '';
  @State welcomeText: string = '';
  @State systemPromptText: string = '';
  @State sharedOn: boolean = false;
  @State agentState: string = '';
  @State iconUrl: string = '';
  @State avatarRev: number = 0;
  @State modelSheetOpen: boolean = false;
  private pathStack: NavPathStack | null = null;
  private agentId: string = '';
  private agentName: string = '';

  private onNavReady(ctx: NavDestinationContext): void {
    if (ctx.pathInfo.param instanceof AgentEditNavParam) {
      this.agentId = ctx.pathInfo.param.agentId;
      this.pathStack = ctx.pathStack;
      this.load();
    } else {
      this.loading = false;
      this.loadError = '页面参数错误';
    }
  }

  private async load(): Promise<void> {
    this.loading = true;
    this.loadError = '';
    try {
      const agent: AgentModel = await AgentService.get(this.agentId);
      this.agentName = agent.name;
      this.nameText = agent.name;
      this.descriptionText = agent.description;
      this.personaText = agent.personaMbti;
      this.modelText = agent.defaultModel;
      this.welcomeText = agent.welcomeMessage;
      this.systemPromptText = agent.systemPrompt;
      this.sharedOn = agent.isShared;
      this.agentState = agent.state;
      this.iconUrl = agent.iconUrl;
      this.avatarRev += 1;
    } catch (e) {
      this.loadError = e instanceof OctopApiError ? e.message : '专家信息加载失败';
    } finally {
      this.loading = false;
    }
  }

  private buildPatchBody(): string {
    const body: Record<string, Object> = {
      'name': this.nameText.trim(),
      'description': this.descriptionText.trim(),
      'persona_mbti': this.personaText.trim(),
      'default_model': this.modelText.trim(),
      'welcome_message': this.welcomeText.trim(),
      'system_prompt': this.systemPromptText.trim(),
      'is_shared': this.sharedOn
    };
    return JSON.stringify(body);
  }

  private async save(): Promise<void> {
    if (this.saving) {
      return;
    }
    if (this.nameText.trim() === '') {
      this.getUIContext().getPromptAction().showToast({ message: '名称不能为空' });
      return;
    }
    this.saving = true;
    try {
      await AgentService.update(this.agentId, this.buildPatchBody());
      SessionStore.markAgentsDirty();
      this.getUIContext().getPromptAction().showToast({ message: '已保存' });
    } catch (e) {
      const message: string = e instanceof OctopApiError ? e.message : '保存失败';
      this.getUIContext().getPromptAction().showToast({ message });
    } finally {
      this.saving = false;
    }
  }

  // ---- 头像 ----

  private showAvatarMenu(): void {
    this.getUIContext().showActionSheet({
      title: '头像',
      message: '选择头像操作',
      sheets: [
        {
          title: '上传头像',
          action: (): void => {
            this.pickAndUploadAvatar();
          }
        },
        {
          title: '删除头像',
          action: (): void => {
            this.deleteAvatar();
          }
        }
      ]
    });
  }

  private async pickAndUploadAvatar(): Promise<void> {
    const docPicker = new picker.DocumentViewPicker();
    const options = new picker.DocumentSelectOptions();
    options.maxSelectNumber = 1;
    let uris: Array<string> = [];
    try {
      uris = await docPicker.select(options);
    } catch (e) {
      return;
    }
    if (uris.length === 0) {
      return;
    }
    const uri: string = uris[0];
    const idx: number = uri.lastIndexOf('/');
    const fileName: string = idx >= 0 ? uri.substring(idx + 1) : 'avatar.png';
    try {
      const file = fileIo.openSync(uri, fileIo.OpenMode.READ_ONLY);
      let data: ArrayBuffer;
      try {
        const stat = fileIo.statSync(file.fd);
        data = new ArrayBuffer(stat.size);
        fileIo.readSync(file.fd, data);
      } finally {
        fileIo.closeSync(file);
      }
      await AgentService.uploadAvatar(this.agentId, fileName, 'application/octet-stream', data);
      this.iconUrl = '';
      this.avatarRev += 1;
      SessionStore.markAgentsDirty();
      this.getUIContext().getPromptAction().showToast({ message: '头像已更新' });
    } catch (e) {
      const message: string = e instanceof OctopApiError ? e.message : '头像上传失败';
      this.getUIContext().getPromptAction().showToast({ message });
    }
  }

  private async deleteAvatar(): Promise<void> {
    if (this.operating) {
      return;
    }
    this.operating = true;
    try {
      await AgentService.deleteAvatar(this.agentId);
      this.iconUrl = '';
      this.avatarRev += 1;
      SessionStore.markAgentsDirty();
      this.getUIContext().getPromptAction().showToast({ message: '头像已删除' });
    } catch (e) {
      const message: string = e instanceof OctopApiError ? e.message : '删除失败';
      this.getUIContext().getPromptAction().showToast({ message });
    } finally {
      this.operating = false;
    }
  }

  // ---- 运行控制 ----

  private async toggleRunning(start: boolean): Promise<void> {
    if (this.operating) {
      return;
    }
    this.operating = true;
    try {
      if (start) {
        await AgentService.start(this.agentId);
        this.agentState = 'running';
      } else {
        await AgentService.stop(this.agentId);
        this.agentState = 'stopped';
      }
      SessionStore.markAgentsDirty();
      this.getUIContext().getPromptAction().showToast({ message: start ? '已启动' : '已停止' });
    } catch (e) {
      const message: string = e instanceof OctopApiError ? e.message : '操作失败';
      this.getUIContext().getPromptAction().showToast({ message });
    } finally {
      this.operating = false;
    }
  }

  private async reloadAgent(): Promise<void> {
    if (this.operating) {
      return;
    }
    this.operating = true;
    try {
      await AgentService.reload(this.agentId);
      SessionStore.markAgentsDirty();
      this.getUIContext().getPromptAction().showToast({ message: '已重载' });
    } catch (e) {
      const message: string = e instanceof OctopApiError ? e.message : '重载失败';
      this.getUIContext().getPromptAction().showToast({ message });
    } finally {
      this.operating = false;
    }
  }

  private async showStatus(): Promise<void> {
    if (this.operating) {
      return;
    }
    this.operating = true;
    try {
      const raw: string = await AgentService.getStatus(this.agentId);
      this.getUIContext().showAlertDialog({
        title: '运行状态',
        message: raw === '' ? '（无状态信息）' : raw,
        confirm: {
          value: $r('app.string.common_confirm'),
          action: (): void => {
          }
        }
      });
    } catch (e) {
      const message: string = e instanceof OctopApiError ? e.message : '状态获取失败';
      this.getUIContext().getPromptAction().showToast({ message });
    }
    this.operating = false;
  }

  private confirmDelete(): void {
    this.getUIContext().showAlertDialog({
      title: '删除专家',
      message: `删除「${this.agentName}」后不可恢复，确定删除吗？`,
      primaryButton: {
        value: $r('app.string.common_cancel'),
        action: (): void => {
        }
      },
      secondaryButton: {
        value: $r('app.string.common_confirm'),
        action: (): void => {
          this.deleteAgent();
        }
      },
      alignment: DialogAlignment.Bottom
    });
  }

  private async deleteAgent(): Promise<void> {
    if (this.operating) {
      return;
    }
    this.operating = true;
    try {
      await AgentService.remove(this.agentId);
      if (AppStorage.get<string>(SessionStore.KEY_AGENT_ID) === this.agentId) {
        AppStorage.setOrCreate(SessionStore.KEY_AGENT_ID, '');
        AppStorage.setOrCreate(SessionStore.KEY_AGENT_NAME, '');
        AppStorage.setOrCreate(SessionStore.KEY_AGENT_WELCOME, '');
      }
      SessionStore.markAgentsDirty();
      if (this.pathStack !== null) {
        this.pathStack.pop();
      }
    } catch (e) {
      const message: string = e instanceof OctopApiError ? e.message : '删除失败';
      this.getUIContext().getPromptAction().showToast({ message });
      this.operating = false;
    }
  }

  build() {
    NavDestination() {
      Column() {
        PageHeader({ title: '编辑专家' })

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
        } else if (this.loadError !== '') {
          Column() {
            ErrorRetry({
              message: this.loadError,
              onRetry: (): void => {
                this.load();
              }
            })
          }
          .layoutWeight(1)
          .width('100%')
          .justifyContent(FlexAlign.Center)
        } else {
          Scroll() {
            Column({ space: 12 }) {
              // 头像与名称
              Row({ space: 14 }) {
                EditAgentAvatar({
                  agentId: this.agentId,
                  iconUrl: this.iconUrl,
                  rev: this.avatarRev
                })
                  .onClick((): void => {
                    this.showAvatarMenu();
                  })
                Column({ space: 4 }) {
                  Text(this.agentName)
                    .fontSize(17)
                    .fontWeight(FontWeight.Bold)
                    .fontColor($r('app.color.text_primary'))
                    .maxLines(1)
                    .textOverflow({ overflow: TextOverflow.Ellipsis })
                  Text('点击头像上传或删除')
                    .fontSize(12)
                    .fontColor($r('app.color.text_tertiary'))
                }
                .layoutWeight(1)
                .alignItems(HorizontalAlign.Start)
              }
              .width('100%')
              .padding(16)
              .borderRadius(16)
              .backgroundColor($r('app.color.bg_card'))
              .border({ width: 1, color: $r('app.color.card_stroke') })
              .shadow({ radius: 10, color: '#0A000000', offsetY: 3 })

              // 运行状态卡片
              Column({ space: 0 }) {
                Row() {
                  Text('运行状态')
                    .fontSize(14)
                    .fontColor($r('app.color.text_secondary'))
                  Blank()
                  Row({ space: 6 }) {
                    Column()
                      .width(8)
                      .height(8)
                      .borderRadius(4)
                      .backgroundColor(this.agentState === 'running'
                        ? $r('app.color.success') : $r('app.color.text_tertiary'))
                    Text(this.agentState === 'running' ? '运行中' : (this.agentState === '' ? '未知' : this.agentState))
                      .fontSize(14)
                      .fontColor(this.agentState === 'running'
                        ? $r('app.color.success') : $r('app.color.text_tertiary'))
                  }
                }
                .width('100%')
                .padding({ left: 16, right: 16, top: 14, bottom: 14 })
                Row({ space: 10 }) {
                  Button('启动')
                    .fontSize(13)
                    .fontWeight(FontWeight.Bold)
                    .height(36)
                    .layoutWeight(1)
                    .borderRadius(18)
                    .backgroundColor($r('app.color.brand_light'))
                    .fontColor($r('app.color.brand'))
                    .systemMaterial(UiMaterialKit.button())
                    .enabled(!this.operating)
                    .onClick((): void => {
                      this.toggleRunning(true);
                    })
                  Button('停止')
                    .fontSize(13)
                    .fontWeight(FontWeight.Bold)
                    .height(36)
                    .layoutWeight(1)
                    .borderRadius(18)
                    .backgroundColor($r('app.color.bg_input'))
                    .fontColor($r('app.color.text_secondary'))
                    .systemMaterial(UiMaterialKit.button())
                    .enabled(!this.operating)
                    .onClick((): void => {
                      this.toggleRunning(false);
                    })
                  Button('重载')
                    .fontSize(13)
                    .fontWeight(FontWeight.Bold)
                    .height(36)
                    .layoutWeight(1)
                    .borderRadius(18)
                    .backgroundColor($r('app.color.bg_input'))
                    .fontColor($r('app.color.text_secondary'))
                    .systemMaterial(UiMaterialKit.button())
                    .enabled(!this.operating)
                    .onClick((): void => {
                      this.reloadAgent();
                    })
                  Button('状态')
                    .fontSize(13)
                    .fontWeight(FontWeight.Bold)
                    .height(36)
                    .layoutWeight(1)
                    .borderRadius(18)
                    .backgroundColor($r('app.color.bg_input'))
                    .fontColor($r('app.color.text_secondary'))
                    .systemMaterial(UiMaterialKit.button())
                    .enabled(!this.operating)
                    .onClick((): void => {
                      this.showStatus();
                    })
                }
                .width('100%')
                .padding({ left: 16, right: 16, top: 4, bottom: 14 })
              }
              .width('100%')
              .borderRadius(16)
              .backgroundColor($r('app.color.bg_card'))
              .border({ width: 1, color: $r('app.color.card_stroke') })
              .shadow({ radius: 10, color: '#0A000000', offsetY: 3 })

              // 基本信息表单
              Column({ space: 14 }) {
                Text('基本信息')
                  .fontSize(15)
                  .fontWeight(FontWeight.Bold)
                  .fontColor($r('app.color.text_primary'))
                  .width('100%')
                  .textAlign(TextAlign.Start)
                Column({ space: 6 }) {
                  Text('名称')
                    .fontSize(13)
                    .fontColor($r('app.color.text_secondary'))
                  TextInput({ text: this.nameText, placeholder: '专家名称' })
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
                Column({ space: 6 }) {
                  Text('描述')
                    .fontSize(13)
                    .fontColor($r('app.color.text_secondary'))
                  TextArea({ text: this.descriptionText, placeholder: '一句话介绍这位专家' })
                    .fontSize(14)
                    .height(64)
                    .backgroundColor($r('app.color.bg_input'))
                    .borderRadius(12)
                    .onChange((value: string): void => {
                      this.descriptionText = value;
                    })
                }
                .width('100%')
                .alignItems(HorizontalAlign.Start)
                Column({ space: 6 }) {
                  Text('人格 MBTI')
                    .fontSize(13)
                    .fontColor($r('app.color.text_secondary'))
                  TextInput({ text: this.personaText, placeholder: '如 INTJ' })
                    .fontSize(14)
                    .height(42)
                    .backgroundColor($r('app.color.bg_input'))
                    .borderRadius(12)
                    .onChange((value: string): void => {
                      this.personaText = value;
                    })
                }
                .width('100%')
                .alignItems(HorizontalAlign.Start)
                Column({ space: 6 }) {
                  Text('默认模型')
                    .fontSize(13)
                    .fontColor($r('app.color.text_secondary'))
                  Row({ space: 8 }) {
                    Text(this.modelText === '' ? '自动（未指定）' : this.modelText)
                      .fontSize(14)
                      .fontColor(this.modelText === '' ? $r('app.color.text_tertiary') : $r('app.color.text_primary'))
                      .maxLines(1)
                      .textOverflow({ overflow: TextOverflow.Ellipsis })
                      .layoutWeight(1)
                    SymbolGlyph($r('sys.symbol.chevron_right'))
                      .fontSize(14)
                      .fontColor([$r('app.color.text_tertiary')])
                  }
                  .width('100%')
                  .height(42)
                  .padding({ left: 12, right: 12 })
                  .backgroundColor($r('app.color.bg_input'))
                  .borderRadius(12)
                  .onClick((): void => {
                    this.modelSheetOpen = true;
                  })
                }
                .width('100%')
                .alignItems(HorizontalAlign.Start)
                Column({ space: 6 }) {
                  Text('欢迎语')
                    .fontSize(13)
                    .fontColor($r('app.color.text_secondary'))
                  TextArea({ text: this.welcomeText, placeholder: '新会话时展示的欢迎消息' })
                    .fontSize(14)
                    .height(64)
                    .backgroundColor($r('app.color.bg_input'))
                    .borderRadius(12)
                    .onChange((value: string): void => {
                      this.welcomeText = value;
                    })
                }
                .width('100%')
                .alignItems(HorizontalAlign.Start)
                Column({ space: 6 }) {
                  Text('系统提示词')
                    .fontSize(13)
                    .fontColor($r('app.color.text_secondary'))
                  TextArea({ text: this.systemPromptText, placeholder: '专家的系统提示词' })
                    .fontSize(14)
                    .height(120)
                    .backgroundColor($r('app.color.bg_input'))
                    .borderRadius(12)
                    .onChange((value: string): void => {
                      this.systemPromptText = value;
                    })
                }
                .width('100%')
                .alignItems(HorizontalAlign.Start)
                Row() {
                  Column({ space: 2 }) {
                    Text('共享给其他用户')
                      .fontSize(14)
                      .fontColor($r('app.color.text_primary'))
                    Text('开启后所有登录用户可对话（只读）')
                      .fontSize(12)
                      .fontColor($r('app.color.text_tertiary'))
                  }
                  .alignItems(HorizontalAlign.Start)
                  .layoutWeight(1)
                  Toggle({ type: ToggleType.Switch, isOn: this.sharedOn })
                    .onChange((isOn: boolean): void => {
                      this.sharedOn = isOn;
                    })
                }
                .width('100%')
              }
              .width('100%')
              .padding(16)
              .borderRadius(16)
              .backgroundColor($r('app.color.bg_card'))
              .border({ width: 1, color: $r('app.color.card_stroke') })
              .shadow({ radius: 10, color: '#0A000000', offsetY: 3 })
              .alignItems(HorizontalAlign.Start)

              // 保存按钮
              Button(this.saving ? '保存中...' : '保存修改')
                .fontSize(15)
                .fontWeight(FontWeight.Bold)
                .height(46)
                .width('100%')
                .borderRadius(23)
                .backgroundColor($r('app.color.brand_light'))
                .fontColor($r('app.color.brand'))
                .systemMaterial(UiMaterialKit.button())
                .enabled(!this.saving)
                .onClick((): void => {
                  this.save();
                })

              // 删除
              Row({ space: 8 }) {
                SymbolGlyph($r('sys.symbol.trash'))
                  .fontSize(16)
                  .fontColor([$r('app.color.danger')])
                Text('删除该专家')
                  .fontSize(15)
                  .fontWeight(FontWeight.Medium)
                  .fontColor($r('app.color.danger'))
              }
              .width('100%')
              .padding({ top: 14, bottom: 14 })
              .borderRadius(16)
              .backgroundColor($r('app.color.danger_soft'))
              .justifyContent(FlexAlign.Center)
              .onClick((): void => {
                this.confirmDelete();
              })
            }
            .width('100%')
            .padding({ left: 14, right: 14, top: 12, bottom: 24 })
          }
          .layoutWeight(1)
          .width('100%')
          .scrollBar(BarState.Off)
          .bindSheet($$this.modelSheetOpen, this.modelSheetBuilder, {
            detents: [SheetSize.MEDIUM, SheetSize.LARGE],
            showClose: true
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

  @Builder
  private modelSheetBuilder() {
    ModelPickerSheet({
      allowAuto: true,
      onPick: (ref: string, label: string): void => {
        this.modelText = ref;
        this.modelSheetOpen = false;
      }
    })
  }
}
