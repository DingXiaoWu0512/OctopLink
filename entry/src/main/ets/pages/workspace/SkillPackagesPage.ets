import { SkillPackageModel, SkillSummaryModel } from '../../model/SkillModels';
import { SkillPackageService } from '../../service/SkillPackageService';
import { SkillService } from '../../service/SkillService';
import { OctopApiError } from '../../net/HttpClient';
import { SessionStore } from '../../store/SessionStore';
import { EmptyView } from '../../components/EmptyView';
import { ErrorRetry } from '../../components/ErrorRetry';
import { PageHeader } from '../../components/PageHeader';
import { UiMaterialKit } from '../../components/UiMaterialKit';
import { TimeFormat } from '../../utils/TimeFormat';
import { picker, fileIo } from '@kit.CoreFileKit';

/** 技能包管理：列表 + 挂载当前专家 + 复制/导出/删除 */
@Component
export struct SkillPackagesPage {
  @State packages: Array<SkillPackageModel> = [];
  @State mountedIds: Array<string> = [];
  @State loading: boolean = true;
  @State refreshing: boolean = false;
  @State errorMsg: string = '';
  @State operating: boolean = false;
  @State expandedId: string = '';
  private agentId: string = '';
  private pathStack: NavPathStack | null = null;
  private createController: CustomDialogController | null = null;

  private onNavReady(ctx: NavDestinationContext): void {
    this.pathStack = ctx.pathStack;
    this.agentId = AppStorage.get<string>(SessionStore.KEY_AGENT_ID) ?? '';
    this.load();
  }

  private async load(): Promise<void> {
    this.loading = true;
    this.errorMsg = '';
    try {
      this.packages = await SkillPackageService.list();
      if (this.agentId !== '') {
        const mounted: Array<SkillPackageModel> =
          await SkillService.listAgentPackages(this.agentId);
        const ids: Array<string> = [];
        for (const pkg of mounted) {
          ids.push(pkg.id);
        }
        this.mountedIds = ids;
      } else {
        this.mountedIds = [];
      }
    } catch (e) {
      this.errorMsg = e instanceof OctopApiError ? e.message : '技能包加载失败';
    } finally {
      this.loading = false;
    }
  }

  private isMounted(pkg: SkillPackageModel): boolean {
    return this.mountedIds.indexOf(pkg.id) >= 0;
  }

  private isExpanded(pkg: SkillPackageModel): boolean {
    return this.expandedId === pkg.id;
  }

  private creatorLabel(pkg: SkillPackageModel): string {
    if (pkg.creatorDisplayName !== '') {
      return pkg.creatorDisplayName;
    }
    if (pkg.creatorUsername !== '') {
      return pkg.creatorUsername;
    }
    return '未知创建者';
  }

  private updatedLabel(pkg: SkillPackageModel): string {
    if (pkg.updatedAtMs > 0) {
      return `更新于 ${TimeFormat.list(pkg.updatedAtMs)}`;
    }
    return '';
  }

  private copyPolicyLabel(pkg: SkillPackageModel): string {
    if (pkg.copyPolicy === 'lock') {
      return '锁定';
    }
    if (pkg.copyPolicy === 'deny') {
      return '禁止复制';
    }
    return '快照';
  }

  private skillEmoji(skill: SkillSummaryModel): string {
    if (skill.emoji !== '') {
      return skill.emoji;
    }
    return '🧩';
  }

  private toggleExpanded(pkg: SkillPackageModel): void {
    this.expandedId = this.expandedId === pkg.id ? '' : pkg.id;
  }

  private async toggleMount(pkg: SkillPackageModel, isOn: boolean): Promise<void> {
    if (this.agentId === '') {
      this.getUIContext().getPromptAction().showToast({ message: '请先选择专家' });
      this.load();
      return;
    }
    if (this.operating) {
      this.load();
      return;
    }
    this.operating = true;
    const next: Array<string> = [];
    for (const id of this.mountedIds) {
      if (id !== pkg.id) {
        next.push(id);
      }
    }
    if (isOn) {
      next.push(pkg.id);
    }
    try {
      await SkillService.putAgentPackages(this.agentId, next);
      this.mountedIds = next;
    } catch (e) {
      const message: string = e instanceof OctopApiError ? e.message : '操作失败';
      this.getUIContext().getPromptAction().showToast({ message });
      this.load();
    } finally {
      this.operating = false;
    }
  }

