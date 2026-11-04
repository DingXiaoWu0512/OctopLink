import {
  BuiltinExpertModel,
  ExpertDetailModel,
  HubExpertModel,
  HubExpertListModel,
  NameContentModel,
  PublishedExpertModel
} from '../../model/ExpertModels';
import { AgentService } from '../../service/AgentService';
import { OctopApiError } from '../../net/HttpClient';
import { SessionStore } from '../../store/SessionStore';
import { EmptyView } from '../../components/EmptyView';
import { ErrorRetry } from '../../components/ErrorRetry';
import { ModelPickerSheet } from '../../components/ModelPickerSheet';
import { PageHeader } from '../../components/PageHeader';
import { AgentAvatar } from '../../components/AgentAvatar';
import { UiMaterialKit } from '../../components/UiMaterialKit';

/** 分段定义 */
class CreateSegment {
  readonly label: string;
  readonly value: number;

  constructor(label: string, value: number) {
    this.label = label;
    this.value = value;
  }
}

/** MBTI 16 型人格选项 */
class MbtiOption {
  readonly code: string;

  constructor(code: string) {
    this.code = code;
  }
}

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
  @State publishedList: Array<PublishedExpertModel> = [];
  @State installing: boolean = false;
  @State detailOpen: boolean = false;
  @State detailLoading: boolean = false;
  @State detail: ExpertDetailModel | null = null;
  @State detailError: string = '';
  // 自定义表单
  @State customName: string = '';
  @State customDesc: string = '';
  @State customMbti: string = '';
  @State customModel: string = '';
  @State customWelcome: string = '';
  @State customPrompt: string = '';
  @State customShared: boolean = false;
  @State customCreating: boolean = false;
  @State modelSheetOpen: boolean = false;
  private pathStack: NavPathStack | null = null;
  private detailMode: number = 0; // 0=内置模板 1=市场
  private detailRef: string = '';
  private segments: Array<CreateSegment> = [
    new CreateSegment('内置模板', 0),
    new CreateSegment('市场', 1),
    new CreateSegment('已发布', 2),
    new CreateSegment('自定义', 3)
  ];
  private mbtiCodes: Array<MbtiOption> = [
    new MbtiOption('INTJ'), new MbtiOption('INTP'), new MbtiOption('ENTJ'), new MbtiOption('ENTP'),
    new MbtiOption('INFJ'), new MbtiOption('INFP'), new MbtiOption('ENFJ'), new MbtiOption('ENFP'),
    new MbtiOption('ISTJ'), new MbtiOption('ISFJ'), new MbtiOption('ESTJ'), new MbtiOption('ESFJ'),
    new MbtiOption('ISTP'), new MbtiOption('ISFP'), new MbtiOption('ESTP'), new MbtiOption('ESFP')
  ];

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

  private async loadPublished(): Promise<void> {
    this.loading = true;
    this.errorMsg = '';
    try {
      this.publishedList = await AgentService.publishedList();
    } catch (e) {
      this.errorMsg = e instanceof OctopApiError ? e.message : '已发布专家加载失败';
    } finally {
      this.loading = false;
    }
  }

  private switchSegment(index: number): void {
    if (this.segIndex === index) {
      return;
    }
    this.segIndex = index;
    if (index === 1 && this.hubItems.length === 0) {
      this.loadHub(this.searchQuery, this.selectedScene);
    } else if (index === 2 && this.publishedList.length === 0) {
      this.loadPublished();
    }
  }

  private doSearch(): void {
    this.loadHub(this.searchQuery.trim(), this.selectedScene);
  }

  private pickScene(scene: string): void {
    this.selectedScene = this.selectedScene === scene ? '' : scene;
    this.loadHub(this.searchQuery.trim(), this.selectedScene);
  }

  // ---- 详情 sheet ----

  private async openDetail(mode: number, ref: string): Promise<void> {
    this.detailMode = mode;
    this.detailRef = ref;
    this.detail = null;
    this.detailError = '';
    this.detailLoading = true;
    this.detailOpen = true;
    try {
      if (mode === 0) {
        this.detail = await AgentService.getExpertDetail(ref);
      } else {
        this.detail = await AgentService.getHubDetail(ref);
      }
    } catch (e) {
      this.detailError = e instanceof OctopApiError ? e.message : '详情加载失败';
    }
    this.detailLoading = false;
  }

  private async installFromDetail(): Promise<void> {
    if (this.installing || this.detail === null) {
      return;
    }
    this.installing = true;
    try {
      if (this.detailMode === 0) {
        await AgentService.createFromBuiltinExpert(this.detailRef, this.detail.label);
      } else {
        await AgentService.installHubExpert(this.detailRef);
      }
      SessionStore.markAgentsDirty();
      this.getUIContext().getPromptAction().showToast({ message: `「${this.detail.label}」创建成功` });
      this.detailOpen = false;
      this.popPage();
    } catch (e) {
      const message: string = e instanceof OctopApiError ? e.message : '创建失败';
      this.getUIContext().getPromptAction().showToast({ message });
    } finally {
      this.installing = false;
    }
  }

  private async installPublished(item: PublishedExpertModel): Promise<void> {
    if (this.installing) {
      return;
    }
    this.installing = true;
    try {
      await AgentService.installPublished(item.id, item.label);
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

  // ---- 自定义创建 ----

  private async createCustom(): Promise<void> {
    if (this.customCreating) {
      return;
    }
    const name: string = this.customName.trim();
    if (name === '') {
      this.getUIContext().getPromptAction().showToast({ message: '请填写专家名称' });
      return;
    }
    this.customCreating = true;
    try {
      const body: Record<string, Object> = {
        'name': name,
        'is_shared': this.customShared
      };
      if (this.customDesc.trim() !== '') {
        body['description'] = this.customDesc.trim();
      }
      if (this.customMbti !== '') {
        body['persona_mbti'] = this.customMbti;
      }
      if (this.customModel !== '') {
        body['default_model'] = this.customModel;
      }
      if (this.customWelcome.trim() !== '') {
        body['welcome_message'] = this.customWelcome.trim();
      }
      if (this.customPrompt.trim() !== '') {
        body['system_prompt'] = this.customPrompt.trim();
      }
      await AgentService.create(JSON.stringify(body));
      SessionStore.markAgentsDirty();
      this.getUIContext().getPromptAction().showToast({ message: '专家创建成功' });
      this.popPage();
    } catch (e) {
      const message: string = e instanceof OctopApiError ? e.message : '创建失败';
      this.getUIContext().getPromptAction().showToast({ message });
    } finally {
      this.customCreating = false;
    }
  }

  @Builder
  private segmentBuilder() {
    Row({ space: 4 }) {
      ForEach(this.segments, (segment: CreateSegment) => {
        Text(segment.label)
          .fontSize(13)
          .fontWeight(this.segIndex === segment.value ? FontWeight.Bold : FontWeight.Normal)
          .fontColor(this.segIndex === segment.value
            ? $r('app.color.text_on_brand') : $r('app.color.text_secondary'))
          .height(32)
          .padding({ left: 14, right: 14 })
          .borderRadius(16)
          .backgroundColor(this.segIndex === segment.value ? $r('app.color.brand') : Color.Transparent)
          .onClick((): void => {
            this.switchSegment(segment.value);
          })
      }, (segment: CreateSegment) => `${segment.value}_${this.segIndex === segment.value}`)
    }
    .padding(3)
    .borderRadius(19)
    .backgroundColor($r('app.color.bg_input'))
    .margin({ top: 10, bottom: 8 })
  }

  @Builder
  private detailSheetBuilder() {
    Column({ space: 12 }) {
      if (this.detailLoading) {
        LoadingProgress()
          .width(36)
          .height(36)
          .color($r('app.color.brand'))
          .margin({ top: 40, bottom: 40 })
      } else if (this.detailError !== '') {
        Text(this.detailError)
          .fontSize(14)
          .fontColor($r('app.color.danger'))
          .padding({ top: 40, bottom: 40 })
      } else if (this.detail !== null) {
        Text(this.detail.label)
          .fontSize(18)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.text_primary'))
          .width('100%')
        if (this.detail.description !== '') {
          Text(this.detail.description)
            .fontSize(13)
            .fontColor($r('app.color.text_secondary'))
            .width('100%')
        }
        if (this.detail.welcomeMessage !== '') {
          Column({ space: 4 }) {
            Text('欢迎语')
              .fontSize(12)
              .fontColor($r('app.color.text_tertiary'))
            Text(this.detail.welcomeMessage)
              .fontSize(13)
              .fontColor($r('app.color.text_secondary'))
          }
          .width('100%')
          .alignItems(HorizontalAlign.Start)
        }
        if (this.detail.quickPrompts.length > 0) {
          Column({ space: 4 }) {
            Text('快捷提问')
              .fontSize(12)
              .fontColor($r('app.color.text_tertiary'))
            Flex({ wrap: FlexWrap.Wrap }) {
              ForEach(this.detail.quickPrompts, (prompt: string) => {
                Text(prompt)
                  .fontSize(11)
                  .fontColor($r('app.color.text_secondary'))
                  .backgroundColor($r('app.color.bg_input'))
                  .borderRadius(10)
                  .padding({ left: 10, right: 10, top: 4, bottom: 4 })
                  .margin({ right: 6, bottom: 6 })
              }, (prompt: string) => prompt)
            }
            .width('100%')
          }
          .width('100%')
          .alignItems(HorizontalAlign.Start)
        }
        if (this.detail.taskExamples.length > 0) {
          Column({ space: 4 }) {
            Text('任务示例')
              .fontSize(12)
              .fontColor($r('app.color.text_tertiary'))
            ForEach(this.detail.taskExamples, (example: string) => {
              Text(`· ${example}`)
                .fontSize(12)
                .fontColor($r('app.color.text_secondary'))
                .width('100%')
            }, (example: string) => example)
          }
          .width('100%')
          .alignItems(HorizontalAlign.Start)
        }
        if (this.detail.fileContents.length > 0) {
          Column({ space: 4 }) {
            Text('模板文件')
              .fontSize(12)
              .fontColor($r('app.color.text_tertiary'))
            ForEach(this.detail.fileContents, (file: NameContentModel) => {
              Column({ space: 2 }) {
                Text(file.name)
                  .fontSize(12)
                  .fontWeight(FontWeight.Medium)
                  .fontColor($r('app.color.text_primary'))
                Text(file.content)
                  .fontSize(11)
                  .fontColor($r('app.color.text_secondary'))
                  .maxLines(4)
                  .textOverflow({ overflow: TextOverflow.Ellipsis })
                  .width('100%')
              }
              .width('100%')
              .alignItems(HorizontalAlign.Start)
              .padding(10)
              .borderRadius(10)
              .backgroundColor($r('app.color.bg_input'))
            }, (file: NameContentModel) => file.name)
          }
          .width('100%')
          .alignItems(HorizontalAlign.Start)
        }
        Button(this.installing ? '创建中…' : (this.detailMode === 0 ? '用此模板创建' : '安装该专家'))
          .fontSize(15)
          .fontWeight(FontWeight.Bold)
          .height(44)
          .width('100%')
          .borderRadius(22)
          .backgroundColor($r('app.color.brand'))
          .fontColor($r('app.color.text_on_brand'))
          .enabled(!this.installing)
          .margin({ top: 6 })
          .onClick((): void => {
            this.installFromDetail();
          })
      }
    }
    .padding({ left: 18, right: 18, top: 18, bottom: 30 })
    .width('100%')
  }

  @Builder
  private modelSheetBuilder() {
    ModelPickerSheet({
      allowAuto: true,
      onPick: (ref: string, label: string): void => {
        this.customModel = ref;
        this.modelSheetOpen = false;
      }
    })
  }

  build() {
    NavDestination() {
      Column() {
        PageHeader({ title: '创建专家' })

        this.segmentBuilder()

        if (this.segIndex === 1) {
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
                } else if (this.segIndex === 1) {
                  this.loadHub(this.searchQuery.trim(), this.selectedScene);
                } else if (this.segIndex === 2) {
                  this.loadPublished();
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
        } else if (this.segIndex === 2 && this.publishedList.length === 0) {
          Column() {
            EmptyView({ title: '暂无已发布专家', subtitle: '其他用户发布的专家会出现在这里' })
          }
          .layoutWeight(1)
          .width('100%')
          .justifyContent(FlexAlign.Center)
        } else if (this.segIndex === 0) {
          List({ space: 10 }) {
            ForEach(this.builtinExperts, (expert: BuiltinExpertModel) => {
              ListItem() {
                Row({ space: 12 }) {
                  AgentAvatar({ iconUrl: expert.iconUrl, avatarSize: 44 })
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
                  Text('查看')
                    .fontSize(13)
                    .fontWeight(FontWeight.Medium)
                    .fontColor($r('app.color.brand'))
                    .backgroundColor($r('app.color.brand_light'))
                    .borderRadius(15)
                    .padding({ left: 16, right: 16, top: 7, bottom: 7 })
                }
                .width('100%')
                .padding(14)
                .borderRadius(16)
                .backgroundColor($r('app.color.bg_card'))
                .border({ width: 1, color: $r('app.color.card_stroke') })
                .shadow({ radius: 10, color: '#0A000000', offsetY: 3 })
                .onClick((): void => {
                  this.openDetail(0, expert.id);
                })
              }
            }, (expert: BuiltinExpertModel) => expert.id)
          }
          .width('100%')
          .layoutWeight(1)
          .padding({ left: 12, right: 12, top: 4, bottom: 20 })
          .scrollBar(BarState.Off)
        } else if (this.segIndex === 1) {
          List({ space: 10 }) {
            ForEach(this.hubItems, (item: HubExpertModel) => {
              ListItem() {
                Row({ space: 12 }) {
                  AgentAvatar({ iconUrl: item.iconUrl, avatarSize: 44 })
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
                  Text('查看')
                    .fontSize(13)
                    .fontWeight(FontWeight.Medium)
                    .fontColor($r('app.color.brand'))
                    .backgroundColor($r('app.color.brand_light'))
                    .borderRadius(15)
                    .padding({ left: 16, right: 16, top: 7, bottom: 7 })
                }
                .width('100%')
                .padding(14)
                .borderRadius(16)
                .backgroundColor($r('app.color.bg_card'))
                .border({ width: 1, color: $r('app.color.card_stroke') })
                .shadow({ radius: 10, color: '#0A000000', offsetY: 3 })
                .onClick((): void => {
                  this.openDetail(1, item.slug);
                })
              }
            }, (item: HubExpertModel) => `${item.slug}_${item.id}`)
          }
          .width('100%')
          .layoutWeight(1)
          .padding({ left: 12, right: 12, top: 4, bottom: 20 })
          .scrollBar(BarState.Off)
        } else if (this.segIndex === 2) {
          List({ space: 10 }) {
            ForEach(this.publishedList, (item: PublishedExpertModel) => {
              ListItem() {
                Row({ space: 12 }) {
                  AgentAvatar({ iconUrl: item.iconUrl, avatarSize: 44 })
                  Column({ space: 4 }) {
                    Text(item.label)
                      .fontSize(16)
                      .fontWeight(FontWeight.Medium)
                      .fontColor($r('app.color.text_primary'))
                      .maxLines(1)
                      .textOverflow({ overflow: TextOverflow.Ellipsis })
                    if (item.description !== '') {
                      Text(item.description)
                        .fontSize(13)
                        .fontColor($r('app.color.text_secondary'))
                        .maxLines(2)
                        .textOverflow({ overflow: TextOverflow.Ellipsis })
                    }
                    if (item.ownerUsername !== '') {
                      Text(`@${item.ownerUsername} 发布`)
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
                  this.installPublished(item);
                })
              }
            }, (item: PublishedExpertModel) => item.id)
          }
          .width('100%')
          .layoutWeight(1)
          .padding({ left: 12, right: 12, top: 4, bottom: 20 })
          .scrollBar(BarState.Off)
        } else {
          // 自定义创建表单
          Scroll() {
            Column({ space: 12 }) {
              Column({ space: 6 }) {
                Text('名称 *')
                  .fontSize(13)
                  .fontColor($r('app.color.text_secondary'))
                TextInput({ text: this.customName, placeholder: '专家名称' })
                  .fontSize(14)
                  .height(42)
                  .backgroundColor($r('app.color.bg_input'))
                  .borderRadius(12)
                  .onChange((value: string): void => {
                    this.customName = value;
                  })
              }
              .width('100%')
              .alignItems(HorizontalAlign.Start)
              Column({ space: 6 }) {
                Text('描述')
                  .fontSize(13)
                  .fontColor($r('app.color.text_secondary'))
                TextArea({ text: this.customDesc, placeholder: '一句话介绍这位专家' })
                  .fontSize(14)
                  .height(64)
                  .backgroundColor($r('app.color.bg_input'))
                  .borderRadius(12)
                  .onChange((value: string): void => {
                    this.customDesc = value;
                  })
              }
              .width('100%')
              .alignItems(HorizontalAlign.Start)
              Column({ space: 6 }) {
                Text('人格 MBTI')
                  .fontSize(13)
                  .fontColor($r('app.color.text_secondary'))
                Select(this.mbtiCodes.map((option: MbtiOption): SelectOption => {
                  return { value: option.code };
                }))
                  .selected(this.mbtiIndex())
                  .value(this.customMbti === '' ? '不设置' : this.customMbti)
                  .font({ size: 14 })
                  .fontColor($r('app.color.text_primary'))
                  .selectedOptionFont({ size: 14 })
                  .optionFont({ size: 14 })
                  .backgroundColor(Color.Transparent)
                  .borderRadius(12)
                  .width('100%')
                  .systemMaterial(UiMaterialKit.button())
                  .menuSystemMaterial(UiMaterialKit.sheet())
                  .onSelect((index: number, text: string): void => {
                    this.customMbti = text;
                  })
              }
              .width('100%')
              .alignItems(HorizontalAlign.Start)
              Column({ space: 6 }) {
                Text('默认模型')
                  .fontSize(13)
                  .fontColor($r('app.color.text_secondary'))
                Row({ space: 8 }) {
                  Text(this.customModel === '' ? '自动（未指定）' : this.customModel)
                    .fontSize(14)
                    .fontColor(this.customModel === ''
                      ? $r('app.color.text_tertiary') : $r('app.color.text_primary'))
                    .maxLines(1)
                    .textOverflow({ overflow: TextOverflow.Ellipsis })
                    .layoutWeight(1)
                  SymbolGlyph($r('sys.symbol.chevron_right'))
                    .fontSize(14)
                    .fontColor([$r('app.color.text_tertiary')])
                }
                .width('100%')
                .height(42)
                .padding({ left: 12, right: 12 })
                .backgroundColor($r('app.color.bg_input'))
                .borderRadius(12)
                .onClick((): void => {
                  this.modelSheetOpen = true;
                })
                .bindSheet($$this.modelSheetOpen, this.modelSheetBuilder, {
                  systemMaterial: UiMaterialKit.sheet(),
                  detents: [SheetSize.MEDIUM, SheetSize.LARGE],
                  showClose: true
                })
              }
              .width('100%')
              .alignItems(HorizontalAlign.Start)
              Column({ space: 6 }) {
                Text('欢迎语')
                  .fontSize(13)
                  .fontColor($r('app.color.text_secondary'))
                TextArea({ text: this.customWelcome, placeholder: '新会话时展示的欢迎消息' })
                  .fontSize(14)
                  .height(64)
                  .backgroundColor($r('app.color.bg_input'))
                  .borderRadius(12)
                  .onChange((value: string): void => {
                    this.customWelcome = value;
                  })
              }
              .width('100%')
              .alignItems(HorizontalAlign.Start)
              Column({ space: 6 }) {
                Text('系统提示词')
                  .fontSize(13)
                  .fontColor($r('app.color.text_secondary'))
                TextArea({ text: this.customPrompt, placeholder: '专家的系统提示词' })
                  .fontSize(14)
                  .height(120)
                  .backgroundColor($r('app.color.bg_input'))
                  .borderRadius(12)
                  .onChange((value: string): void => {
                    this.customPrompt = value;
                  })
              }
              .width('100%')
              .alignItems(HorizontalAlign.Start)
              Row() {
                Column({ space: 2 }) {
                  Text('共享给其他用户')
                    .fontSize(14)
                    .fontColor($r('app.color.text_primary'))
                  Text('开启后所有登录用户可对话（只读）')
                    .fontSize(12)
                    .fontColor($r('app.color.text_tertiary'))
                }
                .alignItems(HorizontalAlign.Start)
                .layoutWeight(1)
                Toggle({ type: ToggleType.Switch, isOn: this.customShared })
                  .onChange((isOn: boolean): void => {
                    this.customShared = isOn;
                  })
              }
              .width('100%')
              Button(this.customCreating ? '创建中…' : '创建专家')
                .fontSize(15)
                .fontWeight(FontWeight.Bold)
                .height(46)
                .width('100%')
                .borderRadius(23)
                .backgroundColor($r('app.color.brand'))
                .fontColor($r('app.color.text_on_brand'))
                .enabled(!this.customCreating)
                .margin({ top: 6 })
                .onClick((): void => {
                  this.createCustom();
                })
            }
            .width('100%')
            .padding({ left: 16, right: 16, top: 8, bottom: 30 })
          }
          .layoutWeight(1)
          .width('100%')
          .scrollBar(BarState.Off)
        }
      }
      .width('100%')
      .height('100%')
      .bindSheet($$this.detailOpen, this.detailSheetBuilder, {
        systemMaterial: UiMaterialKit.sheet(),
        detents: [SheetSize.MEDIUM, SheetSize.LARGE],
        showClose: true
      })
    }
    .hideTitleBar(true)
    .backgroundColor($r('app.color.bg_page'))
    .onReady((ctx: NavDestinationContext): void => {
      this.pathStack = ctx.pathStack;
    })
  }

  private mbtiIndex(): number {
    for (let i = 0; i < this.mbtiCodes.length; i++) {
      if (this.mbtiCodes[i].code === this.customMbti) {
        return i;
      }
    }
    return -1;
  }
}
