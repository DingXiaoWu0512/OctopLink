import { CronService } from '../service/WorkspaceService';
import { UiMaterialKit } from './UiMaterialKit';
import { OctopApiError } from '../net/HttpClient';
import { ModelPickerSheet } from './ModelPickerSheet';

/** 定时任务创建/编辑对话框：触发器四形态 + 提示词示例 + 新线程 + 模型选择 */
@CustomDialog
export struct CronCreateDialog {
  controller?: CustomDialogController;
  onSaved: () => void = (): void => {
  };
  agentId: string = '';
  /** 非空代表编辑模式 */
  cronId: string = '';
  initialName: string = '';
  initialTrigger: string = '';
  initialPrompt: string = '';
  initialFreshThread: boolean = false;
  initialModel: string = '';

  @State isEdit: boolean = false;
  @State triggerKind: number = 0;
  @State nameText: string = '';
  @State valueText: string = '';
  @State promptText: string = '';
  @State freshThread: boolean = false;
  @State modelRef: string = '';
  @State modelLabel: string = '';
  @State examples: Array<string> = [];
  @State submitting: boolean = false;
  @State pickerOpen: boolean = false;

  aboutToAppear(): void {
    this.isEdit = this.cronId !== '';
    this.nameText = this.initialName;
    this.promptText = this.initialPrompt;
    this.freshThread = this.initialFreshThread;
    this.modelRef = this.initialModel;
    this.modelLabel = this.initialModel;
    this.applyInitialTrigger();
    this.loadExamples();
  }

  private applyInitialTrigger(): void {
    const trigger: string = this.initialTrigger;
    if (trigger.startsWith('cron:')) {
      this.triggerKind = 0;
      this.valueText = trigger.substring(5);
    } else if (trigger.startsWith('interval:')) {
      this.triggerKind = 1;
      this.valueText = trigger.substring(9);
    } else if (trigger.startsWith('date:')) {
      this.triggerKind = 2;
      this.valueText = trigger.substring(5);
    } else if (trigger.startsWith('agently:')) {
      this.triggerKind = 3;
      this.valueText = trigger.substring(8);
    }
  }

  private loadExamples(): void {
    CronService.examples(this.agentId).then((list: Array<string>) => {
      this.examples = list;
    }).catch((): void => {
      this.examples = [];
    });
  }

  private triggerPlaceholder(): string {
    if (this.triggerKind === 0) {
      return 'Cron 表达式，如 0 9 * * *';
    }
    if (this.triggerKind === 1) {
      return '间隔秒数，如 3600';
    }
    if (this.triggerKind === 2) {
      return '时间，如 2030-01-01T08:00:00';
    }
    return 'Agent Mail 实例 ID';
  }

  private buildTrigger(): string {
    if (this.triggerKind === 0) {
      return `cron:${this.valueText.trim()}`;
    }
    if (this.triggerKind === 1) {
      return `interval:${this.valueText.trim()}`;
    }
    if (this.triggerKind === 2) {
      return `date:${this.valueText.trim()}`;
    }
    return `agently:${this.valueText.trim()}`;
  }

  private async submit(): Promise<void> {
    if (this.submitting) {
      return;
    }
    const value: string = this.valueText.trim();
    const prompt: string = this.promptText.trim();
    if (value === '' || prompt === '') {
      this.getUIContext().getPromptAction().showToast({ message: '请填写触发条件与提示词' });
      return;
    }
    if (this.triggerKind === 1) {
      const seconds: number = Number(value);
      if (Number.isNaN(seconds) || seconds <= 0) {
        this.getUIContext().getPromptAction().showToast({ message: '间隔必须为正整数秒' });
        return;
      }
    }
    this.submitting = true;
    try {
      if (this.isEdit) {
        const body: Record<string, Object> = {
          'trigger': this.buildTrigger(),
          'prompt': prompt,
          'fresh_thread': this.freshThread
        };
        const name: string = this.nameText.trim();
        if (name !== '') {
          body['name'] = name;
        }
        if (this.modelRef !== '') {
          body['model'] = this.modelRef;
        }
        await CronService.patch(this.agentId, this.cronId, JSON.stringify(body));
      } else {
        await CronService.create(this.agentId, this.nameText.trim(), this.buildTrigger(),
          prompt, this.freshThread, this.modelRef);
      }
      this.controller?.close();
      this.getUIContext().getPromptAction().showToast({ message: this.isEdit ? '任务已保存' : '任务已创建' });
      this.onSaved();
    } catch (e) {
      const message: string = e instanceof OctopApiError ? e.message : '保存失败';
      this.getUIContext().getPromptAction().showToast({ message });
    } finally {
      this.submitting = false;
    }
  }

