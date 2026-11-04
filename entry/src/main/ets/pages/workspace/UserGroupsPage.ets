import { UserAccountModel, UserGroupModel } from '../../model/AuthModels';
import { UserGroupService, UserService } from '../../service/AuthService';
import { OctopApiError } from '../../net/HttpClient';
import { EmptyView } from '../../components/EmptyView';
import { ErrorRetry } from '../../components/ErrorRetry';
import { PageHeader } from '../../components/PageHeader';
import { UiMaterialKit } from '../../components/UiMaterialKit';
import { TimeFormat } from '../../utils/TimeFormat';
import { MenuSheetContent, MenuSheetOption } from '../../components/MenuSheet';

/** 用户组管理：列表/创建/编辑/启停/成员管理/删除（需 users 权限） */
@Component
export struct UserGroupsPage {
  @State groups: Array<UserGroupModel> = [];
  @State users: Array<UserAccountModel> = [];
  @State loading: boolean = true;
  @State refreshing: boolean = false;
  @State errorMsg: string = '';
  @State operating: boolean = false;
  @State menuOpen: boolean = false;
  @State menuTitle: string = '';
  @State menuMessage: string = '';
  @State menuOptions: Array<MenuSheetOption> = [];
  private menuActions: Array<() => void> = [];
  private nameById: Map<number, string> = new Map();
  private dialogController: CustomDialogController | null = null;

  private onNavReady(ctx: NavDestinationContext): void {
    this.load();
  }

  private async load(): Promise<void> {
    this.loading = this.groups.length === 0;
    this.errorMsg = '';
    try {
      this.groups = await UserGroupService.list();
    } catch (e) {
      this.errorMsg = e instanceof OctopApiError ? e.message : '用户组加载失败';
      this.loading = false;
      return;
    }
    try {
      this.users = await UserService.list();
    } catch (e) {
      this.users = [];
    }
    this.rebuildNameMap();
    this.loading = false;
  }

  private rebuildNameMap(): void {
    const map: Map<number, string> = new Map();
    for (const user of this.users) {
      map.set(user.id, user.displayName);
    }
    this.nameById = map;
  }

  private displayNameFor(id: number): string {
    const name: string | undefined = this.nameById.get(id);
    if (name === undefined || name === '') {
      return `用户#${id}`;
    }
    return name;
  }

  private memberPreview(group: UserGroupModel): string {
    if (group.memberIds.length === 0) {
      return '暂无成员';
    }
    const names: Array<string> = [];
    const limit: number = Math.min(2, group.memberIds.length);
    for (let i = 0; i < limit; i++) {
      names.push(this.displayNameFor(group.memberIds[i]));
    }
    let preview: string = names.join('、');
    if (group.memberIds.length > 2) {
      preview = `${preview} 等 ${group.memberIds.length} 人`;
    }
    return preview;
  }

  private toastError(e: Object, fallback: string): void {
    const message: string = e instanceof OctopApiError ? e.message : fallback;
    this.getUIContext().getPromptAction().showToast({ message });
  }

  private showCreate(): void {
    this.dialogController = new CustomDialogController({
      builder: GroupEditDialog({
        groupId: '',
        initialName: '',
        initialDescription: '',
        onSaved: (): void => {
          this.load();
        }
      }),
      autoCancel: true,
      systemMaterial: UiMaterialKit.sheet()
    });
    this.dialogController.open();
  }

  private showEdit(group: UserGroupModel): void {
    this.dialogController = new CustomDialogController({
      builder: GroupEditDialog({
        groupId: group.id,
        initialName: group.name,
        initialDescription: group.description,
        onSaved: (): void => {
          this.load();
        }
      }),
      autoCancel: true,
      systemMaterial: UiMaterialKit.sheet()
    });
    this.dialogController.open();
  }

  private showMembers(group: UserGroupModel): void {
    this.dialogController = new CustomDialogController({
      builder: GroupMembersDialog({
        groupId: group.id,
        groupName: group.name,
        initialMemberIds: group.memberIds,
        onSaved: (): void => {
          this.load();
        }
      }),
      autoCancel: true,
      systemMaterial: UiMaterialKit.sheet()
    });
    this.dialogController.open();
  }

