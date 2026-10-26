import { ThreadModel } from '../../model/ThreadModels';
import { ThreadService } from '../../service/ThreadService';
import { OctopApiError } from '../../net/HttpClient';
import { UiMaterialKit } from '../../components/UiMaterialKit';
import { PageHeader } from '../../components/PageHeader';
import { ErrorRetry } from '../../components/ErrorRetry';
import { ModelPickerSheet } from '../../components/ModelPickerSheet';

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

  private onNavReady(ctx: NavDestinationContext): void {
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
