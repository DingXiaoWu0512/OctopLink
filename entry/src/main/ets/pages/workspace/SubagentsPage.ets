import {
  InstalledSubagentModel,
  SubagentCatalogItemModel,
  SubagentDivisionModel
} from '../../model/SkillModels';
import { SubagentService } from '../../service/SubagentService';
import { OctopApiError } from '../../net/HttpClient';
import { SessionStore } from '../../store/SessionStore';
import { EmptyView } from '../../components/EmptyView';
import { ErrorRetry } from '../../components/ErrorRetry';
import { PageHeader } from '../../components/PageHeader';

/** 子代理：目录浏览/搜索/分区筛选 + 安装；已安装列表（当前专家） */
@Component
export struct SubagentsPage {
  @State divisions: Array<SubagentDivisionModel> = [];
  @State catalog: Array<SubagentCatalogItemModel> = [];
  @State installed: Array<InstalledSubagentModel> = [];
  @State loading: boolean = true;
  @State refreshing: boolean = false;
  @State errorMsg: string = '';
  @State operating: boolean = false;
  @State activeTab: number = 0;
  @State selectedDivision: string = '';
  @State searchText: string = '';
  private agentId: string = '';
  private pathStack: NavPathStack | null = null;

  private onNavReady(ctx: NavDestinationContext): void {
    this.pathStack = ctx.pathStack;
    this.agentId = AppStorage.get<string>(SessionStore.KEY_AGENT_ID) ?? '';
    this.load();
  }

  private async load(): Promise<void> {
    this.loading = true;
    this.errorMsg = '';
    try {
      this.divisions = await SubagentService.divisions();
      this.catalog = await SubagentService.catalog();
      await this.loadInstalled();
    } catch (e) {
      this.errorMsg = e instanceof OctopApiError ? e.message : '子代理目录加载失败';
    } finally {
      this.loading = false;
    }
  }

  private async loadInstalled(): Promise<void> {
    if (this.agentId === '') {
      this.installed = [];
      return;
    }
    try {
      this.installed = await SubagentService.listInstalled(this.agentId);
    } catch (e) {
      this.installed = [];
    }
  }

  private filteredCatalog(): Array<SubagentCatalogItemModel> {
    const result: Array<SubagentCatalogItemModel> = [];
    const q: string = this.searchText.trim().toLowerCase();
    for (const item of this.catalog) {
      if (this.selectedDivision !== '' && item.division !== this.selectedDivision) {
        continue;
      }
      if (q !== '' && item.displayTitle().toLowerCase().indexOf(q) < 0 &&
        item.displayDesc().toLowerCase().indexOf(q) < 0) {
        continue;
      }
      result.push(item);
    }
    return result;
  }

  private divisionLabel(item: SubagentCatalogItemModel): string {
    for (const div of this.divisions) {
      if (div.id === item.division) {
        return div.label;
      }
    }
    return item.division;
  }

  private emojiOf(item: SubagentCatalogItemModel): string {
    if (item.emoji !== '') {
      return item.emoji;
    }
    return '🤖';
  }

  private tabFontColor(index: number): ResourceColor {
    if (this.activeTab === index) {
      return $r('app.color.bg_card');
    }
    return $r('app.color.text_secondary');
  }

  private tabBgColor(index: number): ResourceColor {
    if (this.activeTab === index) {
      return $r('app.color.brand');
    }
    return $r('app.color.bg_input');
  }

  private chipFontColor(divisionId: string): ResourceColor {
    if (this.selectedDivision === divisionId) {
      return $r('app.color.bg_card');
    }
    return $r('app.color.text_secondary');
  }

  private chipBgColor(divisionId: string): ResourceColor {
    if (this.selectedDivision === divisionId) {
      return $r('app.color.brand');
    }
    return $r('app.color.bg_input');
  }

