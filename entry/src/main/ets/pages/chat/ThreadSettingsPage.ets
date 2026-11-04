import { HeartbeatConfigModel } from '../../model/AgentModels';
import { ThreadModel } from '../../model/ThreadModels';
import { AgentService } from '../../service/AgentService';
import { ThreadService } from '../../service/ThreadService';
import { OctopApiError } from '../../net/HttpClient';
import { UiMaterialKit } from '../../components/UiMaterialKit';
import { PageHeader } from '../../components/PageHeader';
import { ErrorRetry } from '../../components/ErrorRetry';
import { ModelPickerSheet } from '../../components/ModelPickerSheet';
import { TrajectoryNavParam } from './TrajectoryPage';
import { picker, fileIo } from '@kit.CoreFileKit';

/** 路由参数：目标会话 */
export class ThreadSettingsNavParam {
  readonly agentId: string;
  readonly threadId: string;

  constructor(agentId: string, threadId: string) {
    this.agentId = agentId;
    this.threadId = threadId;
  }
}

/** 三选一选项 */
class SettingOption {
  readonly label: string;
  readonly value: string;

  constructor(label: string, value: string) {
    this.label = label;
    this.value = value;
  }
}

/** 分段选择行：标题 + 副标题 + 选项 pill 组 */
@Component
struct OptionPickerRow {
  @Prop title: string = '';
  @Prop subtitle: string = '';
  @Prop options: Array<SettingOption> = [];
  @Prop selected: string = '';
  onSelect: (value: string) => void = (value: string): void => {
  };


  build() {
    Column({ space: 8 }) {
      Column({ space: 2 }) {
        Text(this.title)
          .fontSize(15)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.text_primary'))
          .width('100%')
        if (this.subtitle !== '') {
          Text(this.subtitle)
            .fontSize(12)
            .fontColor($r('app.color.text_tertiary'))
            .width('100%')
        }
      }
      .width('100%')
      .alignItems(HorizontalAlign.Start)

      Row({ space: 8 }) {
        ForEach(this.options, (option: SettingOption) => {
          Text(option.label)
            .fontSize(13)
            .fontWeight(this.selected === option.value ? FontWeight.Bold : FontWeight.Normal)
            .fontColor(this.selected === option.value ?
              $r('app.color.brand') : $r('app.color.text_secondary'))
            .padding({ left: 14, right: 14, top: 7, bottom: 7 })
            .borderRadius(16)
            .backgroundColor(this.selected === option.value ?
              $r('app.color.brand_light') : $r('app.color.bg_input'))
            .onClick((): void => {
              this.onSelect(option.value);
            })
        }, (option: SettingOption) => option.value)
      }
      .width('100%')
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }
}

/** 会话设置：模型/推理/对话模式/审批策略（PATCH threads 组合器设置） */
@Component
export struct ThreadSettingsPage {
  @State loading: boolean = true;
  @State errorMsg: string = '';
  @State saving: boolean = false;
  @State modelLabel: string = '';
  @State reasoningMode: string = 'auto';
  @State reasoningEffort: string = 'medium';
  @State conversationMode: string = 'craft';
  @State hitlMode: string = 'ask';
  @State modelSheetOpen: boolean = false;

  private agentId: string = '';
  private threadId: string = '';
  private pathStack: NavPathStack | null = null;
  private modelRef: string = '';
  private modelTouched: boolean = false;
  private loaded: boolean = false;

  private readonly reasoningModeOptions: Array<SettingOption> = [
    new SettingOption('自动', 'auto'),
    new SettingOption('开启', 'enabled'),
    new SettingOption('关闭', 'disabled')
  ];
  private readonly reasoningEffortOptions: Array<SettingOption> = [
    new SettingOption('低', 'low'),
    new SettingOption('中', 'medium'),
    new SettingOption('高', 'high')
  ];
  private readonly conversationModeOptions: Array<SettingOption> = [
    new SettingOption('问答', 'ask'),
    new SettingOption('规划', 'plan'),
    new SettingOption('创作', 'craft')
  ];
  private readonly hitlModeOptions: Array<SettingOption> = [
    new SettingOption('执行前询问', 'ask'),
    new SettingOption('全部放行', 'allow_all'),
    new SettingOption('工具放行', 'allow_tools')
  ];

