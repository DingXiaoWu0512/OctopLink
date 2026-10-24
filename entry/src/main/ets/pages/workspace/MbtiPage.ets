import { MbtiTypeModel } from '../../model/WorkspaceModels';
import { MbtiService } from '../../service/WorkspaceService';
import { OctopApiError } from '../../net/HttpClient';
import { SessionStore } from '../../store/SessionStore';
import { ErrorRetry } from '../../components/ErrorRetry';
import { PageHeader } from '../../components/PageHeader';

/** MBTI 人格：浏览 16 类型并应用到当前专家 */
@Component
export struct MbtiPage {
  @State types: Array<MbtiTypeModel> = [];
  @State currentCode: string = '';
  @State loading: boolean = true;
  @State errorMsg: string = '';
  @State applying: boolean = false;
  private agentId: string = '';

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

  private confirmApply(type: MbtiTypeModel): void {
    if (this.applying) {
      return;
    }
    this.getUIContext().showAlertDialog({
      title: `应用「${type.code} ${type.nameZh}」`,
      message: '将重新生成专家的 SOUL.md 并重载，确定应用该人格吗？',
      primaryButton: {
        value: $r('app.string.common_cancel'),
        action: (): void => {
        }
      },
      secondaryButton: {
        value: $r('app.string.common_confirm'),
        action: (): void => {
          this.applyType(type);
        }
      },
      alignment: DialogAlignment.Bottom
    });
  }

  private async applyType(type: MbtiTypeModel): Promise<void> {
    if (this.applying) {
      return;
    }
    this.applying = true;
    try {
      await MbtiService.apply(this.agentId, type.code);
      this.currentCode = type.code;
      SessionStore.markAgentsDirty();
      this.getUIContext().getPromptAction().showToast({ message: `已应用 ${type.code} ${type.nameZh}` });
    } catch (e) {
      const message: string = e instanceof OctopApiError ? e.message : '应用失败';
      this.getUIContext().getPromptAction().showToast({ message });
    } finally {
      this.applying = false;
    }
  }

  build() {
    NavDestination() {
      Column() {
        PageHeader({ title: 'MBTI 人格' })

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
              }
              .width('100%')
              .padding({ left: 14, right: 14, top: 10, bottom: 10 })
              .borderRadius(12)
              .backgroundColor(this.currentCode === ''
                ? $r('app.color.bg_input') : $r('app.color.brand_light'))
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
                    this.confirmApply(type);
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
