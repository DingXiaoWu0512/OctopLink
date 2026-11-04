import { AdminService } from '../../service/AdminService';
import { UserAccountModel, UserRoleModel } from '../../model/AuthModels';
import { AdminOverviewModel } from '../../model/AdminModels';
import { OctopApiError } from '../../net/HttpClient';
import { EmptyView } from '../../components/EmptyView';
import { ErrorRetry } from '../../components/ErrorRetry';
import { PageHeader } from '../../components/PageHeader';
import { UiMaterialKit } from '../../components/UiMaterialKit';
import { MenuSheetContent, MenuSheetOption } from '../../components/MenuSheet';

/** 概览统计单元格（ForEach 用稳定对象） */
class AdminStatCell {
  readonly label: string;
  readonly value: string;

  constructor(label: string, value: string) {
    this.label = label;
    this.value = value;
  }
}

/** 重置密码对话框（POST /api/users/{id}/reset-password） */
@CustomDialog
struct AdminResetPasswordDialog {
  controller?: CustomDialogController;
  userId: number = 0;
  username: string = '';
  onSaved: () => void = (): void => {
  };

  @State passwordText: string = '';
  @State confirmText: string = '';
  @State submitting: boolean = false;

  private async submit(): Promise<void> {
    if (this.submitting) {
      return;
    }
    const password: string = this.passwordText.trim();
    if (password === '') {
      this.getUIContext().getPromptAction().showToast({ message: '请输入新密码' });
      return;
    }
    if (password !== this.confirmText.trim()) {
      this.getUIContext().getPromptAction().showToast({ message: '两次输入的密码不一致' });
      return;
    }
    this.submitting = true;
    try {
      await AdminService.resetPassword(this.userId, password);
      this.controller?.close();
      this.getUIContext().getPromptAction().showToast({ message: '密码已重置' });
      this.onSaved();
    } catch (e) {
      const message: string = e instanceof OctopApiError ? e.message : '重置失败';
      this.getUIContext().getPromptAction().showToast({ message });
    } finally {
      this.submitting = false;
    }
  }