  // 心跳主动唤醒（专家级配置，独立端点保存）
  @State hbAvailable: boolean = true;
  @State hbEnabled: boolean = false;
  @State hbEvery: string = '1h';
  @State hbActiveEnabled: boolean = false;
  @State hbStart: string = '09:00';
  @State hbEnd: string = '21:00';
  @State hbSaving: boolean = false;
  private hbTarget: string = 'user';
  private readonly hbEveryOptions: Array<SettingOption> = [
    new SettingOption('30 分钟', '30m'),
    new SettingOption('1 小时', '1h'),
    new SettingOption('3 小时', '3h'),
    new SettingOption('6 小时', '6h'),
    new SettingOption('12 小时', '12h'),
    new SettingOption('1 天', '1d')
  ];

  private onNavReady(ctx: NavDestinationContext): void {
    this.pathStack = ctx.pathStack;
    if (ctx.pathInfo.param instanceof ThreadSettingsNavParam) {
      this.agentId = ctx.pathInfo.param.agentId;
      this.threadId = ctx.pathInfo.param.threadId;
      this.load();
    } else {
      this.loading = false;
      this.errorMsg = '页面参数错误';
    }
  }

  private async load(): Promise<void> {
    if (this.agentId === '' || this.threadId === '') {
      return;
    }
    this.loading = !this.loaded;
    this.errorMsg = '';
    try {
      const threads: Array<ThreadModel> = await ThreadService.list(this.agentId, 200);
      let found: ThreadModel | null = null;
      for (const thread of threads) {
        if (thread.threadId === this.threadId) {
          found = thread;
          break;
        }
      }
      if (found === null) {
        this.errorMsg = '会话不存在或已被删除';
        this.loaded = true;
        this.loading = false;
        return;
      }
      this.modelRef = found.modelRef;
      this.modelLabel = found.modelRef === '' ? '自动' : found.modelRef;
      this.reasoningMode = found.reasoningMode === '' ? 'auto' : found.reasoningMode;
      this.reasoningEffort = found.reasoningEffort === '' ? 'medium' : found.reasoningEffort;
      this.conversationMode = found.conversationMode === '' ? 'craft' : found.conversationMode;
      this.hitlMode = found.hitlPolicyMode === '' ? 'ask' : found.hitlPolicyMode;
      this.loaded = true;
    } catch (e) {
      this.errorMsg = e instanceof OctopApiError ? e.message : '会话设置加载失败';
    }
    this.loading = false;
    this.loadHeartbeat();
  }

  /** 心跳配置：加载失败（旧服务端无此端点）不阻塞页面，仅隐藏分区 */
  private async loadHeartbeat(): Promise<void> {
    try {
      const cfg: HeartbeatConfigModel = await AgentService.getHeartbeatConfig(this.agentId);
      this.hbEnabled = cfg.enabled;
      this.hbEvery = cfg.every;
      this.hbTarget = cfg.target === '' ? 'user' : cfg.target;
      this.hbActiveEnabled = cfg.activeHoursEnabled;
      this.hbStart = cfg.activeHoursStart;
      this.hbEnd = cfg.activeHoursEnd;
      this.hbAvailable = true;
    } catch (e) {
      this.hbAvailable = false;
    }
  }

  private isValidTime(text: string): boolean {
    if (text.length !== 5 || text.charAt(2) !== ':') {
      return false;
    }
    const h: number = Number(text.substring(0, 2));
    const m: number = Number(text.substring(3));
    return h >= 0 && h <= 23 && m >= 0 && m <= 59;
  }

