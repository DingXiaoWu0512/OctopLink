import { UsageService } from '../../service/UsageService';
import { UsageBucketModel, UsageSummaryModel } from '../../model/UsageModels';
import { OctopApiError } from '../../net/HttpClient';
import { EmptyView } from '../../components/EmptyView';
import { ErrorRetry } from '../../components/ErrorRetry';
import { PageHeader } from '../../components/PageHeader';
import { TimeFormat } from '../../utils/TimeFormat';
import { picker, fileIo } from '@kit.CoreFileKit';

/** 汇总指标单元格（ForEach 用稳定对象） */
class UsageMetricCell {
  readonly label: string;
  readonly value: string;

  constructor(label: string, value: string) {
    this.label = label;
    this.value = value;
  }
}

/** Token 用量统计：窗口/粒度选择 + 汇总卡片 + 分布明细 + 导出 Excel */
@Component
export struct UsagePage {
  @State windowKey: string = 'last_7d';
  @State granularityKey: string = 'by_day';
  @State summary: UsageSummaryModel | null = null;
  @State loading: boolean = true;
  @State refreshing: boolean = false;
  @State errorMsg: string = '';
  @State exporting: boolean = false;

  private onNavReady(ctx: NavDestinationContext): void {
    this.load();
  }

  private async load(): Promise<void> {
    this.loading = this.summary === null;
    this.errorMsg = '';
    try {
      this.summary = await UsageService.summary(this.windowKey, this.granularityKey);
    } catch (e) {
      this.errorMsg = e instanceof OctopApiError ? e.message : '用量加载失败';
    } finally {
      this.loading = false;
    }
  }

  private windowLabel(key: string): string {
    const label: string = UsageService.WINDOW_LABELS[key];
    if (label === undefined || label === '') {
      return key;
    }
    return label;
  }

  private granularityLabel(key: string): string {
    const label: string = UsageService.GRANULARITY_LABELS[key];
    if (label === undefined || label === '') {
      return key;
    }
    return label;
  }

  private hasData(): boolean {
    if (this.summary === null) {
      return false;
    }
    return this.summary.totalTokens > 0 || this.summary.buckets.length > 0;
  }

  private totalText(): string {
    if (this.summary === null) {
      return '0';
    }
    return this.summary.totalTokens.toLocaleString();
  }

  private rangeText(): string {
    if (this.summary === null) {
      return '';
    }
    const start: string = TimeFormat.full(this.summary.rangeStartSec * 1000);
    const end: string = TimeFormat.full(this.summary.rangeEndSec * 1000);
    if (start === '' && end === '') {
      return '';
    }
    return `${start} ~ ${end}`;
  }

  private metricCells(): Array<UsageMetricCell> {
    if (this.summary === null) {
      return [];
    }
    const s: UsageSummaryModel = this.summary;
    const cells: Array<UsageMetricCell> = [
      new UsageMetricCell('输入', s.inputTokens.toLocaleString()),
      new UsageMetricCell('输出', s.outputTokens.toLocaleString()),
      new UsageMetricCell('推理', s.reasoningTokens.toLocaleString()),
      new UsageMetricCell('缓存读取', s.cacheReadTokens.toLocaleString()),
      new UsageMetricCell('模型调用', s.modelCalls.toLocaleString()),
      new UsageMetricCell('对话轮次', s.turns.toLocaleString()),
      new UsageMetricCell('平均每轮', s.avgPerTurn.toLocaleString()),
      new UsageMetricCell('缓存命中', `${s.cacheHitPercent}%`)
    ];
    return cells;
  }

  private buckets(): Array<UsageBucketModel> {
    if (this.summary === null) {
      return [];
    }
    return this.summary.buckets;
  }

  private bucketLabel(bucket: UsageBucketModel): string {
    if (bucket.label === '') {
      return bucket.key;
    }
    return bucket.label;
  }

  private bucketSubText(bucket: UsageBucketModel): string {
    return `${bucket.totalTokens.toLocaleString()} tokens · ${bucket.modelCalls} 次调用 · ${bucket.turns} 轮`;
  }

  private bucketBarWidth(bucket: UsageBucketModel): string {
    if (this.summary === null) {
      return '0%';
    }
    let maxTotal: number = 0;
    for (const item of this.summary.buckets) {
      if (item.totalTokens > maxTotal) {
        maxTotal = item.totalTokens;
      }
    }
    if (maxTotal <= 0 || bucket.totalTokens <= 0) {
      return '0%';
    }
    const pct: number = Math.round(bucket.totalTokens * 100 / maxTotal);
    return `${pct}%`;
  }

