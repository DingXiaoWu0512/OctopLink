import { CronJobModel } from '../../model/WorkspaceModels';
import { CronService } from '../../service/WorkspaceService';
import { OctopApiError } from '../../net/HttpClient';
import { SessionStore } from '../../store/SessionStore';
import { EmptyView } from '../../components/EmptyView';
import { ErrorRetry } from '../../components/ErrorRetry';
import { CronCreateDialog } from '../../components/CronCreateDialog';
import { TimeFormat } from '../../utils/TimeFormat';
import { PageHeader } from '../../components/PageHeader';
import { UiMaterialKit } from '../../components/UiMaterialKit';

/** 定时任务管理（当前专家） */
@Component
export struct CronPage {
  @State jobs: Array<CronJobModel> = [];
  @State loading: boolean = true;
  @State refreshing: boolean = false;
  @State errorMsg: string = '';
  @State operating: boolean = false;
  private agentId: string = '';
  private pathStack: NavPathStack | null = null;
  private createController: CustomDialogController | null = null;

  private onNavReady(ctx: NavDestinationContext): void {
    this.pathStack = ctx.pathStack;
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
      this.jobs = await CronService.list(this.agentId);
    } catch (e) {
      this.errorMsg = e instanceof OctopApiError ? e.message : '定时任务加载失败';
    } finally {
      this.loading = false;
    }
  }

  private showCreate(): void {
    this.createController = new CustomDialogController({
      builder: CronCreateDialog({
        agentId: this.agentId,
        onCreated: (): void => {
          this.load();
        }
      }),
      autoCancel: true
    });
    this.createController.open();
  }

  private async toggle(job: CronJobModel, on: boolean): Promise<void> {
    if (this.operating) {
      return;
    }
    this.operating = true;
    try {
      await CronService.setEnabled(this.agentId, job.id, on);
      await this.load();
    } catch (e) {
      const message: string = e instanceof OctopApiError ? e.message : '操作失败';
      this.getUIContext().getPromptAction().showToast({ message });
    } finally {
      this.operating = false;
    }
  }

  private async runNow(job: CronJobModel): Promise<void> {
    if (this.operating) {
      return;
    }
    this.operating = true;
    try {
      await CronService.runNow(this.agentId, job.id);
      this.getUIContext().getPromptAction().showToast({ message: '已触发执行' });
      await this.load();
    } catch (e) {
      const message: string = e instanceof OctopApiError ? e.message : '触发失败';
      this.getUIContext().getPromptAction().showToast({ message });
    } finally {
      this.operating = false;
    }
  }

  private confirmDelete(job: CronJobModel): void {
    this.getUIContext().showAlertDialog({
      title: '删除任务',
      message: `确定删除「${job.name === '' ? job.triggerDisplay() : job.name}」吗？`,
      primaryButton: {
        value: $r('app.string.common_cancel'),
        action: (): void => {
        }
      },
      secondaryButton: {
        value: $r('app.string.common_confirm'),
        action: (): void => {
          this.deleteJob(job);
        }
      },
      alignment: DialogAlignment.Bottom
    });
  }

  private async deleteJob(job: CronJobModel): Promise<void> {
    if (this.operating) {
      return;
    }
    this.operating = true;
    try {
      await CronService.remove(this.agentId, job.id);
      await this.load();
    } catch (e) {
      const message: string = e instanceof OctopApiError ? e.message : '删除失败';
      this.getUIContext().getPromptAction().showToast({ message });
    } finally {
      this.operating = false;
    }
  }

  build() {
    NavDestination() {
      Stack({ alignContent: Alignment.BottomEnd }) {
        Column() {
          PageHeader({ title: '定时任务' })

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
          } else if (this.jobs.length === 0) {
            Column() {
              EmptyView({
                title: '暂无定时任务',
                subtitle: '点击右下角按钮创建',
                icon: $r('sys.symbol.clock')
              })
            }
            .layoutWeight(1)
            .width('100%')
            .justifyContent(FlexAlign.Center)
          } else {
            Refresh({ refreshing: $$this.refreshing }) {
              List({ space: 12 }) {
                ForEach(this.jobs, (job: CronJobModel) => {
                  ListItem() {
                    Row({ space: 12 }) {
                      Column() {
                        SymbolGlyph($r('sys.symbol.clock'))
                          .fontSize(20)
                          .fontColor([$r('app.color.brand')])
                      }
                      .width(42)
                      .height(42)
                      .borderRadius(13)
                      .backgroundColor($r('app.color.brand_light'))
                      .justifyContent(FlexAlign.Center)
                      .opacity(job.enabled ? 1 : 0.45)
                      Column({ space: 7 }) {
                        Row() {
                          Text(job.name === '' ? '未命名任务' : job.name)
                            .fontSize(16)
                            .fontWeight(FontWeight.Medium)
                            .fontColor(job.enabled ? $r('app.color.text_primary') : $r('app.color.text_tertiary'))
                            .maxLines(1)
                            .textOverflow({ overflow: TextOverflow.Ellipsis })
                            .layoutWeight(1)
                          Toggle({ type: ToggleType.Switch, isOn: job.enabled })
                            .onChange((isOn: boolean): void => {
                              this.toggle(job, isOn);
                            })
                        }
                        .width('100%')
                        Text(job.prompt)
                          .fontSize(13)
                          .fontColor($r('app.color.text_secondary'))
                          .maxLines(2)
                          .textOverflow({ overflow: TextOverflow.Ellipsis })
                          .width('100%')
                          .lineHeight(19)
                        Row({ space: 8 }) {
                          Text(job.triggerDisplay())
                            .fontSize(11)
                            .fontColor($r('app.color.brand'))
                            .backgroundColor($r('app.color.brand_light'))
                            .borderRadius(6)
                            .padding({ left: 8, right: 8, top: 3, bottom: 3 })
                            .maxLines(1)
                          if (job.lastRunAtMs > 0) {
                            Text(`上次 ${TimeFormat.list(job.lastRunAtMs)}`)
                              .fontSize(11)
                              .fontColor($r('app.color.text_tertiary'))
                              .maxLines(1)
                          }
                          if (job.lastStatus !== '' && job.lastStatus !== 'ok') {
                            Text(job.lastStatus)
                              .fontSize(11)
                              .fontColor($r('app.color.danger'))
                              .backgroundColor($r('app.color.danger_soft'))
                              .borderRadius(6)
                              .padding({ left: 8, right: 8, top: 3, bottom: 3 })
                              .maxLines(1)
                          }
                          Blank()
                          Row({ space: 4 }) {
                            SymbolGlyph($r('sys.symbol.play'))
                              .fontSize(12)
                              .fontColor([$r('app.color.brand')])
                            Text('立即执行')
                              .fontSize(12)
                              .fontWeight(FontWeight.Medium)
                              .fontColor($r('app.color.brand'))
                          }
                          .onClick((): void => {
                            this.runNow(job);
                          })
                        }
                        .width('100%')
                      }
                      .layoutWeight(1)
                      .alignItems(HorizontalAlign.Start)
                    }
                    .width('100%')
                    .padding({ left: 14, right: 14, top: 14, bottom: 14 })
                    .borderRadius(16)
                    .backgroundColor($r('app.color.bg_card'))
                    .gesture(
                      LongPressGesture()
                        .onAction((event: GestureEvent): void => {
                          this.confirmDelete(job);
                        })
                    )
                  }
                }, (job: CronJobModel) => job.id)
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
          this.showCreate();
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
