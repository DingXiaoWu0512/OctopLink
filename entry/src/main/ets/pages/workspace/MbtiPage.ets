import { MbtiDimensionModel, MbtiQuestionModel, MbtiTypeModel } from '../../model/WorkspaceModels';
import { MbtiService } from '../../service/WorkspaceService';
import { OctopApiError } from '../../net/HttpClient';
import { SessionStore } from '../../store/SessionStore';
import { ErrorRetry } from '../../components/ErrorRetry';
import { PageHeader } from '../../components/PageHeader';
import { UiMaterialKit } from '../../components/UiMaterialKit';

/** MBTI 人格：28 题测试流程 + 16 类型浏览并应用到当前专家 */
@Component
export struct MbtiPage {
  @State types: Array<MbtiTypeModel> = [];
  @State currentCode: string = '';
  @State loading: boolean = true;
  @State errorMsg: string = '';
  @State applying: boolean = false;
  /** grid=类型网格 | testing=答题 | result=测试结果 */
  @State mode: string = 'grid';
  @State questions: Array<MbtiQuestionModel> = [];
  @State qIndex: number = 0;
  @State submitting: boolean = false;
  @State resultCode: string = '';
  @State resultProfile: MbtiTypeModel | null = null;
  @State detailOpen: boolean = false;
  @State detailType: MbtiTypeModel | null = null;
  @State detailPreview: string = '';
  @State detailLoading: boolean = false;
  private agentId: string = '';
  private answers: Record<string, Object> = {};

  private onNavReady(ctx: NavDestinationContext): void {
    this.agentId = AppStorage.get<string>(SessionStore.KEY_AGENT_ID) ?? '';
    if (this.agentId === '') {
      this.loading = false;
      this.errorMsg = '未选择专家，请先在专家页选择';
      return;
    }
    this.load();
  }

  private async load(): Promise<void> {
    this.loading = true;
    this.errorMsg = '';
    try {
      this.types = await MbtiService.listTypes();
    } catch (e) {
      this.errorMsg = e instanceof OctopApiError ? e.message : '人格类型加载失败';
      this.loading = false;
      return;
    }
    // 当前人格尽力获取（无权限时静默忽略）
    try {
      this.currentCode = await MbtiService.current(this.agentId);
    } catch (e) {
      this.currentCode = '';
    }
    this.loading = false;
  }

  private async startTest(): Promise<void> {
    if (this.submitting) {
      return;
    }
    this.submitting = true;
    try {
      this.questions = await MbtiService.questions();
      if (this.questions.length === 0) {
        this.getUIContext().getPromptAction().showToast({ message: '测试题加载失败' });
        this.submitting = false;
        return;
      }
      this.answers = {};
      this.qIndex = 0;
      this.mode = 'testing';
    } catch (e) {
      const message: string = e instanceof OctopApiError ? e.message : '测试题加载失败';
      this.getUIContext().getPromptAction().showToast({ message });
    } finally {
      this.submitting = false;
    }
  }

  private answer(choice: string): void {
    const question: MbtiQuestionModel = this.questions[this.qIndex];
    this.answers[String(question.id)] = choice;
    if (this.qIndex + 1 < this.questions.length) {
      this.qIndex += 1;
      return;
    }
    this.submitTest();
  }

  private async submitTest(): Promise<void> {
    if (this.submitting) {
      return;
    }
    this.submitting = true;
    try {
      const result = await MbtiService.submit(this.answers, false);
      this.resultCode = result.code;
      this.resultProfile = result.profile;
      this.mode = 'result';
    } catch (e) {
      const message: string = e instanceof OctopApiError ? e.message : '答卷提交失败';
      this.getUIContext().getPromptAction().showToast({ message });
    } finally {
      this.submitting = false;
    }
  }

  private confirmApply(code: string, nameZh: string): void {
    if (this.applying) {
      return;
    }
    this.getUIContext().showAlertDialog({
      title: `应用「${code} ${nameZh}」`,
      message: '将重新生成专家的 SOUL.md 并重载，确定应用该人格吗？',
      primaryButton: {
        value: $r('app.string.common_cancel'),
        action: (): void => {
        }
      },
      secondaryButton: {
        value: $r('app.string.common_confirm'),
        action: (): void => {
          this.applyCode(code, nameZh);
        }
      },
      alignment: DialogAlignment.Bottom
    });
  }

