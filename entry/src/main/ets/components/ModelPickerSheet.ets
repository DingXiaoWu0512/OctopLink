import { BusinessError } from '@kit.BasicServicesKit';
import { ResolvedModelEntry } from '../model/WorkspaceModels';
import { ProviderService } from '../service/ProviderService';

/** 模型选择器分组（按 provider 聚合） */
class ModelPickerGroup {
  providerName: string;
  entries: Array<ResolvedModelEntry>;

  constructor(providerName: string, entries: Array<ResolvedModelEntry>) {
    this.providerName = providerName;
    this.entries = entries;
  }
}

/**
 * 模型选择面板（作为 bindSheet 内容使用）：
 * - 数据源 GET /api/providers/resolved，按 provider 分组展示，支持关键字过滤
 * - 选中回调 ref 为 "provider/model"（threads model_ref / agent default_model 形式），
 *   空串代表"自动"（跟随会话与全局默认设置）
 */
@Component
export struct ModelPickerSheet {
  /** 选中回调：ref = "provider/model" 或 ''（自动）；label 为展示名 */
  onPick: (ref: string, label: string) => void = (ref: string, label: string) => {
  };
  /** 是否提供"自动"选项 */
  allowAuto: boolean = true;

  @State groups: Array<ModelPickerGroup> = [];
  @State keyword: string = '';
  @State loading: boolean = true;
  @State loadError: string = '';

  aboutToAppear(): void {
    this.loadModels();
  }

  private loadModels(): void {
    this.loading = true;
    this.loadError = '';
    ProviderService.resolvedModels().then((list: Array<ResolvedModelEntry>) => {
      this.loading = false;
      this.rebuildGroups(list);
    }).catch((error: BusinessError) => {
      this.loading = false;
      this.loadError = error.message;
    });
  }

  /** 按关键字过滤并按 provider 分组 */
  private rebuildGroups(list: Array<ResolvedModelEntry>): void {
    const kw: string = this.keyword.trim().toLowerCase();
    const result: Array<ModelPickerGroup> = [];
    for (const entry of list) {
      const hit: boolean = kw === '' || entry.displayName().toLowerCase().includes(kw) ||
        entry.model.toLowerCase().includes(kw) || entry.providerName.toLowerCase().includes(kw);
      if (!hit) {
        continue;
      }
      let group: ModelPickerGroup | null = null;
      for (const existing of result) {
        if (existing.providerName === entry.providerName) {
          group = existing;
          break;
        }
      }
      if (group === null) {
        group = new ModelPickerGroup(entry.providerName, []);
        result.push(group);
      }
      group.entries.push(entry);
    }
    this.groups = result;
  }

  build() {
    Column({ space: 10 }) {
      Row() {
        Text('选择模型')
          .fontSize(16)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.text_primary'))
        Blank()
        if (this.loadError !== '') {
          Text('重试')
            .fontSize(13)
            .fontColor($r('app.color.brand'))
            .onClick((): void => {
              this.loadModels();
            })
        }
      }
      .width('100%')

      TextInput({ placeholder: '搜索模型或厂商', text: this.keyword })
        .fontSize(14)
        .height(40)
        .padding({ left: 12, right: 12 })
        .backgroundColor($r('app.color.bg_input'))
        .borderRadius(12)
        .onChange((value: string) => {
          this.keyword = value;
          this.loadModels();
        })

      if (this.loading) {
        Column({ space: 8 }) {
          LoadingProgress()
            .width(28)
            .height(28)
            .color($r('app.color.brand'))
          Text('加载模型列表…')
            .fontSize(13)
            .fontColor($r('app.color.text_tertiary'))
        }
        .layoutWeight(1)
        .width('100%')
        .justifyContent(FlexAlign.Center)
      } else if (this.loadError !== '') {
        Column({ space: 10 }) {
          Text(this.loadError)
            .fontSize(13)
            .fontColor($r('app.color.danger'))
            .textAlign(TextAlign.Center)
          Button('重试')
            .fontSize(13)
            .height(34)
            .backgroundColor($r('app.color.brand'))
            .onClick((): void => {
              this.loadModels();
            })
        }
        .layoutWeight(1)
        .width('100%')
        .justifyContent(FlexAlign.Center)
      } else {
        List({ space: 6 }) {
          if (this.allowAuto) {
            ListItem() {
              Row({ space: 10 }) {
                Column()
                  .width(8)
                  .height(8)
                  .borderRadius(4)
                  .backgroundColor($r('app.color.brand'))
                Column({ space: 2 }) {
                  Text('自动')
                    .fontSize(14)
                    .fontWeight(FontWeight.Medium)
                    .fontColor($r('app.color.text_primary'))
                  Text('跟随会话与全局默认设置')
                    .fontSize(11)
                    .fontColor($r('app.color.text_tertiary'))
                }
                .layoutWeight(1)
                .alignItems(HorizontalAlign.Start)
              }
              .width('100%')
              .padding({ left: 12, right: 12, top: 11, bottom: 11 })
              .borderRadius(12)
              .backgroundColor($r('app.color.bg_card'))
              .onClick((): void => {
                this.onPick('', '自动');
              })
            }
          }
          ForEach(this.groups, (group: ModelPickerGroup) => {
            ListItem() {
              Column({ space: 6 }) {
                Text(group.providerName)
                  .fontSize(11)
                  .fontColor($r('app.color.text_tertiary'))
                  .width('100%')
                ForEach(group.entries, (entry: ResolvedModelEntry) => {
                  Row({ space: 10 }) {
                    Column({ space: 2 }) {
                      Text(entry.displayName())
                        .fontSize(14)
                        .fontColor($r('app.color.text_primary'))
                        .maxLines(1)
                      Text(entry.model)
                        .fontSize(11)
                        .fontColor($r('app.color.text_tertiary'))
                        .maxLines(1)
                    }
                    .layoutWeight(1)
                    .alignItems(HorizontalAlign.Start)
                    if (entry.reasoning) {
                      Text('推理')
                        .fontSize(10)
                        .fontColor($r('app.color.brand'))
                        .padding({ left: 6, right: 6, top: 2, bottom: 2 })
                        .borderRadius(6)
                        .backgroundColor($r('app.color.brand_light'))
                    }
                  }
                  .width('100%')
                  .padding({ left: 12, right: 12, top: 11, bottom: 11 })
                  .borderRadius(12)
                  .backgroundColor($r('app.color.bg_card'))
                  .onClick((): void => {
                    this.onPick(entry.ref(), entry.displayName());
                  })
                }, (entry: ResolvedModelEntry) => entry.ref())
              }
              .width('100%')
            }
          }, (group: ModelPickerGroup) => `${group.providerName}_${group.entries.length}`)
        }
        .layoutWeight(1)
        .width('100%')
      }
    }
    .width('100%')
    .height('100%')
    .padding({ left: 16, right: 16, top: 14, bottom: 16 })
  }
}