  build() {
    Column({ space: 14 }) {
      Text('重置密码')
        .fontSize(17)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.text_primary'))
        .width('100%')
        .textAlign(TextAlign.Start)

      Text(`为「${this.username}」设置新密码`)
        .fontSize(12)
        .fontColor($r('app.color.text_tertiary'))
        .width('100%')

      TextInput({
        text: this.passwordText,
        placeholder: '新密码'
      })
        .fontSize(14)
        .height(42)
        .type(InputType.Password)
        .backgroundColor($r('app.color.bg_input'))
        .borderRadius(12)
        .onChange((value: string): void => {
          this.passwordText = value;
        })

      TextInput({
        text: this.confirmText,
        placeholder: '再次输入新密码'
      })
        .fontSize(14)
        .height(42)
        .type(InputType.Password)
        .backgroundColor($r('app.color.bg_input'))
        .borderRadius(12)
        .onChange((value: string): void => {
          this.confirmText = value;
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
        Button(this.submitting ? '提交中...' : '确认重置')
          .fontSize(14)
          .height(38)
          .layoutWeight(1)
          .borderRadius(19)
          .backgroundColor($r('app.color.brand'))
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

/**
 * 管理员控制台（路由 'admin'）：
 * - 顶部系统概览卡（用户数/专家数/运行中，GET /api/admin/overview）
 * - 用户列表：角色徽章 / 启停 Toggle / 长按菜单（重置密码/修改角色/解锁登录/删除）
 * - 非管理员访问：403 → 「需要管理员权限」错误态
 */
@Component
export struct AdminPage {
  @State overview: AdminOverviewModel | null = null;
  @State users: Array<UserAccountModel> = [];
  @State roles: Array<UserRoleModel> = [];
  @State loading: boolean = true;
  @State refreshing: boolean = false;
  @State errorMsg: string = '';
  @State operating: boolean = false;
  @State menuOpen: boolean = false;
  @State menuTitle: string = '';
  @State menuMessage: string = '';
  @State menuOptions: Array<MenuSheetOption> = [];
  private menuActions: Array<() => void> = [];
  private resetController: CustomDialogController | null = null;
  private pathStack: NavPathStack | null = null;

  onNavReady(ctx: NavDestinationContext): void {
    this.pathStack = ctx.pathStack;
    this.load();
  }

  /** 统一错误文案：403/权限不足给专门提示 */
  private errorMessage(e: Object, fallback: string): string {
    if (e instanceof OctopApiError) {
      if (e.status === 403) {
        return '需要管理员权限';
      }
      return e.message;
    }
    return fallback;
  }

  private async load(): Promise<void> {
    this.loading = this.overview === null;
    this.errorMsg = '';
    try {
      this.overview = await AdminService.overview();
    } catch (e) {
      this.overview = null;
    }
    try {
      this.users = await AdminService.listUsers();
    } catch (e) {
      this.errorMsg = this.errorMessage(e, '用户列表加载失败');
      this.loading = false;
      return;
    }
    try {
      this.roles = await AdminService.listRoles();
    } catch (e) {
      this.roles = [];
    }
    this.loading = false;
  }

  private statCells(): Array<AdminStatCell> {
    if (this.overview === null) {
      return [];
    }
    const overview: AdminOverviewModel = this.overview;
    return [
      new AdminStatCell('用户数', `${overview.totalUsers}`),
      new AdminStatCell('专家数', `${overview.totalAgents}`),
      new AdminStatCell('运行中', `${overview.runningAgents()}`)
    ];
  }

  private roleBadgeText(user: UserAccountModel): string {
    if (user.roleName !== '') {
      return user.roleName;
    }
    return user.role;
  }

  private userSubtitle(user: UserAccountModel): string {
    if (user.email !== '') {
      return user.email;
    }
    if (user.displayName !== '' && user.displayName !== user.username) {
      return user.displayName;
    }
    return '';
  }

  private showResetDialog(user: UserAccountModel): void {
    this.resetController = new CustomDialogController({
      builder: AdminResetPasswordDialog({
        userId: user.id,
        username: user.username,
        onSaved: (): void => {
          this.load();
        }
      }),
      autoCancel: true,
      systemMaterial: UiMaterialKit.sheet()
    });
    this.resetController.open();
  }

  /** 修改角色：角色列表选单（PATCH /api/users/{id} {role}） */
  private showRoleSheet(user: UserAccountModel): void {
    if (this.roles.length === 0) {
      this.getUIContext().getPromptAction().showToast({ message: '角色列表加载失败，请重试' });
      return;
    }
    const options: Array<MenuSheetOption> = [];
    const actions: Array<() => void> = [];
    for (const role of this.roles) {
      const roleId: string = role.id;
      options.push(new MenuSheetOption($r('sys.symbol.person'),
        role.name === '' ? role.id : `${role.name}（${role.id}）`,
        role.description, false));
      actions.push((): void => {
        this.applyRole(user, roleId);
      });
    }
    this.menuTitle = '修改角色';
    this.menuMessage = `为「${user.username}」选择新角色`;
    this.menuOptions = options;
    this.menuActions = actions;
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

  private async applyRole(user: UserAccountModel, roleId: string): Promise<void> {
    if (this.operating) {
      return;
    }
    this.operating = true;
    try {
      await AdminService.changeRole(user.id, roleId);
      this.getUIContext().getPromptAction().showToast({ message: '角色已更新' });
      await this.load();
    } catch (e) {
      const message: string = this.errorMessage(e, '角色更新失败');
      this.getUIContext().getPromptAction().showToast({ message });
    } finally {
      this.operating = false;
    }
  }

  private async unlockUser(user: UserAccountModel): Promise<void> {
    if (this.operating) {
      return;
    }
    this.operating = true;
    try {
      await AdminService.unlockLogin(user.id);
      this.getUIContext().getPromptAction().showToast({ message: '登录锁定已清除' });
      await this.load();
    } catch (e) {
      const message: string = this.errorMessage(e, '解锁失败');
      this.getUIContext().getPromptAction().showToast({ message });
    } finally {
      this.operating = false;
    }
  }

  private confirmDelete(user: UserAccountModel): void {
    this.getUIContext().showAlertDialog({
      title: '删除用户',
      message: `确定删除「${user.username}」吗？该操作不可恢复。`,
      primaryButton: {
        value: $r('app.string.common_cancel'),
        action: (): void => {
        }
      },
      secondaryButton: {
        value: $r('app.string.common_confirm'),
        action: (): void => {
          this.deleteUser(user);
        }
      },
      alignment: DialogAlignment.Bottom
    });
  }

  private async deleteUser(user: UserAccountModel): Promise<void> {
    if (this.operating) {
      return;
    }
    this.operating = true;
    try {
      await AdminService.deleteUser(user.id);
      this.getUIContext().getPromptAction().showToast({ message: '用户已删除' });
      await this.load();
    } catch (e) {
      const message: string = this.errorMessage(e, '删除失败');
      this.getUIContext().getPromptAction().showToast({ message });
    } finally {
      this.operating = false;
    }
  }

  private showUserMenu(user: UserAccountModel): void {
    const options: Array<MenuSheetOption> = [
      new MenuSheetOption($r('sys.symbol.key'), '重置密码', '', false),
      new MenuSheetOption($r('sys.symbol.person'), '修改角色', '从角色模板中选择', false)
    ];
    const actions: Array<() => void> = [
      (): void => {
        this.showResetDialog(user);
      },
      (): void => {
        this.showRoleSheet(user);
      }
    ];
    if (user.loginLocked) {
      options.push(new MenuSheetOption($r('sys.symbol.lock_open'), '解锁登录', '', false));
      actions.push((): void => {
        this.unlockUser(user);
      });
    }
    options.push(new MenuSheetOption($r('sys.symbol.trash'), '删除用户', '', true));
    actions.push((): void => {
      this.confirmDelete(user);
    });
    this.menuTitle = user.username;
    this.menuMessage = '选择操作';
    this.menuOptions = options;
    this.menuActions = actions;
    this.menuOpen = true;
  }

  /** 启停用户（PATCH /api/users/{id} {disabled}） */
  private async toggleUser(user: UserAccountModel, on: boolean): Promise<void> {
    if (this.operating) {
      return;
    }
    this.operating = true;
    try {
      await AdminService.setUserEnabled(user.id, on);
      await this.load();
    } catch (e) {
      const message: string = this.errorMessage(e, '操作失败');
      this.getUIContext().getPromptAction().showToast({ message });
      await this.load();
    } finally {
      this.operating = false;
    }
  }

  build() {
    NavDestination() {
      Column() {
        PageHeader({ title: '管理员控制台' })

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
            List({ space: 12 }) {
              ListItem() {
                Row({ space: 12 }) {
                  Column() {
                    SymbolGlyph($r('sys.symbol.wrench_and_screwdriver'))
                      .fontSize(20)
                      .fontColor([$r('app.color.brand')])
                  }
                  .width(42)
                  .height(42)
                  .borderRadius(13)
                  .backgroundColor($r('app.color.brand_light'))
                  .justifyContent(FlexAlign.Center)

                  Column({ space: 3 }) {
                    Text('运维管理')
                      .fontSize(16)
                      .fontWeight(FontWeight.Medium)
                      .fontColor($r('app.color.text_primary'))
                    Text('备份 · 服务更新 · 安全策略 · 环境变量 · TLS')
                      .fontSize(12)
                      .fontColor($r('app.color.text_tertiary'))
                  }
                  .layoutWeight(1)
                  .alignItems(HorizontalAlign.Start)

                  SymbolGlyph($r('sys.symbol.chevron_right'))
                    .fontSize(13)
                    .fontColor([$r('app.color.icon_secondary')])
                }
                .width('100%')
                .padding({ left: 14, right: 14, top: 12, bottom: 12 })
                .borderRadius(16)
                .backgroundColor($r('app.color.bg_card'))
                .border({ width: 1, color: $r('app.color.divider') })
                .onClick((): void => {
                  if (this.pathStack !== null) {
                    this.pathStack.pushPathByName('adminOps', '');
                  }
                })
              }

              if (this.overview !== null) {
                ListItem() {
                  Column({ space: 12 }) {
                    Row({ space: 10 }) {
                      Column() {
                        SymbolGlyph($r('sys.symbol.wand_and_stars'))
                          .fontSize(20)
                          .fontColor([$r('app.color.brand')])
                      }
                      .width(42)
                      .height(42)
                      .borderRadius(13)
                      .backgroundColor($r('app.color.brand_light'))
                      .justifyContent(FlexAlign.Center)

                      Text('系统概览')
                        .fontSize(16)
                        .fontWeight(FontWeight.Bold)
                        .fontColor($r('app.color.text_primary'))
                        .layoutWeight(1)
                    }
                    .width('100%')

                    Row() {
                      ForEach(this.statCells(), (cell: AdminStatCell) => {
                        Column({ space: 4 }) {
                          Text(cell.value)
                            .fontSize(22)
                            .fontWeight(FontWeight.Bold)
                            .fontColor($r('app.color.brand'))
                          Text(cell.label)
                            .fontSize(11)
                            .fontColor($r('app.color.text_tertiary'))
                        }
                        .layoutWeight(1)
                        .alignItems(HorizontalAlign.Center)
                      }, (cell: AdminStatCell) => cell.label)
                    }
                    .width('100%')

                    Text('长按用户卡片可重置密码 / 修改角色 / 删除')
                      .fontSize(11)
                      .fontColor($r('app.color.text_tertiary'))
                      .width('100%')
                  }
                  .width('100%')
                  .padding(14)
                  .borderRadius(16)
                  .backgroundColor($r('app.color.bg_card'))
                  .border({ width: 1, color: $r('app.color.divider') })
                }
              }

              if (this.users.length === 0) {
                ListItem() {
                  EmptyView({
                    title: '暂无用户',
                    subtitle: '服务器上还没有注册用户',
                    icon: $r('sys.symbol.person_2')
                  })
                }
              } else {
                ForEach(this.users, (user: UserAccountModel) => {
                  ListItem() {
                    Row({ space: 12 }) {
                      Column() {
                        SymbolGlyph($r('sys.symbol.person_2'))
                          .fontSize(20)
                          .fontColor([$r('app.color.brand')])
                      }
                      .width(42)
                      .height(42)
                      .borderRadius(13)
                      .backgroundColor($r('app.color.brand_light'))
                      .justifyContent(FlexAlign.Center)
                      .opacity(user.disabled ? 0.45 : 1)

                      Column({ space: 7 }) {
                        Row() {
                          Text(user.username)
                            .fontSize(16)
                            .fontWeight(FontWeight.Medium)
                            .fontColor(user.disabled ? $r('app.color.text_tertiary')
                              : $r('app.color.text_primary'))
                            .maxLines(1)
                            .textOverflow({ overflow: TextOverflow.Ellipsis })
                            .layoutWeight(1)
                          Toggle({ type: ToggleType.Switch, isOn: !user.disabled })
                            .onChange((isOn: boolean): void => {
                              this.toggleUser(user, isOn);
                            })
                        }
                        .width('100%')

                        Row({ space: 8 }) {
                          if (user.role === 'admin') {
                            Text(this.roleBadgeText(user))
                              .fontSize(11)
                              .fontColor($r('app.color.brand'))
                              .backgroundColor($r('app.color.brand_light'))
                              .borderRadius(6)
                              .padding({ left: 8, right: 8, top: 3, bottom: 3 })
                              .maxLines(1)
                          } else {
                            Text(this.roleBadgeText(user))
                              .fontSize(11)
                              .fontColor($r('app.color.text_secondary'))
                              .backgroundColor($r('app.color.bg_input'))
                              .borderRadius(6)
                              .padding({ left: 8, right: 8, top: 3, bottom: 3 })
                              .maxLines(1)
                          }
                          if (user.loginLocked) {
                            Text('已锁定')
                              .fontSize(11)
                              .fontColor($r('app.color.warning'))
                              .backgroundColor($r('app.color.warning_soft'))
                              .borderRadius(6)
                              .padding({ left: 8, right: 8, top: 3, bottom: 3 })
                          }
                          if (user.disabled) {
                            Text('已停用')
                              .fontSize(11)
                              .fontColor($r('app.color.text_tertiary'))
                              .maxLines(1)
                          }
                          if (this.userSubtitle(user) !== '') {
                            Text(this.userSubtitle(user))
                              .fontSize(11)
                              .fontColor($r('app.color.text_tertiary'))
                              .maxLines(1)
                              .textOverflow({ overflow: TextOverflow.Ellipsis })
                              .constraintSize({ maxWidth: 150 })
                          }
                        }
                        .width('100%')
                      }
                      .layoutWeight(1)
                      .alignItems(HorizontalAlign.Start)
                    }
                    .width('100%')
                    .padding(14)
                    .borderRadius(16)
                    .backgroundColor($r('app.color.bg_card'))
                    .border({ width: 1, color: $r('app.color.divider') })
                    .gesture(
                      LongPressGesture()
                        .onAction((event: GestureEvent): void => {
                          this.showUserMenu(user);
                        })
                    )
                  }
                }, (user: UserAccountModel) => `${user.id}`)
              }
            }
            .width('100%')
            .height('100%')
            .padding({ left: 14, right: 14, top: 4, bottom: 24 })
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