  private async applyCode(code: string, nameZh: string): Promise<void> {
    if (this.applying) {
      return;
    }
    this.applying = true;
    try {
      await MbtiService.apply(this.agentId, code);
      this.currentCode = code;
      SessionStore.markAgentsDirty();
      this.getUIContext().getPromptAction().showToast({ message: `已应用 ${code} ${nameZh}` });
    } catch (e) {
      const message: string = e instanceof OctopApiError ? e.message : '应用失败';
      this.getUIContext().getPromptAction().showToast({ message });
    } finally {
      this.applying = false;
    }
  }

  private openDetail(type: MbtiTypeModel): void {
    this.detailType = type;
    this.detailPreview = '';
    this.detailOpen = true;
    this.loadDetail(type.code);
  }

  private async loadDetail(code: string): Promise<void> {
    this.detailLoading = true;
    try {
      const detail = await MbtiService.typeDetail(code);
      if (this.detailType !== null && this.detailType.code === code) {
        this.detailType = detail;
      }
    } catch (e) {
      // 详情加载失败时保留列表卡片数据
    }
    try {
      const preview = await MbtiService.preview(code);
      if (this.detailType !== null && this.detailType.code === code) {
        this.detailPreview = preview;
      }
    } catch (e) {
      this.detailPreview = '';
    }
    this.detailLoading = false;
  }