  private async saveHeartbeat(): Promise<void> {
    if (this.hbSaving) {
      return;
    }
    if (this.hbActiveEnabled && (!this.isValidTime(this.hbStart) || !this.isValidTime(this.hbEnd))) {
      this.getUIContext().getPromptAction().showToast({ message: '生效时段格式需为 HH:MM' });
      return;
    }
    this.hbSaving = true;
    try {
      await AgentService.putHeartbeatConfig(this.agentId, new HeartbeatConfigModel(
        this.hbEnabled, this.hbEvery, this.hbTarget,
        this.hbActiveEnabled, this.hbStart, this.hbEnd));
      this.getUIContext().getPromptAction().showToast({ message: '心跳设置已保存' });
    } catch (e) {
      this.getUIContext().getPromptAction().showToast({
        message: e instanceof OctopApiError ? e.message : '心跳设置保存失败'
      });
    }
    this.hbSaving = false;
  }

  private async save(): Promise<void> {
    if (this.saving) {
      return;
    }
    this.saving = true;
    const body: Record<string, Object> = {};
    if (this.modelTouched) {
      body['model_ref'] = this.modelRef === '' ? 'auto/auto' : this.modelRef;
    }
    body['reasoning_mode'] = this.reasoningMode;
    body['reasoning_effort'] = this.reasoningEffort;
    body['conversation_mode'] = this.conversationMode;
    const policy: Record<string, Object> = { 'mode': this.hitlMode };
    body['hitl_policy'] = policy;
    try {
      await ThreadService.updateThreadSettings(this.agentId, this.threadId, JSON.stringify(body));
      this.getUIContext().getPromptAction().showToast({ message: '会话设置已保存' });
    } catch (e) {
      this.getUIContext().getPromptAction().showToast({
        message: e instanceof OctopApiError ? e.message : '保存失败'
      });
    }
    this.saving = false;
  }

  /** 导出未渲染原始会话历史为 JSON 文件 */
  private exportHistory(): void {
    ThreadService.exportHistory(this.agentId, this.threadId).then((text: string): void => {
      const docPicker = new picker.DocumentViewPicker();
      const saveOptions = new picker.DocumentSaveOptions();
      saveOptions.newFileNames = [`history_${this.threadId}.json`];
      docPicker.save(saveOptions).then(async (uris: Array<string>): Promise<void> => {
        if (uris.length > 0) {
          const file = fileIo.openSync(uris[0], fileIo.OpenMode.READ_WRITE);
          try {
            fileIo.writeSync(file.fd, text);
          } finally {
            fileIo.closeSync(file);
          }
          this.getUIContext().getPromptAction().showToast({ message: '历史已导出' });
        }
      }).catch((): void => {
        // 用户取消保存
      });
    }).catch((e: Object): void => {
      const message: string = e instanceof OctopApiError ? e.message : '导出失败';
      this.getUIContext().getPromptAction().showToast({ message });
    });
  }