  private confirmInstall(item: SubagentCatalogItemModel): void {
    if (this.agentId === '') {
      this.getUIContext().getPromptAction().showToast({ message: '请先选择专家' });
      return;
    }
    this.getUIContext().showAlertDialog({
      title: '安装子代理',
      message: `确定安装「${item.displayTitle()}」吗？`,
      primaryButton: {
        value: $r('app.string.common_cancel'),
        action: (): void => {
        }
      },
      secondaryButton: {
        value: $r('app.string.common_confirm'),
        action: (): void => {
          this.installSubagent(item);
        }
      },
      alignment: DialogAlignment.Bottom
    });
  }

  private async installSubagent(item: SubagentCatalogItemModel): Promise<void> {
    if (this.operating) {
      return;
    }
    this.operating = true;
    try {
      await SubagentService.install(this.agentId, item.slug);
      this.getUIContext().getPromptAction().showToast({ message: '已安装' });
      await this.loadInstalled();
    } catch (e) {
      const message: string = e instanceof OctopApiError ? e.message : '安装失败';
      this.getUIContext().getPromptAction().showToast({ message });
    } finally {
      this.operating = false;
    }
  }

  build() {
    NavDestination() {
      Column() {
        PageHeader({ title: '子代理' })

        Row({ space: 8 }) {
          Text('目录')
            .fontSize(13)
            .fontWeight(FontWeight.Medium)
            .fontColor(this.tabFontColor(0))
            .height(30)
            .layoutWeight(1)
            .textAlign(TextAlign.Center)
            .borderRadius(15)
            .backgroundColor(this.tabBgColor(0))
            .onClick((): void => {
              this.activeTab = 0;
            })
          Text('已安装')
            .fontSize(13)
            .fontWeight(FontWeight.Medium)
            .fontColor(this.tabFontColor(1))
            .height(30)
            .layoutWeight(1)
            .textAlign(TextAlign.Center)
            .borderRadius(15)
            .backgroundColor(this.tabBgColor(1))
            .onClick((): void => {
              this.activeTab = 1;
              this.loadInstalled();
            })
        }
        .width('100%')
        .padding({ left: 14, right: 14, top: 4, bottom: 10 })

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
        } else if (this.activeTab === 0) {
          Column() {
            TextInput({
              text: this.searchText,
              placeholder: '搜索子代理'
            })
              .fontSize(13)
              .height(38)
              .backgroundColor($r('app.color.bg_input'))
              .borderRadius(12)
              .width('100%')
              .onChange((value: string): void => {
                this.searchText = value;
              })

            Scroll() {
              Row({ space: 8 }) {
                Text('全部')
                  .fontSize(12)
                  .fontColor(this.chipFontColor(''))
                  .backgroundColor(this.chipBgColor(''))
                  .height(28)
                  .padding({ left: 12, right: 12 })
                  .borderRadius(14)
                  .onClick((): void => {
                    this.selectedDivision = '';
                  })
                ForEach(this.divisions, (div: SubagentDivisionModel) => {
                  Text(div.label)
                    .fontSize(12)
                    .fontColor(this.chipFontColor(div.id))
                    .backgroundColor(this.chipBgColor(div.id))
                    .height(28)
                    .padding({ left: 12, right: 12 })
                    .borderRadius(14)
                    .maxLines(1)
                    .onClick((): void => {
                      this.selectedDivision = div.id;
                    })
                }, (div: SubagentDivisionModel) => div.id)
              }
            }
            .scrollable(ScrollDirection.Horizontal)
            .scrollBar(BarState.Off)
            .width('100%')
            .margin({ top: 10 })

            if (this.filteredCatalog().length === 0) {
              Column() {
                EmptyView({
                  title: '暂无子代理',
                  subtitle: '换个关键词或分区试试',
                  icon: $r('sys.symbol.robot')
                })
              }
              .layoutWeight(1)
              .width('100%')
              .justifyContent(FlexAlign.Center)
            } else {
              Refresh({ refreshing: $$this.refreshing }) {
                List({ space: 12 }) {
                  ForEach(this.filteredCatalog(), (item: SubagentCatalogItemModel) => {
                    ListItem() {
                      Row({ space: 12 }) {
                        Column() {
                          Text(this.emojiOf(item))
                            .fontSize(24)
                        }
                        .width(46)
                        .height(46)
                        .borderRadius(14)
                        .backgroundColor($r('app.color.bg_input'))
                        .justifyContent(FlexAlign.Center)

                        Column({ space: 5 }) {
                          Row() {
                            Text(item.displayTitle())
                              .fontSize(15)
                              .fontWeight(FontWeight.Medium)
                              .fontColor($r('app.color.text_primary'))
                              .maxLines(1)
                              .textOverflow({ overflow: TextOverflow.Ellipsis })
                              .layoutWeight(1)
                            Button('安装')
                              .fontSize(12)
                              .height(28)
                              .padding({ left: 14, right: 14 })
                              .borderRadius(14)
                              .backgroundColor($r('app.color.brand'))
                              .fontColor($r('app.color.bg_card'))
                              .onClick((): void => {
                                this.confirmInstall(item);
                              })
                          }
                          .width('100%')

                          Text(item.displayDesc())
                            .fontSize(12)
                            .fontColor($r('app.color.text_secondary'))
                            .maxLines(2)
                            .textOverflow({ overflow: TextOverflow.Ellipsis })
                            .width('100%')
                            .lineHeight(17)

                          Row({ space: 5 }) {
                            Column()
                              .width(8)
                              .height(8)
                              .borderRadius(4)
                              .backgroundColor(item.color)
                            Text(this.divisionLabel(item))
                              .fontSize(11)
                              .fontColor($r('app.color.text_tertiary'))
                              .maxLines(1)
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
                    }
                  }, (item: SubagentCatalogItemModel) => item.slug)
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
          .layoutWeight(1)
          .width('100%')
          .padding({ left: 14, right: 14 })
        } else {
          if (this.agentId === '') {
            Column() {
              EmptyView({
                title: '请先选择专家',
                subtitle: '在专家页选择后再安装子代理',
                icon: $r('sys.symbol.person')
              })
            }
            .layoutWeight(1)
            .width('100%')
            .justifyContent(FlexAlign.Center)
          } else if (this.installed.length === 0) {
            Column() {
              EmptyView({
                title: '暂未安装子代理',
                subtitle: '去目录页安装',
                icon: $r('sys.symbol.robot')
              })
            }
            .layoutWeight(1)
            .width('100%')
            .justifyContent(FlexAlign.Center)
          } else {
            Refresh({ refreshing: $$this.refreshing }) {
              List({ space: 12 }) {
                ForEach(this.installed, (sub: InstalledSubagentModel) => {
                  ListItem() {
                    Row({ space: 12 }) {
                      Column() {
                        Column()
                          .width(10)
                          .height(10)
                          .borderRadius(5)
                          .backgroundColor(sub.color)
                      }
                      .width(42)
                      .height(42)
                      .borderRadius(13)
                      .backgroundColor($r('app.color.bg_input'))
                      .justifyContent(FlexAlign.Center)

                      Column({ space: 5 }) {
                        Text(sub.name)
                          .fontSize(15)
                          .fontWeight(FontWeight.Medium)
                          .fontColor($r('app.color.text_primary'))
                          .maxLines(1)
                          .textOverflow({ overflow: TextOverflow.Ellipsis })
                          .width('100%')
                        Text(sub.description)
                          .fontSize(12)
                          .fontColor($r('app.color.text_secondary'))
                          .maxLines(2)
                          .textOverflow({ overflow: TextOverflow.Ellipsis })
                          .width('100%')
                          .lineHeight(17)
                        Text(sub.path)
                          .fontSize(11)
                          .fontColor($r('app.color.text_tertiary'))
                          .maxLines(1)
                          .textOverflow({ overflow: TextOverflow.Ellipsis })
                          .width('100%')
                      }
                      .layoutWeight(1)
                      .alignItems(HorizontalAlign.Start)
                    }
                    .width('100%')
                    .padding({ left: 14, right: 14, top: 14, bottom: 14 })
                    .borderRadius(16)
                    .backgroundColor($r('app.color.bg_card'))
                  }
                }, (sub: InstalledSubagentModel) => sub.slug)
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