  build() {
    NavDestination() {
      Column() {
        PageHeader({
          title: this.mode === 'testing' ? 'MBTI 测试' : (this.mode === 'result' ? '测试结果' : 'MBTI 人格'),
          onBack: this.mode === 'grid' ? null : (): void => {
            this.mode = 'grid';
          }
        })

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
        } else if (this.mode === 'testing') {
          this.testingBody()
        } else if (this.mode === 'result') {
          this.resultBody()
        } else {
          this.gridBody()
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
  gridBody() {
    Scroll() {
      Column({ space: 12 }) {
        Row({ space: 8 }) {
          SymbolGlyph($r('sys.symbol.face_smiling'))
            .fontSize(15)
            .fontColor([$r('app.color.brand')])
          Text(this.currentCode === '' ? '点击类型卡片，为当前专家设定人格'
            : `当前人格：${this.currentCode}`)
            .fontSize(13)
            .fontWeight(FontWeight.Medium)
            .fontColor(this.currentCode === '' ? $r('app.color.text_secondary') : $r('app.color.brand'))
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .layoutWeight(1)
        }
        .width('100%')
        .padding({ left: 14, right: 14, top: 10, bottom: 10 })
        .borderRadius(12)
        .backgroundColor(this.currentCode === ''
          ? $r('app.color.bg_input') : $r('app.color.brand_light'))

        Row({ space: 12 }) {
          Column({ space: 4 }) {
            Text('MBTI 人格测试')
              .fontSize(15)
              .fontWeight(FontWeight.Bold)
              .fontColor($r('app.color.text_on_brand'))
            Text('28 道题，测出专家最适合的人格')
              .fontSize(12)
              .fontColor($r('app.color.text_on_brand'))
              .opacity(0.85)
          }
          .alignItems(HorizontalAlign.Start)
          .layoutWeight(1)

          Button(this.submitting ? '加载中...' : '开始测试')
            .fontSize(13)
            .height(34)
            .borderRadius(17)
            .backgroundColor($r('app.color.bg_card'))
            .fontColor($r('app.color.brand'))
            .enabled(!this.submitting)
            .onClick((): void => {
              this.startTest();
            })
        }
        .width('100%')
        .padding({ left: 16, right: 16, top: 14, bottom: 14 })
        .borderRadius(16)
        .linearGradient({
          angle: 135,
          colors: [[$r('app.color.brand_grad_start'), 0], [$r('app.color.brand_grad_end'), 1]]
        })
        .shadow({ radius: 12, color: '#260A59F7', offsetY: 4 })

        Flex({ direction: FlexDirection.Row, wrap: FlexWrap.Wrap, justifyContent: FlexAlign.Start }) {
          ForEach(this.types, (type: MbtiTypeModel) => {
            Column({ space: 6 }) {
              Row({ space: 8 }) {
                Text(type.code)
                  .fontSize(16)
                  .fontWeight(FontWeight.Bold)
                  .fontColor(type.code === this.currentCode
                    ? $r('app.color.brand') : $r('app.color.text_primary'))
                if (type.code === this.currentCode) {
                  Text('使用中')
                    .fontSize(10)
                    .fontColor($r('app.color.text_on_brand'))
                    .backgroundColor($r('app.color.brand'))
                    .borderRadius(8)
                    .padding({ left: 8, right: 8, top: 2, bottom: 2 })
                }
              }
              Text(type.nameZh)
                .fontSize(14)
                .fontColor($r('app.color.text_secondary'))
              if (type.summaryZh !== '') {
                Text(type.summaryZh)
                  .fontSize(11)
                  .fontColor($r('app.color.text_tertiary'))
                  .maxLines(3)
                  .textOverflow({ overflow: TextOverflow.Ellipsis })
                  .textAlign(TextAlign.Start)
              }
            }
            .width('47%')
            .padding(12)
            .borderRadius(16)
            .backgroundColor(type.code === this.currentCode
              ? $r('app.color.brand_light') : $r('app.color.bg_card'))
            .border({
              width: type.code === this.currentCode ? 1.5 : 1,
              color: type.code === this.currentCode
                ? $r('app.color.brand') : $r('app.color.card_stroke')
            })
            .shadow({ radius: 10, color: '#0A000000', offsetY: 3 })
            .alignItems(HorizontalAlign.Start)
            .margin(4)
            .constraintSize({ minHeight: 110 })
            .justifyContent(FlexAlign.Start)
            .onClick((): void => {
              this.openDetail(type);
            })
          }, (type: MbtiTypeModel) => type.code)
        }
        .width('100%')
      }
      .width('100%')
      .padding({ left: 14, right: 14, top: 12, bottom: 24 })
    }
    .layoutWeight(1)
    .width('100%')
    .scrollBar(BarState.Off)
    .bindSheet(this.detailOpen, this.detailBuilder(), {
      systemMaterial: UiMaterialKit.sheet(),
      detents: [SheetSize.MEDIUM, SheetSize.LARGE],
      showClose: true
    })
  }

  @Builder
  testingBody() {
    Column({ space: 18 }) {
      Progress({ value: this.qIndex + 1, total: this.questions.length, type: ProgressType.Linear })
        .width('80%')
        .color($r('app.color.brand'))

      Text(`第 ${this.qIndex + 1} / ${this.questions.length} 题`)
        .fontSize(12)
        .fontColor($r('app.color.text_tertiary'))

      Column({ space: 16 }) {
        Text(this.questions[this.qIndex].dimension)
          .fontSize(11)
          .fontColor($r('app.color.brand'))
          .backgroundColor($r('app.color.brand_light'))
          .borderRadius(8)
          .padding({ left: 10, right: 10, top: 3, bottom: 3 })
        Text(this.questions[this.qIndex].questionZh)
          .fontSize(19)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.text_primary'))
          .textAlign(TextAlign.Center)
          .lineHeight(28)
      }
      .constraintSize({ minHeight: 140 })
      .justifyContent(FlexAlign.Center)

      if (this.submitting) {
        LoadingProgress()
          .width(28)
          .height(28)
          .color($r('app.color.brand'))
      } else {
        Column({ space: 12 }) {
          Button() {
            Row({ space: 10 }) {
              Text('A')
                .fontSize(14)
                .fontWeight(FontWeight.Bold)
                .fontColor($r('app.color.brand'))
                .width(30)
                .height(30)
                .textAlign(TextAlign.Center)
                .borderRadius(15)
                .backgroundColor($r('app.color.brand_light'))
              Text(this.questions[this.qIndex].optionAZh)
                .fontSize(15)
                .fontColor($r('app.color.text_primary'))
                .maxLines(2)
                .textAlign(TextAlign.Start)
                .layoutWeight(1)
            }
            .width('100%')
          }
          .buttonStyle(ButtonStyleMode.NORMAL)
          .backgroundColor($r('app.color.bg_card'))
          .border({ width: 1, color: $r('app.color.card_stroke') })
          .borderRadius(16)
          .width('100%')
          .height(64)
          .onClick((): void => {
            this.answer('A');
          })

          Button() {
            Row({ space: 10 }) {
              Text('B')
                .fontSize(14)
                .fontWeight(FontWeight.Bold)
                .fontColor($r('app.color.brand'))
                .width(30)
                .height(30)
                .textAlign(TextAlign.Center)
                .borderRadius(15)
                .backgroundColor($r('app.color.brand_light'))
              Text(this.questions[this.qIndex].optionBZh)
                .fontSize(15)
                .fontColor($r('app.color.text_primary'))
                .maxLines(2)
                .textAlign(TextAlign.Start)
                .layoutWeight(1)
            }
            .width('100%')
          }
          .buttonStyle(ButtonStyleMode.NORMAL)
          .backgroundColor($r('app.color.bg_card'))
          .border({ width: 1, color: $r('app.color.card_stroke') })
          .borderRadius(16)
          .width('100%')
          .height(64)
          .onClick((): void => {
            this.answer('B');
          })
        }
        .width('100%')
        .padding({ left: 20, right: 20 })
      }
    }
    .width('100%')
    .layoutWeight(1)
    .padding({ top: 20, left: 20, right: 20, bottom: 30 })
    .justifyContent(FlexAlign.Start)
  }

  @Builder
  resultBody() {
    Scroll() {
      Column({ space: 16 }) {
        Column({ space: 8 }) {
          Text(this.resultCode)
            .fontSize(52)
            .fontWeight(FontWeight.Bold)
            .fontColor(this.resultProfile !== null && this.resultProfile.color !== ''
              ? this.resultProfile.color : $r('app.color.brand'))
          Text(this.resultProfile === null ? '' : this.resultProfile.nameZh)
            .fontSize(20)
            .fontWeight(FontWeight.Medium)
            .fontColor($r('app.color.text_primary'))
          Text(this.resultProfile === null ? '' : this.resultProfile.nameEn)
            .fontSize(13)
            .fontColor($r('app.color.text_tertiary'))
        }
        .width('100%')
        .padding({ top: 20, bottom: 8 })

        if (this.resultProfile !== null && this.resultProfile.summaryZh !== '') {
          Text(this.resultProfile.summaryZh)
            .fontSize(13)
            .fontColor($r('app.color.text_secondary'))
            .lineHeight(21)
            .width('100%')
            .padding({ left: 16, right: 16, top: 12, bottom: 12 })
            .borderRadius(14)
            .backgroundColor($r('app.color.bg_card'))
            .border({ width: 1, color: $r('app.color.card_stroke') })
        }

        if (this.resultProfile !== null && this.resultProfile.dimensions.length > 0) {
          Column({ space: 12 }) {
            ForEach(this.resultProfile.dimensions, (dim: MbtiDimensionModel) => {
              Column({ space: 5 }) {
                Row() {
                  Text(`${dim.labelZh()} ${dim.pole}`)
                    .fontSize(12)
                    .fontWeight(FontWeight.Medium)
                    .fontColor($r('app.color.text_secondary'))
                  Blank()
                  Text(`${dim.percent}%`)
                    .fontSize(12)
                    .fontColor($r('app.color.brand'))
                }
                .width('100%')
                Progress({ value: dim.percent, total: 100, type: ProgressType.Linear })
                  .width('100%')
                  .color($r('app.color.brand'))
              }
              .width('100%')
            }, (dim: MbtiDimensionModel) => dim.key)
          }
          .width('100%')
          .padding(16)
          .borderRadius(14)
          .backgroundColor($r('app.color.bg_card'))
          .border({ width: 1, color: $r('app.color.card_stroke') })
        }

        Row({ space: 12 }) {
          Button('重新测试')
            .fontSize(14)
            .height(42)
            .layoutWeight(1)
            .borderRadius(21)
            .backgroundColor($r('app.color.bg_input'))
            .fontColor($r('app.color.text_secondary'))
            .onClick((): void => {
              this.startTest();
            })
          Button(this.applying ? '应用中...' : '应用到当前专家')
            .fontSize(14)
            .height(42)
            .layoutWeight(1)
            .borderRadius(21)
            .linearGradient({
              angle: 140,
              colors: [[$r('app.color.brand_grad_start'), 0], [$r('app.color.brand_grad_end'), 1]]
            })
            .fontColor($r('app.color.text_on_brand'))
            .enabled(!this.applying)
            .onClick((): void => {
              const nameZh: string = this.resultProfile === null ? '' : this.resultProfile.nameZh;
              this.confirmApply(this.resultCode, nameZh);
            })
        }
        .width('100%')
        .margin({ top: 6, bottom: 30 })
      }
      .width('100%')
      .padding({ left: 20, right: 20 })
    }
    .layoutWeight(1)
    .width('100%')
    .scrollBar(BarState.Off)
  }

  @Builder
  detailBuilder() {
    Column({ space: 14 }) {
      if (this.detailType === null) {
        LoadingProgress()
          .width(28)
          .height(28)
          .color($r('app.color.brand'))
          .margin({ top: 40 })
      } else {
        Row({ space: 12 }) {
          Text(this.detailType.code)
            .fontSize(30)
            .fontWeight(FontWeight.Bold)
            .fontColor(this.detailType.color !== '' ? this.detailType.color : $r('app.color.brand'))
          Column({ space: 3 }) {
            Text(this.detailType.nameZh)
              .fontSize(16)
              .fontWeight(FontWeight.Medium)
              .fontColor($r('app.color.text_primary'))
            Text(this.detailType.nameEn)
              .fontSize(12)
              .fontColor($r('app.color.text_tertiary'))
          }
          .alignItems(HorizontalAlign.Start)
          .layoutWeight(1)
        }
        .width('100%')

        if (this.detailType.nicknameZh !== '') {
          Text(`「${this.detailType.nicknameZh}」`)
            .fontSize(13)
            .fontColor($r('app.color.brand'))
            .width('100%')
        }

        if (this.detailType.summaryZh !== '') {
          Text(this.detailType.summaryZh)
            .fontSize(13)
            .fontColor($r('app.color.text_secondary'))
            .lineHeight(21)
            .width('100%')
        }

        if (this.detailType.dimensions.length > 0) {
          Column({ space: 10 }) {
            ForEach(this.detailType.dimensions, (dim: MbtiDimensionModel) => {
              Column({ space: 5 }) {
                Row() {
                  Text(`${dim.labelZh()} ${dim.pole}`)
                    .fontSize(12)
                    .fontWeight(FontWeight.Medium)
                    .fontColor($r('app.color.text_secondary'))
                  Blank()
                  Text(`${dim.percent}%`)
                    .fontSize(12)
                    .fontColor($r('app.color.brand'))
                }
                .width('100%')
                Progress({ value: dim.percent, total: 100, type: ProgressType.Linear })
                  .width('100%')
                  .color($r('app.color.brand'))
              }
              .width('100%')
            }, (dim: MbtiDimensionModel) => dim.key)
          }
          .width('100%')
          .padding(14)
          .borderRadius(14)
          .backgroundColor($r('app.color.bg_input'))
        }

        if (this.detailLoading) {
          Row({ space: 8 }) {
            LoadingProgress()
              .width(16)
              .height(16)
              .color($r('app.color.text_tertiary'))
            Text('加载人格模板预览...')
              .fontSize(12)
              .fontColor($r('app.color.text_tertiary'))
          }
        } else if (this.detailPreview !== '') {
          Column({ space: 8 }) {
            Text('SOUL.md 模板预览')
              .fontSize(12)
              .fontWeight(FontWeight.Medium)
              .fontColor($r('app.color.text_secondary'))
              .width('100%')
            Scroll() {
              Text(this.detailPreview)
                .fontSize(11)
                .fontColor($r('app.color.text_tertiary'))
                .lineHeight(17)
            }
            .constraintSize({ maxHeight: 180 })
            .width('100%')
            .align(Alignment.TopStart)
            .scrollBar(BarState.Auto)
          }
          .width('100%')
        }

        Button(this.detailType.code === this.currentCode ? '当前人格' : '应用到当前专家')
          .fontSize(14)
          .height(42)
          .borderRadius(21)
          .width('100%')
          .linearGradient({
            angle: 140,
            colors: [[$r('app.color.brand_grad_start'), 0], [$r('app.color.brand_grad_end'), 1]]
          })
          .fontColor($r('app.color.text_on_brand'))
          .enabled(this.detailType.code !== this.currentCode && !this.applying)
          .onClick((): void => {
            const code: string = this.detailType === null ? '' : this.detailType.code;
            const nameZh: string = this.detailType === null ? '' : this.detailType.nameZh;
            this.confirmApply(code, nameZh);
          })
      }
    }
    .padding({ left: 20, right: 20, top: 24, bottom: 30 })
    .width('100%')
  }
}