  private async copyToAgent(pkg: SkillPackageModel): Promise<void> {
    if (this.agentId === '') {
      this.getUIContext().getPromptAction().showToast({ message: '请先选择专家' });
      return;
    }
    if (pkg.skills.length === 0) {
      this.getUIContext().getPromptAction().showToast({ message: '包内暂无技能' });
      return;
    }
    if (this.operating) {
      return;
    }
    this.operating = true;
    try {
      const slugs: Array<string> = [];
      for (const skill of pkg.skills) {
        slugs.push(skill.slug);
      }
      const copied: Array<string> =
        await SkillService.copyPackageSkills(this.agentId, pkg.id, slugs);
      this.getUIContext().getPromptAction().showToast({ message: `已复制 ${copied.length} 个技能` });
    } catch (e) {
      const message: string = e instanceof OctopApiError ? e.message : '复制失败';
      this.getUIContext().getPromptAction().showToast({ message });
    } finally {
      this.operating = false;
    }
  }

  private async exportZip(pkg: SkillPackageModel): Promise<void> {
    if (this.operating) {
      return;
    }
    this.operating = true;
    try {
      const buffer: ArrayBuffer = await SkillPackageService.exportZip(pkg.id);
      this.saveZip(pkg.id, buffer);
    } catch (e) {
      const message: string = e instanceof OctopApiError ? e.message : '导出失败';
      this.getUIContext().getPromptAction().showToast({ message });
    } finally {
      this.operating = false;
    }
  }

  private saveZip(packageId: string, buffer: ArrayBuffer): void {
    const docPicker = new picker.DocumentViewPicker();
    const saveOptions = new picker.DocumentSaveOptions();
    saveOptions.newFileNames = [`package_${packageId}.zip`];
    docPicker.save(saveOptions).then(async (uris: Array<string>): Promise<void> => {
      if (uris.length > 0) {
        const file = fileIo.openSync(uris[0], fileIo.OpenMode.READ_WRITE);
        try {
          fileIo.writeSync(file.fd, buffer);
        } finally {
          fileIo.closeSync(file);
        }
        this.getUIContext().getPromptAction().showToast({ message: '已导出 ZIP' });
      }
    }).catch((): void => {
    });
  }

  private confirmDelete(pkg: SkillPackageModel): void {
    this.getUIContext().showAlertDialog({
      title: '删除技能包',
      message: `确定删除「${pkg.name}」吗？`,
      primaryButton: {
        value: $r('app.string.common_cancel'),
        action: (): void => {
        }
      },
      secondaryButton: {
        value: $r('app.string.common_confirm'),
        action: (): void => {
          this.removePackage(pkg);
        }
      },
      alignment: DialogAlignment.Bottom
    });
  }

  private async removePackage(pkg: SkillPackageModel): Promise<void> {
    if (this.operating) {
      return;
    }
    this.operating = true;
    try {
      await SkillPackageService.remove(pkg.id);
      if (this.expandedId === pkg.id) {
        this.expandedId = '';
      }
      this.getUIContext().getPromptAction().showToast({ message: '已删除' });
      await this.load();
    } catch (e) {
      const message: string = e instanceof OctopApiError ? e.message : '删除失败';
      this.getUIContext().getPromptAction().showToast({ message });
    } finally {
      this.operating = false;
    }
  }

  private showCreate(): void {
    this.createController = new CustomDialogController({
      builder: SkillPackageCreateDialog({
        onSaved: (): void => {
          this.load();
        }
      }),
      autoCancel: true,
      systemMaterial: UiMaterialKit.sheet()
    });
    this.createController.open();
  }