  private showGroupMenu(group: UserGroupModel): void {
    this.menuTitle = group.name;
    this.menuMessage = '选择操作';
    this.menuOptions = [
      new MenuSheetOption($r('sys.symbol.person_2'), '管理成员', `${group.memberIds.length} 位成员`, false),
      new MenuSheetOption($r('sys.symbol.square_and_pencil'), '编辑', '修改名称与描述', false),
      new MenuSheetOption($r('sys.symbol.trash'), '删除', '', true)
    ];
    this.menuActions = [
      (): void => {
        this.showMembers(group);
      },
      (): void => {
        this.showEdit(group);
      },
      (): void => {
        this.confirmDelete(group);
      }
    ];
    this.menuOpen = true;
  }

  /** 菜单选中：先关半模态再执行预置动作（越界保护） */
  private onMenuSelect(index: number): void {
    this.menuOpen = false;
    if (index < 0 || index >= this.menuActions.length) {
      return;
    }
    const action: () => void = this.menuActions[index];
    action();
  }

  private async toggleEnabled(group: UserGroupModel, on: boolean): Promise<void> {
    if (this.operating) {
      return;
    }
    this.operating = true;
    const body: Record<string, Object> = { 'enabled': on };
    try {
      await UserGroupService.patch(group.id, JSON.stringify(body));
      await this.load();
    } catch (e) {
      this.toastError(e, '操作失败');
    } finally {
      this.operating = false;
    }
  }

  private confirmDelete(group: UserGroupModel): void {
    this.getUIContext().showAlertDialog({
      title: '删除用户组',
      message: `确定删除「${group.name}」吗？该操作不可恢复。`,
      primaryButton: {
        value: $r('app.string.common_cancel'),
        action: (): void => {
        }
      },
      secondaryButton: {
        value: $r('app.string.common_confirm'),
        action: (): void => {
          this.deleteGroup(group);
        }
      },
      alignment: DialogAlignment.Bottom
    });
  }

  private async deleteGroup(group: UserGroupModel): Promise<void> {
    if (this.operating) {
      return;
    }
    this.operating = true;
    try {
      await UserGroupService.remove(group.id);
      this.getUIContext().getPromptAction().showToast({ message: '已删除' });
      await this.load();
    } catch (e) {
      this.toastError(e, '删除失败');
    } finally {
      this.operating = false;
    }
  }

