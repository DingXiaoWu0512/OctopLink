import { BuiltinExpertModel, HubExpertModel, HubExpertListModel } from '../../model/ExpertModels';
import { AgentService } from '../../service/AgentService';
import { OctopApiError } from '../../net/HttpClient';
import { SessionStore } from '../../store/SessionStore';
import { EmptyView } from '../../components/EmptyView';
import { ErrorRetry } from '../../components/ErrorRetry';
import { PageHeader } from '../../components/PageHeader';

@Component
export struct ExpertCreatePage {
  @State segIndex: number = 0;
  @State loading: boolean = false;
  @State errorMsg: string = '';
  @State builtinExperts: Array<BuiltinExpertModel> = [];
  @State hubItems: Array<HubExpertModel> = [];
  @State hubScenes: Array<string> = [];
  @State selectedScene: string = '';
  @State searchQuery: string = '';
  @State installing: boolean = false;
  private pathStack: NavPathStack | null = null;

  aboutToAppear(): void {
    this.loadBuiltin();
  }

  private popPage(): void {
    if (this.pathStack !== null) {
      this.pathStack.pop();
    }
  }

  private async loadBuiltin(): Promise<void> {
    this.loading = true;
    this.errorMsg = '';
    try {
      this.builtinExperts = await AgentService.listBuiltinExperts();
    } catch (e) {
      this.errorMsg = e instanceof OctopApiError ? e.message : '模板列表加载失败';
    } finally {
      this.loading = false;
    }
  }

  private async loadHub(query: string, scene: string): Promise<void> {
    this.loading = true;
    this.errorMsg = '';
    try {
      const result: HubExpertListModel = await AgentService.listHubExperts(query, scene);
      this.hubItems = result.items;
      this.hubScenes = result.scenes;
    } catch (e) {
      this.errorMsg = e instanceof OctopApiError ? e.message : '专家市场加载失败';
    } finally {
      this.loading = false;
    }
  }

  private switchSegment(index: number): void {
    if (this.segIndex === index) {
      return;
    }
    this.segIndex = index;
    if (index === 1 && this.hubItems.length === 0 && this.errorMsg === '') {
      this.loadHub(this.searchQuery, this.selectedScene);
    }
  }

  private doSearch(): void {
    this.loadHub(this.searchQuery.trim(), this.selectedScene);
  }

  private pickScene(scene: string): void {
    this.selectedScene = this.selectedScene === scene ? '' : scene;
    this.loadHub(this.searchQuery.trim(), this.selectedScene);
  }

  private async createFromBuiltin(expert: BuiltinExpertModel): Promise<void> {
    if (this.installing) {
      return;
    }
    this.installing = true;
    try {
      await AgentService.createFromBuiltinExpert(expert.id, expert.label);
      SessionStore.markAgentsDirty();
      this.getUIContext().getPromptAction().showToast({ message: `「${expert.label}」创建成功` });
      this.popPage();
    } catch (e) {
      const message: string = e instanceof OctopApiError ? e.message : '创建失败';
      this.getUIContext().getPromptAction().showToast({ message });
    } finally {
      this.installing = false;
    }
  }

  private async installHub(item: HubExpertModel): Promise<void> {
    if (this.installing) {
      return;
    }
    this.installing = true;
    try {
      await AgentService.installHubExpert(item.slug);
      SessionStore.markAgentsDirty();
      this.getUIContext().getPromptAction().showToast({ message: `「${item.label}」安装成功` });
      this.popPage();
    } catch (e) {
      const message: string = e instanceof OctopApiError ? e.message : '安装失败';
      this.getUIContext().getPromptAction().showToast({ message });
    } finally {
      this.installing = false;
    }
  }