  build() {
    Column({ space: 14 }) {
      Text(this.isEdit ? '编辑定时任务' : '新建定时任务')
        .fontSize(17)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.text_primary'))
        .width('100%')
        .textAlign(TextAlign.Start)

      TextInput({
        text: this.nameText,
        placeholder: '任务名称（可选）'
      })
        .fontSize(14)
        .height(42)
        .backgroundColor($r('app.color.bg_input'))
        .borderRadius(12)
        .onChange((value: string): void => {
          this.nameText = value;
        })

      Row({ space: 8 }) {
        Text('Cron')
          .fontSize(13)
          .fontColor(this.triggerKind === 0 ? $r('app.color.text_on_brand') : $r('app.color.text_secondary'))
          .height(30)
          .padding({ left: 12, right: 12 })
          .borderRadius(15)
          .backgroundColor(this.triggerKind === 0 ? $r('app.color.brand') : $r('app.color.bg_input'))
          .onClick((): void => {
            this.triggerKind = 0;
          })
        Text('间隔')
          .fontSize(13)
          .fontColor(this.triggerKind === 1 ? $r('app.color.text_on_brand') : $r('app.color.text_secondary'))
          .height(30)
          .padding({ left: 12, right: 12 })
          .borderRadius(15)
          .backgroundColor(this.triggerKind === 1 ? $r('app.color.brand') : $r('app.color.bg_input'))
          .onClick((): void => {
            this.triggerKind = 1;
          })
        Text('定时一次')
          .fontSize(13)
          .fontColor(this.triggerKind === 2 ? $r('app.color.text_on_brand') : $r('app.color.text_secondary'))
          .height(30)
          .padding({ left: 12, right: 12 })
          .borderRadius(15)
          .backgroundColor(this.triggerKind === 2 ? $r('app.color.brand') : $r('app.color.bg_input'))
          .onClick((): void => {
            this.triggerKind = 2;
          })
        Text('新邮件')
          .fontSize(13)
          .fontColor(this.triggerKind === 3 ? $r('app.color.text_on_brand') : $r('app.color.text_secondary'))
          .height(30)
          .padding({ left: 12, right: 12 })
          .borderRadius(15)
          .backgroundColor(this.triggerKind === 3 ? $r('app.color.brand') : $r('app.color.bg_input'))
          .onClick((): void => {
            this.triggerKind = 3;
          })
      }
      .width('100%')

      TextInput({
        text: this.valueText,
        placeholder: this.triggerPlaceholder()
      })
        .fontSize(14)
        .height(42)
        .backgroundColor($r('app.color.bg_input'))
        .borderRadius(12)
        .onChange((value: string): void => {
          this.valueText = value;
        })

      TextArea({
        text: this.promptText,
        placeholder: this.examples.length > 0 ? `触发时执行的提示词，如：${this.examples[0]}`
          : '触发时执行的提示词'
      })
        .fontSize(14)
        .height(80)
        .backgroundColor($r('app.color.bg_input'))
        .borderRadius(12)
        .onChange((value: string): void => {
          this.promptText = value;
        })

      if (this.examples.length > 0) {
        Scroll() {
          Row({ space: 8 }) {
            ForEach(this.examples, (example: string) => {
              Text(example)
                .fontSize(11)
                .fontColor($r('app.color.brand'))
                .backgroundColor($r('app.color.brand_light'))
                .borderRadius(10)
                .padding({ left: 10, right: 10, top: 5, bottom: 5 })
                .maxLines(1)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
                .constraintSize({ maxWidth: 180 })
                .onClick((): void => {
                  this.promptText = example;
                })
            }, (example: string, index: number) => `${index}-${example}`)
          }
        }
        .scrollable(ScrollDirection.Horizontal)
        .scrollBar(BarState.Auto)
        .width('100%')
      }

      Row() {
        Column({ space: 3 }) {
          Text('每次运行开新线程')
            .fontSize(14)
            .fontColor($r('app.color.text_primary'))
          Text('关闭时在会话中继续执行')
            .fontSize(11)
            .fontColor($r('app.color.text_tertiary'))
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1)

        Toggle({ type: ToggleType.Switch, isOn: this.freshThread })
          .onChange((isOn: boolean): void => {
            this.freshThread = isOn;
          })
      }
      .width('100%')

      Row() {
        Column({ space: 3 }) {
          Text('执行模型')
            .fontSize(14)
            .fontColor($r('app.color.text_primary'))
          Text(this.modelRef === '' ? '跟随会话与全局默认' : this.modelLabel)
            .fontSize(11)
            .fontColor($r('app.color.text_tertiary'))
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1)

        SymbolGlyph($r('sys.symbol.chevron_right'))
          .fontSize(14)
          .fontColor([$r('app.color.text_tertiary')])
      }
      .width('100%')
      .padding({ top: 10, bottom: 10 })
      .onClick((): void => {
        this.pickerOpen = true;
      })
      .bindSheet(this.pickerOpen, this.pickerBuilder(), {
        height: SheetSize.MEDIUM,
        showClose: true,
        systemMaterial: UiMaterialKit.sheet()
      })

      Row({ space: 12 }) {
        Button($r('app.string.common_cancel'))
          .fontSize(14)
          .height(38)
          .layoutWeight(1)
          .borderRadius(19)
          .backgroundColor($r('app.color.bg_input'))
          .fontColor($r('app.color.text_secondary'))
          .onClick((): void => {
            this.controller?.close();
          })
        Button(this.submitting ? '保存中...' : (this.isEdit ? '保存' : '创建'))
          .fontSize(14)
          .height(38)
          .layoutWeight(1)
          .borderRadius(19)
          .linearGradient({
            angle: 140,
            colors: [[$r('app.color.brand_grad_start'), 0], [$r('app.color.brand_grad_end'), 1]]
          })
          .shadow({ radius: 10, color: '#260A59F7', offsetY: 4 })
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

  @Builder
  pickerBuilder() {
    ModelPickerSheet({
      onPick: (ref: string, label: string): void => {
        this.modelRef = ref;
        this.modelLabel = ref === '' ? '' : label;
        this.pickerOpen = false;
      }
    })
  }
}