  build() {
    NavDestination() {
      Column() {
        PageHeader({ title: '会话设置' })

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
        } else {
          Scroll() {
            Column({ space: 14 }) {
              Column({ space: 10 }) {
                Text('模型')
                  .fontSize(15)
                  .fontWeight(FontWeight.Medium)
                  .fontColor($r('app.color.text_primary'))
                  .width('100%')
                Text('该会话使用的模型，默认跟随专家设置自动选择')
                  .fontSize(12)
                  .fontColor($r('app.color.text_tertiary'))
                  .width('100%')
                Button({ stateEffect: true }) {
                  Row({ space: 6 }) {
                    Text(this.modelLabel)
                      .fontSize(14)
                      .fontColor($r('app.color.text_primary'))
                      .maxLines(1)
                      .constraintSize({ maxWidth: 200 })
                    SymbolGlyph($r('sys.symbol.chevron_right'))
                      .fontSize(12)
                      .fontColor([$r('app.color.text_tertiary')])
                  }
                }
                .height(40)
                .padding({ left: 14, right: 10 })
                .borderRadius(14)
                .backgroundColor($r('app.color.bg_input'))
                .width('100%')
                .onClick((): void => {
                  this.modelSheetOpen = true;
                })
                .bindSheet($$this.modelSheetOpen, this.modelSheetBuilder, {
                  detents: [SheetSize.MEDIUM, SheetSize.LARGE],
                  systemMaterial: UiMaterialKit.sheet()
                })
              }
              .width('100%')
              .padding(14)
              .borderRadius(16)
              .backgroundColor($r('app.color.bg_card'))
              .border({ width: 1, color: $r('app.color.card_stroke') })
              .alignItems(HorizontalAlign.Start)

              Column({ space: 14 }) {
                OptionPickerRow({
                  title: '推理模式',
                  subtitle: '是否展示思维链',
                  options: this.reasoningModeOptions,
                  selected: this.reasoningMode,
                  onSelect: (value: string): void => {
                    this.reasoningMode = value;
                  }
                })
                Divider().color($r('app.color.divider'))
                OptionPickerRow({
                  title: '推理深度',
                  subtitle: '开启推理时的思考力度',
                  options: this.reasoningEffortOptions,
                  selected: this.reasoningEffort,
                  onSelect: (value: string): void => {
                    this.reasoningEffort = value;
                  }
                })
              }
              .width('100%')
              .padding(14)
              .borderRadius(16)
              .backgroundColor($r('app.color.bg_card'))
              .border({ width: 1, color: $r('app.color.card_stroke') })
              .alignItems(HorizontalAlign.Start)

              Column({ space: 14 }) {
                OptionPickerRow({
                  title: '对话模式',
                  subtitle: '问答只读 / 规划写计划 / 创作写文档',
                  options: this.conversationModeOptions,
                  selected: this.conversationMode,
                  onSelect: (value: string): void => {
                    this.conversationMode = value;
                  }
                })
                Divider().color($r('app.color.divider'))
                OptionPickerRow({
                  title: '审批策略',
                  subtitle: '专家执行操作前是否需要人工确认',
                  options: this.hitlModeOptions,
                  selected: this.hitlMode,
                  onSelect: (value: string): void => {
                    this.hitlMode = value;
                  }
                })
              }
              .width('100%')
              .padding(14)
              .borderRadius(16)
              .backgroundColor($r('app.color.bg_card'))
              .border({ width: 1, color: $r('app.color.card_stroke') })
              .alignItems(HorizontalAlign.Start)

              if (this.hbAvailable) {
                Column({ space: 14 }) {
                  Row({ space: 10 }) {
                    Column({ space: 2 }) {
                      Text('心跳主动唤醒')
                        .fontSize(15)
                        .fontWeight(FontWeight.Medium)
                        .fontColor($r('app.color.text_primary'))
                      Text('按间隔自动唤醒专家，可主动给你发消息')
                        .fontSize(12)
                        .fontColor($r('app.color.text_tertiary'))
                    }
                    .layoutWeight(1)
                    .alignItems(HorizontalAlign.Start)

                    Toggle({ type: ToggleType.Switch, isOn: this.hbEnabled })
                      .selectedColor($r('app.color.brand'))
                      .onChange((on: boolean): void => {
                        this.hbEnabled = on;
                      })
                  }
                  .width('100%')

                  if (this.hbEnabled) {
                    OptionPickerRow({
                      title: '唤醒间隔',
                      subtitle: '专家自动自检并考虑是否主动联系的频率',
                      options: this.hbEveryOptions,
                      selected: this.hbEvery,
                      onSelect: (value: string): void => {
                        this.hbEvery = value;
                      }
                    })

                    Row({ space: 10 }) {
                      Column({ space: 2 }) {
                        Text('仅限生效时段')
                          .fontSize(15)
                          .fontWeight(FontWeight.Medium)
                          .fontColor($r('app.color.text_primary'))
                        Text('时段外不打扰（如仅白天提醒）')
                          .fontSize(12)
                          .fontColor($r('app.color.text_tertiary'))
                      }
                      .layoutWeight(1)
                      .alignItems(HorizontalAlign.Start)

                      Toggle({ type: ToggleType.Switch, isOn: this.hbActiveEnabled })
                        .selectedColor($r('app.color.brand'))
                        .onChange((on: boolean): void => {
                          this.hbActiveEnabled = on;
                        })
                    }
                    .width('100%')

                    if (this.hbActiveEnabled) {
                      Row({ space: 10 }) {
                        TextInput({ text: this.hbStart, placeholder: '09:00' })
                          .fontSize(14)
                          .height(40)
                          .layoutWeight(1)
                          .backgroundColor($r('app.color.bg_input'))
                          .borderRadius(12)
                          .onChange((value: string): void => {
                            this.hbStart = value;
                          })
                        Text('至')
                          .fontSize(13)
                          .fontColor($r('app.color.text_tertiary'))
                        TextInput({ text: this.hbEnd, placeholder: '21:00' })
                          .fontSize(14)
                          .height(40)
                          .layoutWeight(1)
                          .backgroundColor($r('app.color.bg_input'))
                          .borderRadius(12)
                          .onChange((value: string): void => {
                            this.hbEnd = value;
                          })
                      }
                      .width('100%')
                    }

                    Button(this.hbSaving ? '保存中…' : '保存心跳设置')
                      .fontSize(14)
                      .fontWeight(FontWeight.Medium)
                      .fontColor($r('app.color.brand'))
                      .backgroundColor($r('app.color.brand_light'))
                      .borderRadius(14)
                      .height(40)
                      .width('100%')
                      .enabled(!this.hbSaving)
                      .onClick((): void => {
                        this.saveHeartbeat();
                      })
                  }
                }
                .width('100%')
                .padding(14)
                .borderRadius(16)
                .backgroundColor($r('app.color.bg_card'))
                .border({ width: 1, color: $r('app.color.card_stroke') })
                .alignItems(HorizontalAlign.Start)
              }

              Button(this.saving ? '保存中…' : '保存设置')
                .fontSize(15)
                .fontWeight(FontWeight.Bold)
                .fontColor(Color.White)
                .backgroundColor($r('app.color.brand'))
                .borderRadius(16)
                .height(46)
                .width('100%')
                .margin({ top: 4 })
                .onClick((): void => {
                  this.save();
                })

              Button('查看对话轨迹')
                .fontSize(15)
                .fontWeight(FontWeight.Medium)
                .fontColor($r('app.color.brand'))
                .backgroundColor($r('app.color.brand_light'))
                .borderRadius(16)
                .height(46)
                .width('100%')
                .margin({ top: 2 })
                .onClick((): void => {
                  if (this.pathStack !== null) {
                    this.pathStack.pushPath(new NavPathInfo('trajectory',
                      new TrajectoryNavParam(this.agentId, this.threadId)));
                  }
                })

              Button('导出原始历史（JSON）')
                .fontSize(14)
                .fontWeight(FontWeight.Medium)
                .fontColor($r('app.color.text_secondary'))
                .backgroundColor($r('app.color.bg_input'))
                .borderRadius(16)
                .height(42)
                .width('100%')
                .onClick((): void => {
                  this.exportHistory();
                })

              Text('设置仅对当前会话生效，不影响专家默认配置')
                .fontSize(12)
                .fontColor($r('app.color.text_tertiary'))
                .width('100%')
                .textAlign(TextAlign.Center)
            }
            .width('100%')
            .padding({ left: 14, right: 14, top: 8, bottom: 28 })
          }
          .layoutWeight(1)
          .width('100%')
          .scrollBar(BarState.Off)
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
        this.modelRef = ref;
        this.modelTouched = true;
        this.modelLabel = ref === '' ? '自动' : label;
        this.modelSheetOpen = false;
      }
    })
  }
}