  private exportLabel(): string {
    if (this.exporting) {
      return '导出中...';
    }
    return '导出 Excel';
  }

  private async exportExcel(): Promise<void> {
    if (this.exporting) {
      return;
    }
    this.exporting = true;
    try {
      const buffer: ArrayBuffer = await UsageService.exportXlsx(this.windowKey);
      const docPicker = new picker.DocumentViewPicker();
      const opts = new picker.DocumentSaveOptions();
      opts.newFileNames = [`usage_${this.windowKey}.xlsx`];
      const uris: Array<string> = await docPicker.save(opts);
      if (uris.length > 0) {
        const file = fileIo.openSync(uris[0], fileIo.OpenMode.READ_WRITE);
        fileIo.writeSync(file.fd, buffer);
        fileIo.closeSync(file);
        this.getUIContext().getPromptAction().showToast({ message: '已保存' });
      }
    } catch (e) {
      const message: string = e instanceof OctopApiError ? e.message : '导出失败';
      this.getUIContext().getPromptAction().showToast({ message });
    } finally {
      this.exporting = false;
    }
  }

  build() {
    NavDestination() {
      Column() {
        PageHeader({ title: 'Token 用量' })

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
          Refresh({ refreshing: $$this.refreshing }) {
            Scroll() {
              Column() {
                Scroll() {
                  Row({ space: 8 }) {
                    ForEach(UsageService.WINDOWS, (item: string) => {
                      if (this.windowKey === item) {
                        Text(this.windowLabel(item))
                          .fontSize(12)
                          .fontWeight(FontWeight.Medium)
                          .fontColor($r('app.color.text_on_brand'))
                          .backgroundColor($r('app.color.brand'))
                          .height(30)
                          .padding({ left: 12, right: 12 })
                          .borderRadius(15)
                          .maxLines(1)
                          .onClick((): void => {
                            this.windowKey = item;
                            this.load();
                          })
                      } else {
                        Text(this.windowLabel(item))
                          .fontSize(12)
                          .fontColor($r('app.color.text_secondary'))
                          .backgroundColor($r('app.color.bg_input'))
                          .height(30)
                          .padding({ left: 12, right: 12 })
                          .borderRadius(15)
                          .maxLines(1)
                          .onClick((): void => {
                            this.windowKey = item;
                            this.load();
                          })
                      }
                    }, (item: string) => item)
                  }
                }
                .scrollable(ScrollDirection.Horizontal)
                .scrollBar(BarState.Off)
                .width('100%')

                Scroll() {
                  Row({ space: 8 }) {
                    ForEach(UsageService.GRANULARITIES, (item: string) => {
                      if (this.granularityKey === item) {
                        Text(this.granularityLabel(item))
                          .fontSize(12)
                          .fontWeight(FontWeight.Medium)
                          .fontColor($r('app.color.text_on_brand'))
                          .backgroundColor($r('app.color.brand'))
                          .height(30)
                          .padding({ left: 12, right: 12 })
                          .borderRadius(15)
                          .maxLines(1)
                          .onClick((): void => {
                            this.granularityKey = item;
                            this.load();
                          })
                      } else {
                        Text(this.granularityLabel(item))
                          .fontSize(12)
                          .fontColor($r('app.color.text_secondary'))
                          .backgroundColor($r('app.color.bg_input'))
                          .height(30)
                          .padding({ left: 12, right: 12 })
                          .borderRadius(15)
                          .maxLines(1)
                          .onClick((): void => {
                            this.granularityKey = item;
                            this.load();
                          })
                      }
                    }, (item: string) => item)
                  }
                }
                .scrollable(ScrollDirection.Horizontal)
                .scrollBar(BarState.Off)
                .width('100%')
                .margin({ top: 10 })

                Row() {
                  Blank()
                  Button(this.exportLabel())
                    .fontSize(12)
                    .height(30)
                    .borderRadius(15)
                    .backgroundColor($r('app.color.bg_input'))
                    .fontColor($r('app.color.brand'))
                    .enabled(!this.exporting)
                    .onClick((): void => {
                      this.exportExcel();
                    })
                }
                .width('100%')
                .margin({ top: 12 })

                if (this.hasData()) {
                  Column() {
                    Column({ space: 4 }) {
                      Text(this.totalText())
                        .fontSize(32)
                        .fontWeight(FontWeight.Bold)
                        .fontColor($r('app.color.brand'))
                        .maxLines(1)
                      Text('总 Token')
                        .fontSize(12)
                        .fontColor($r('app.color.text_tertiary'))
                      if (this.rangeText() !== '') {
                        Text(this.rangeText())
                          .fontSize(11)
                          .fontColor($r('app.color.text_tertiary'))
                          .maxLines(1)
                      }
                    }
                    .width('100%')
                    .padding({ top: 18, bottom: 6 })
                    .alignItems(HorizontalAlign.Center)

                    Flex({ wrap: FlexWrap.Wrap }) {
                      ForEach(this.metricCells(), (cell: UsageMetricCell) => {
                        Column({ space: 4 }) {
                          Text(cell.label)
                            .fontSize(11)
                            .fontColor($r('app.color.text_tertiary'))
                          Text(cell.value)
                            .fontSize(15)
                            .fontWeight(FontWeight.Medium)
                            .fontColor($r('app.color.text_primary'))
                            .maxLines(1)
                        }
                        .width('50%')
                        .alignItems(HorizontalAlign.Start)
                        .padding({ top: 10, bottom: 2 })
                      }, (cell: UsageMetricCell) => cell.label)
                    }
                    .width('100%')
                    .padding({ left: 16, right: 16, bottom: 8 })
                  }
                  .width('100%')
                  .borderRadius(16)
                  .backgroundColor($r('app.color.bg_card'))
                  .border({ width: 1, color: $r('app.color.card_stroke') })
                  .margin({ top: 14 })

                  Text(this.granularityLabel(this.granularityKey))
                    .fontSize(14)
                    .fontWeight(FontWeight.Bold)
                    .fontColor($r('app.color.text_primary'))
                    .width('100%')
                    .textAlign(TextAlign.Start)
                    .margin({ top: 18, bottom: 4 })

                  ForEach(this.buckets(), (bucket: UsageBucketModel) => {
                    Column({ space: 6 }) {
                      Row() {
                        Text(this.bucketLabel(bucket))
                          .fontSize(13)
                          .fontWeight(FontWeight.Medium)
                          .fontColor($r('app.color.text_primary'))
                          .maxLines(1)
                          .textOverflow({ overflow: TextOverflow.Ellipsis })
                          .layoutWeight(1)
                        Text(bucket.totalTokens.toLocaleString())
                          .fontSize(13)
                          .fontWeight(FontWeight.Medium)
                          .fontColor($r('app.color.brand'))
                          .maxLines(1)
                      }
                      .width('100%')

                      Row() {
                        Row()
                          .width(this.bucketBarWidth(bucket))
                          .height(6)
                          .borderRadius(3)
                          .backgroundColor($r('app.color.brand'))
                      }
                      .width('100%')
                      .height(6)
                      .borderRadius(3)
                      .backgroundColor($r('app.color.bg_input'))

                      Text(this.bucketSubText(bucket))
                        .fontSize(11)
                        .fontColor($r('app.color.text_tertiary'))
                        .maxLines(1)
                        .width('100%')
                    }
                    .width('100%')
                    .padding(12)
                    .borderRadius(14)
                    .backgroundColor($r('app.color.bg_card'))
                    .border({ width: 1, color: $r('app.color.card_stroke') })
                    .margin({ top: 8 })
                  }, (bucket: UsageBucketModel) => `${bucket.key}-${bucket.totalTokens}`)
                } else {
                  EmptyView({
                    title: '该时段暂无用量',
                    subtitle: '发起对话后这里会展示统计',
                    icon: $r('sys.symbol.timer')
                  })
                  .margin({ top: 16 })
                }
              }
              .width('100%')
              .constraintSize({ minHeight: '100%' })
              .padding({ left: 14, right: 14, top: 4, bottom: 30 })
            }
            .scrollBar(BarState.Off)
            .align(Alignment.Top)
            .width('100%')
            .height('100%')
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
    }
    .hideTitleBar(true)
    .backgroundColor($r('app.color.bg_page'))
    .onReady((ctx: NavDestinationContext): void => {
      this.onNavReady(ctx);
    })
  }
}