  build() {
    NavDestination() {
      Stack({ alignContent: Alignment.BottomEnd }) {
        Column() {
          PageHeader({ title: '技能包' })

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
          } else if (this.packages.length === 0) {
            Column() {
              EmptyView({
                title: '暂无技能包',
                subtitle: '点击右下角按钮创建',
                icon: $r('sys.symbol.square_grid_2x2')
              })
            }
            .layoutWeight(1)
            .width('100%')
            .justifyContent(FlexAlign.Center)
          } else {
            Refresh({ refreshing: $$this.refreshing }) {
              List({ space: 12 }) {
                ForEach(this.packages, (pkg: SkillPackageModel) => {
                  ListItem() {
                    Column({ space: 12 }) {
                      Row({ space: 12 }) {
                        Column() {
                          SymbolGlyph($r('sys.symbol.book'))
                            .fontSize(20)
                            .fontColor([$r('app.color.brand')])
                        }
                        .width(42)
                        .height(42)
                        .borderRadius(13)
                        .backgroundColor($r('app.color.brand_light'))
                        .justifyContent(FlexAlign.Center)

                        Column({ space: 7 }) {
                          Row() {
                            Text(pkg.name)
                              .fontSize(16)
                              .fontWeight(FontWeight.Medium)
                              .fontColor($r('app.color.text_primary'))
                              .maxLines(1)
                              .textOverflow({ overflow: TextOverflow.Ellipsis })
                              .layoutWeight(1)
                            Toggle({ type: ToggleType.Switch, isOn: this.isMounted(pkg) })
                              .onChange((isOn: boolean): void => {
                                this.toggleMount(pkg, isOn);
                              })
                          }
                          .width('100%')

                          Text(pkg.description)
                            .fontSize(13)
                            .fontColor($r('app.color.text_secondary'))
                            .maxLines(2)
                            .textOverflow({ overflow: TextOverflow.Ellipsis })
                            .width('100%')
                            .lineHeight(19)

                          Row({ space: 8 }) {
                            Text(`${pkg.skillCount} 技能`)
                              .fontSize(11)
                              .fontColor($r('app.color.brand'))
                              .backgroundColor($r('app.color.brand_light'))
                              .borderRadius(6)
                              .padding({ left: 8, right: 8, top: 3, bottom: 3 })
                              .maxLines(1)
                            Text(this.copyPolicyLabel(pkg))
                              .fontSize(11)
                              .fontColor($r('app.color.text_secondary'))
                              .backgroundColor($r('app.color.bg_input'))
                              .borderRadius(6)
                              .padding({ left: 8, right: 8, top: 3, bottom: 3 })
                              .maxLines(1)
                            Text(this.creatorLabel(pkg))
                              .fontSize(11)
                              .fontColor($r('app.color.text_tertiary'))
                              .maxLines(1)
                            if (pkg.updatedAtMs > 0) {
                              Text(this.updatedLabel(pkg))
                                .fontSize(11)
                                .fontColor($r('app.color.text_tertiary'))
                                .maxLines(1)
                            }
                          }
                          .width('100%')
                        }
                        .layoutWeight(1)
                        .alignItems(HorizontalAlign.Start)
                      }
                      .width('100%')
                      .onClick((): void => {
                        this.toggleExpanded(pkg);
                      })

                      if (this.isExpanded(pkg)) {
                        Column({ space: 10 }) {
                          Column({ space: 6 }) {
                            ForEach(pkg.skills, (skill: SkillSummaryModel) => {
                              Row({ space: 8 }) {
                                Text(this.skillEmoji(skill))
                                  .fontSize(16)
                                  .width(24)
                                  .textAlign(TextAlign.Center)
                                Column({ space: 2 }) {
                                  Text(skill.displayTitle())
                                    .fontSize(13)
                                    .fontWeight(FontWeight.Medium)
                                    .fontColor($r('app.color.text_primary'))
                                    .maxLines(1)
                                    .textOverflow({ overflow: TextOverflow.Ellipsis })
                                    .width('100%')
                                  Text(skill.displaySummary())
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
                            }, (skill: SkillSummaryModel, index: number) => `${index}-${skill.slug}`)
                          }
                          .width('100%')

                          Row({ space: 8 }) {
                            if (pkg.canCopy) {
                              Button('复制到专家')
                                .fontSize(12)
                                .height(30)
                                .padding({ left: 12, right: 12 })
                                .borderRadius(15)
                                .backgroundColor($r('app.color.brand_light'))
                                .fontColor($r('app.color.brand'))
                                .onClick((): void => {
                                  this.copyToAgent(pkg);
                                })
                            }
                            if (pkg.canDownload) {
                              Button('导出 ZIP')
                                .fontSize(12)
                                .height(30)
                                .padding({ left: 12, right: 12 })
                                .borderRadius(15)
                                .backgroundColor($r('app.color.bg_input'))
                                .fontColor($r('app.color.text_secondary'))
                                .onClick((): void => {
                                  this.exportZip(pkg);
                                })
                            }
                            if (pkg.canWrite) {
                              Button('删除包')
                                .fontSize(12)
                                .height(30)
                                .padding({ left: 12, right: 12 })
                                .borderRadius(15)
                                .backgroundColor($r('app.color.danger_soft'))
                                .fontColor($r('app.color.danger'))
                                .onClick((): void => {
                                  this.confirmDelete(pkg);
                                })
                            }
                          }
                          .width('100%')
                        }
                        .width('100%')
                        .padding({ top: 10 })
                        .border({ width: 1, color: $r('app.color.divider') })
                        .borderRadius(12)
                      }
                    }
                    .width('100%')
                    .padding({ left: 14, right: 14, top: 14, bottom: 14 })
                    .borderRadius(16)
                    .backgroundColor($r('app.color.bg_card'))
                  }
                }, (pkg: SkillPackageModel) => pkg.id)
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
        .backgroundColor($r('app.color.fab_glass'))
        .backgroundBlurStyle(BlurStyle.COMPONENT_THICK)
        .border({ width: 1, color: $r('app.color.card_stroke') })
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

/** 新建技能包对话框 */
@CustomDialog
struct SkillPackageCreateDialog {
  controller?: CustomDialogController;
  onSaved: () => void = (): void => {
  };
  @State nameText: string = '';
  @State descText: string = '';
  @State submitting: boolean = false;

  private submitLabel(): string {
    if (this.submitting) {
      return '创建中...';
    }
    return '创建';
  }

  private async submit(): Promise<void> {
    if (this.submitting) {
      return;
    }
    const name: string = this.nameText.trim();
    if (name === '') {
      this.getUIContext().getPromptAction().showToast({ message: '请填写包名称' });
      return;
    }
    this.submitting = true;
    try {
      await SkillPackageService.create(name, this.descText.trim());
      this.controller?.close();
      this.getUIContext().getPromptAction().showToast({ message: '技能包已创建' });
      this.onSaved();
    } catch (e) {
      const message: string = e instanceof OctopApiError ? e.message : '创建失败';
      this.getUIContext().getPromptAction().showToast({ message });
    } finally {
      this.submitting = false;
    }
  }

  build() {
    Column({ space: 14 }) {
      Text('新建技能包')
        .fontSize(17)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.text_primary'))
        .width('100%')
        .textAlign(TextAlign.Start)

      TextInput({
        text: this.nameText,
        placeholder: '包名称'
      })
        .fontSize(14)
        .height(42)
        .backgroundColor($r('app.color.bg_input'))
        .borderRadius(12)
        .onChange((value: string): void => {
          this.nameText = value;
        })

      TextInput({
        text: this.descText,
        placeholder: '描述（可选）'
      })
        .fontSize(14)
        .height(42)
        .backgroundColor($r('app.color.bg_input'))
        .borderRadius(12)
        .onChange((value: string): void => {
          this.descText = value;
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
        Button(this.submitLabel())
          .fontSize(14)
          .height(38)
          .layoutWeight(1)
          .borderRadius(19)
          .backgroundColor($r('app.color.brand'))
          .fontColor($r('app.color.bg_card'))
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
}