  build() {
    NavDestination() {
      Stack({ alignContent: Alignment.BottomEnd }) {
        Column() {
          PageHeader({ title: '用户组管理' })

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
          } else if (this.groups.length === 0) {
            Column() {
              EmptyView({
                title: '暂无用户组',
                subtitle: '点击右下角按钮创建',
                icon: $r('sys.symbol.person')
              })
            }
            .layoutWeight(1)
            .width('100%')
            .justifyContent(FlexAlign.Center)
          } else {
            Refresh({ refreshing: $$this.refreshing }) {
              List({ space: 12 }) {
                ForEach(this.groups, (group: UserGroupModel) => {
                  ListItem() {
                    Row({ space: 12 }) {
                      Column() {
                        SymbolGlyph($r('sys.symbol.person'))
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
                          Text(group.name)
                            .fontSize(16)
                            .fontWeight(FontWeight.Medium)
                            .fontColor($r('app.color.text_primary'))
                            .maxLines(1)
                            .textOverflow({ overflow: TextOverflow.Ellipsis })
                            .layoutWeight(1)
                          Toggle({ type: ToggleType.Switch, isOn: group.enabled })
                            .onChange((isOn: boolean): void => {
                              this.toggleEnabled(group, isOn);
                            })
                        }
                        .width('100%')

                        if (group.description !== '') {
                          Text(group.description)
                            .fontSize(13)
                            .fontColor($r('app.color.text_secondary'))
                            .maxLines(2)
                            .textOverflow({ overflow: TextOverflow.Ellipsis })
                            .width('100%')
                            .lineHeight(19)
                        }

                        Row({ space: 8 }) {
                          Text(`${group.memberCount} 成员`)
                            .fontSize(11)
                            .fontColor($r('app.color.brand'))
                            .backgroundColor($r('app.color.brand_light'))
                            .borderRadius(6)
                            .padding({ left: 8, right: 8, top: 3, bottom: 3 })
                            .maxLines(1)
                          Text(this.memberPreview(group))
                            .fontSize(11)
                            .fontColor($r('app.color.text_tertiary'))
                            .maxLines(1)
                            .textOverflow({ overflow: TextOverflow.Ellipsis })
                            .layoutWeight(1)
                          if (group.createdAtMs > 0) {
                            Text(TimeFormat.list(group.createdAtMs))
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
                    .padding({ left: 14, right: 14, top: 14, bottom: 14 })
                    .borderRadius(16)
                    .backgroundColor($r('app.color.bg_card'))
                    .border({ width: 1, color: $r('app.color.card_stroke') })
                    .gesture(
                      LongPressGesture()
                        .onAction((event: GestureEvent): void => {
                          this.showGroupMenu(group);
                        })
                    )
                  }
                }, (group: UserGroupModel) => group.id)
              }
              .width('100%')
              .height('100%')
              .padding({ left: 14, right: 14, top: 4, bottom: 20 })
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
    .bindSheet($$this.menuOpen, this.menuSheetBuilder, {
      detents: [SheetSize.FIT_CONTENT],
      showClose: true,
      systemMaterial: UiMaterialKit.sheet()
    })
  }

  @Builder
  menuSheetBuilder() {
    MenuSheetContent({
      title: this.menuTitle,
      message: this.menuMessage,
      options: this.menuOptions,
      onSelect: (index: number): void => {
        this.onMenuSelect(index);
      }
    })
  }
}

/** 用户组创建/编辑对话框 */
@CustomDialog
struct GroupEditDialog {
  controller?: CustomDialogController;
  onSaved: () => void = (): void => {
  };
  /** 非空代表编辑模式 */
  groupId: string = '';
  initialName: string = '';
  initialDescription: string = '';

  @State isEdit: boolean = false;
  @State nameText: string = '';
  @State descText: string = '';
  @State submitting: boolean = false;

  aboutToAppear(): void {
    this.isEdit = this.groupId !== '';
    this.nameText = this.initialName;
    this.descText = this.initialDescription;
  }

  private async submit(): Promise<void> {
    if (this.submitting) {
      return;
    }
    const name: string = this.nameText.trim();
    if (name === '') {
      this.getUIContext().getPromptAction().showToast({ message: '请填写用户组名称' });
      return;
    }
    this.submitting = true;
    try {
      if (this.isEdit) {
        const body: Record<string, Object> = {
          'name': name,
          'description': this.descText.trim()
        };
        await UserGroupService.patch(this.groupId, JSON.stringify(body));
      } else {
        await UserGroupService.create(name, this.descText.trim());
      }
      this.controller?.close();
      this.getUIContext().getPromptAction().showToast({ message: this.isEdit ? '用户组已保存' : '用户组已创建' });
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
      Text(this.isEdit ? '编辑用户组' : '新建用户组')
        .fontSize(17)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.text_primary'))
        .width('100%')
        .textAlign(TextAlign.Start)

      TextInput({
        text: this.nameText,
        placeholder: '用户组名称 *'
      })
        .fontSize(14)
        .height(42)
        .backgroundColor($r('app.color.bg_input'))
        .borderRadius(12)
        .onChange((value: string): void => {
          this.nameText = value;
        })

      TextArea({
        text: this.descText,
        placeholder: '描述（可选）'
      })
        .fontSize(14)
        .height(80)
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
        Button(this.submitting ? '保存中...' : '保存')
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
}

/** 用户组成员管理对话框：勾选用户后全量替换成员 */
@CustomDialog
struct GroupMembersDialog {
  controller?: CustomDialogController;
  onSaved: () => void = (): void => {
  };
  groupId: string = '';
  groupName: string = '';
  initialMemberIds: Array<number> = [];

  @State users: Array<UserAccountModel> = [];
  @State selectedIds: Array<number> = [];
  @State loading: boolean = true;
  @State errorMsg: string = '';
  @State submitting: boolean = false;

  aboutToAppear(): void {
    const initial: Array<number> = [];
    for (const id of this.initialMemberIds) {
      initial.push(id);
    }
    this.selectedIds = initial;
    this.load();
  }

  private async load(): Promise<void> {
    this.loading = true;
    this.errorMsg = '';
    try {
      this.users = await UserService.list();
    } catch (e) {
      this.errorMsg = e instanceof OctopApiError ? e.message : '用户列表加载失败';
    } finally {
      this.loading = false;
    }
  }

  private isSelected(id: number): boolean {
    for (const item of this.selectedIds) {
      if (item === id) {
        return true;
      }
    }
    return false;
  }

  private toggleSelected(id: number): void {
    const next: Array<number> = [];
    let removed: boolean = false;
    for (const item of this.selectedIds) {
      if (item === id) {
        removed = true;
      } else {
        next.push(item);
      }
    }
    if (!removed) {
      next.push(id);
    }
    this.selectedIds = next;
  }

  private async submit(): Promise<void> {
    if (this.submitting) {
      return;
    }
    this.submitting = true;
    try {
      await UserGroupService.replaceMembers(this.groupId, this.selectedIds);
      this.controller?.close();
      this.getUIContext().getPromptAction().showToast({ message: '成员已保存' });
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
      Text(`管理成员：${this.groupName}`)
        .fontSize(17)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.text_primary'))
        .width('100%')
        .textAlign(TextAlign.Start)

      if (this.loading) {
        Column() {
          LoadingProgress()
            .width(32)
            .height(32)
            .color($r('app.color.brand'))
        }
        .width('100%')
        .height(240)
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
        .width('100%')
      } else if (this.users.length === 0) {
        Column() {
          Text('暂无可选用户')
            .fontSize(13)
            .fontColor($r('app.color.text_secondary'))
        }
        .width('100%')
        .padding({ top: 40, bottom: 40 })
        .alignItems(HorizontalAlign.Center)
      } else {
        Text(`已选 ${this.selectedIds.length} / ${this.users.length} 人`)
          .fontSize(12)
          .fontColor($r('app.color.text_tertiary'))
          .width('100%')
          .textAlign(TextAlign.Start)

        List({ space: 8 }) {
          ForEach(this.users, (user: UserAccountModel) => {
            ListItem() {
              Row({ space: 10 }) {
                Column() {
                  if (this.isSelected(user.id)) {
                    SymbolGlyph($r('sys.symbol.checkmark'))
                      .fontSize(14)
                      .fontColor([$r('app.color.text_on_brand')])
                  }
                }
                .width(24)
                .height(24)
                .borderRadius(12)
                .justifyContent(FlexAlign.Center)
                .alignItems(HorizontalAlign.Center)
                .backgroundColor(this.isSelected(user.id)
                  ? $r('app.color.brand') : $r('app.color.bg_input'))
                .border({ width: 1, color: this.isSelected(user.id)
                  ? $r('app.color.brand') : $r('app.color.card_stroke') })

                Column({ space: 2 }) {
                  Text(user.displayName)
                    .fontSize(14)
                    .fontWeight(FontWeight.Medium)
                    .fontColor($r('app.color.text_primary'))
                    .maxLines(1)
                    .textOverflow({ overflow: TextOverflow.Ellipsis })
                  Text(`@${user.username}`)
                    .fontSize(11)
                    .fontColor($r('app.color.text_tertiary'))
                    .maxLines(1)
                    .textOverflow({ overflow: TextOverflow.Ellipsis })
                }
                .layoutWeight(1)
                .alignItems(HorizontalAlign.Start)
              }
              .width('100%')
              .onClick((): void => {
                this.toggleSelected(user.id);
              })
            }
          }, (user: UserAccountModel) => `${user.id}-${user.username}`)
        }
        .width('100%')
        .height(260)
        .scrollBar(BarState.Off)
      }

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
        Button(this.submitting ? '保存中...' : '保存')
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
}