  build() {
    NavDestination() {
      Column() {
        PageHeader({ title: '创建专家' })

        // 分段切换（胶囊轨道）
        Row({ space: 4 }) {
          Text('内置模板')
            .fontSize(14)
            .fontWeight(this.segIndex === 0 ? FontWeight.Bold : FontWeight.Normal)
            .fontColor(this.segIndex === 0 ? $r('app.color.text_on_brand') : $r('app.color.text_secondary'))
            .height(34)
            .padding({ left: 18, right: 18 })
            .borderRadius(17)
            .backgroundColor(this.segIndex === 0 ? $r('app.color.brand') : Color.Transparent)
            .onClick((): void => {
              this.switchSegment(0);
            })
          Text('专家市场')
            .fontSize(14)
            .fontWeight(this.segIndex === 1 ? FontWeight.Bold : FontWeight.Normal)
            .fontColor(this.segIndex === 1 ? $r('app.color.text_on_brand') : $r('app.color.text_secondary'))
            .height(34)
            .padding({ left: 18, right: 18 })
            .borderRadius(17)
            .backgroundColor(this.segIndex === 1 ? $r('app.color.brand') : Color.Transparent)
            .onClick((): void => {
              this.switchSegment(1);
            })
        }
        .padding(3)
        .borderRadius(20)
        .backgroundColor($r('app.color.bg_input'))
        .margin({ top: 10, bottom: 8 })

        if (this.segIndex === 1) {
          // 市场搜索与场景筛选
          Column({ space: 8 }) {
            Row({ space: 8 }) {
              TextInput({
                text: this.searchQuery,
                placeholder: '搜索市场专家'
              })
                .layoutWeight(1)
                .fontSize(14)
                .height(38)
                .backgroundColor($r('app.color.bg_input'))
                .onChange((value: string): void => {
                  this.searchQuery = value;
                })
                .onSubmit((enterKey: EnterKeyType): void => {
                  this.doSearch();
                })
              Button('搜索')
                .fontSize(13)
                .height(38)
                .backgroundColor($r('app.color.brand'))
                .fontColor($r('app.color.text_on_brand'))
                .onClick((): void => {
                  this.doSearch();
                })
            }
            .width('100%')
            if (this.hubScenes.length > 0) {
              Scroll() {
                Row({ space: 8 }) {
                  ForEach(this.hubScenes, (scene: string) => {
                    Text(scene)
                      .fontSize(12)
                      .fontColor(this.selectedScene === scene
                        ? $r('app.color.text_on_brand') : $r('app.color.text_secondary'))
                      .backgroundColor(this.selectedScene === scene
                        ? $r('app.color.brand') : $r('app.color.bg_input'))
                      .borderRadius(12)
                      .padding({ left: 12, right: 12, top: 5, bottom: 5 })
                      .onClick((): void => {
                        this.pickScene(scene);
                      })
                  }, (scene: string) => scene)
                }
              }
              .scrollable(ScrollDirection.Horizontal)
              .scrollBar(BarState.Off)
              .width('100%')
            }
          }
          .width('100%')
          .padding({ left: 16, right: 16, bottom: 8 })
        }

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
                if (this.segIndex === 0) {
                  this.loadBuiltin();
                } else {
                  this.loadHub(this.searchQuery.trim(), this.selectedScene);
                }
              }
            })
          }
          .layoutWeight(1)
          .width('100%')
          .justifyContent(FlexAlign.Center)
        } else if (this.segIndex === 0 && this.builtinExperts.length === 0) {
          Column() {
            EmptyView({ title: '暂无内置模板', subtitle: '请检查服务端版本' })
          }
          .layoutWeight(1)
          .width('100%')
          .justifyContent(FlexAlign.Center)
        } else if (this.segIndex === 1 && this.hubItems.length === 0) {
          Column() {
            EmptyView({ title: '没有找到市场专家', subtitle: '换个关键词试试' })
          }
          .layoutWeight(1)
          .width('100%')
          .justifyContent(FlexAlign.Center)
        } else if (this.segIndex === 0) {
          List({ space: 10 }) {
            ForEach(this.builtinExperts, (expert: BuiltinExpertModel) => {
              ListItem() {
                Row({ space: 12 }) {
                  Image($r('app.media.octop_logo'))
                    .width(44)
                    .height(44)
                    .borderRadius(22)
                    .backgroundColor($r('app.color.brand_light'))
                  Column({ space: 4 }) {
                    Text(expert.label)
                      .fontSize(16)
                      .fontWeight(FontWeight.Medium)
                      .fontColor($r('app.color.text_primary'))
                      .maxLines(1)
                      .textOverflow({ overflow: TextOverflow.Ellipsis })
                    if (expert.description !== '') {
                      Text(expert.description)
                        .fontSize(13)
                        .fontColor($r('app.color.text_secondary'))
                        .maxLines(2)
                        .textOverflow({ overflow: TextOverflow.Ellipsis })
                    }
                  }
                  .layoutWeight(1)
                  .alignItems(HorizontalAlign.Start)
                  Text('创建')
                    .fontSize(13)
                    .fontWeight(FontWeight.Medium)
                    .fontColor($r('app.color.text_on_brand'))
                    .linearGradient({
                      angle: 140,
                      colors: [[$r('app.color.brand_grad_start'), 0], [$r('app.color.brand_grad_end'), 1]]
                    })
                    .borderRadius(15)
                    .padding({ left: 16, right: 16, top: 7, bottom: 7 })
                    .shadow({ radius: 8, color: '#260A59F7', offsetY: 3 })
                }
                .width('100%')
                .padding(14)
                .borderRadius(16)
                .backgroundColor($r('app.color.bg_card'))
                .border({ width: 1, color: $r('app.color.card_stroke') })
                .shadow({ radius: 10, color: '#0A000000', offsetY: 3 })
                .onClick((): void => {
                  this.createFromBuiltin(expert);
                })
              }
            }, (expert: BuiltinExpertModel) => expert.id)
          }
          .width('100%')
          .layoutWeight(1)
          .padding({ left: 12, right: 12, top: 4, bottom: 20 })
          .scrollBar(BarState.Off)
        } else {
          List({ space: 10 }) {
            ForEach(this.hubItems, (item: HubExpertModel) => {
              ListItem() {
                Row({ space: 12 }) {
                  Image($r('app.media.octop_logo'))
                    .width(44)
                    .height(44)
                    .borderRadius(22)
                    .backgroundColor($r('app.color.brand_light'))
                  Column({ space: 4 }) {
                    Row({ space: 6 }) {
                      Text(item.label)
                        .fontSize(16)
                        .fontWeight(FontWeight.Medium)
                        .fontColor($r('app.color.text_primary'))
                        .maxLines(1)
                        .textOverflow({ overflow: TextOverflow.Ellipsis })
                      if (item.scene !== '') {
                        Text(item.scene)
                          .fontSize(11)
                          .fontColor($r('app.color.text_secondary'))
                          .backgroundColor($r('app.color.bg_input'))
                          .borderRadius(4)
                          .padding({ left: 6, right: 6, top: 1, bottom: 1 })
                      }
                    }
                    if (item.description !== '') {
                      Text(item.description)
                        .fontSize(13)
                        .fontColor($r('app.color.text_secondary'))
                        .maxLines(2)
                        .textOverflow({ overflow: TextOverflow.Ellipsis })
                    }
                    if (item.skillCount > 0) {
                      Text(`${item.skillCount} 项技能`)
                        .fontSize(12)
                        .fontColor($r('app.color.text_tertiary'))
                    }
                  }
                  .layoutWeight(1)
                  .alignItems(HorizontalAlign.Start)
                  Text('安装')
                    .fontSize(13)
                    .fontWeight(FontWeight.Medium)
                    .fontColor($r('app.color.text_on_brand'))
                    .linearGradient({
                      angle: 140,
                      colors: [[$r('app.color.brand_grad_start'), 0], [$r('app.color.brand_grad_end'), 1]]
                    })
                    .borderRadius(15)
                    .padding({ left: 16, right: 16, top: 7, bottom: 7 })
                    .shadow({ radius: 8, color: '#260A59F7', offsetY: 3 })
                }
                .width('100%')
                .padding(14)
                .borderRadius(16)
                .backgroundColor($r('app.color.bg_card'))
                .border({ width: 1, color: $r('app.color.card_stroke') })
                .shadow({ radius: 10, color: '#0A000000', offsetY: 3 })
                .onClick((): void => {
                  this.installHub(item);
                })
              }
            }, (item: HubExpertModel) => `${item.slug}_${item.id}`)
          }
          .width('100%')
          .layoutWeight(1)
          .padding({ left: 12, right: 12, top: 4, bottom: 20 })
          .scrollBar(BarState.Off)
        }
      }
      .width('100%')
      .height('100%')
    }
    .hideTitleBar(true)
    .backgroundColor($r('app.color.bg_page'))
    .onReady((ctx: NavDestinationContext): void => {
      this.pathStack = ctx.pathStack;
    })
  }
}
