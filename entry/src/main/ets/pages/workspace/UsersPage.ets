import { UserAccountModel, UserRoleModel } from '../../model/AuthModels';
import { UserRoleService, UserService } from '../../service/AuthService';
import { OctopApiError } from '../../net/HttpClient';
import { EmptyView } from '../../components/EmptyView';
import { ErrorRetry } from '../../components/ErrorRetry';
import { PageHeader } from '../../components/PageHeader';
import { UiMaterialKit } from '../../components/UiMaterialKit';
import { MenuSheetContent, MenuSheetOption } from '../../components/MenuSheet';

/** 用户管理：用户列表/创建/编辑/启停/解锁/重置密码/批量操作 + 角色模板管理（需 users 权限） */
@Component
export struct UsersPage {
  @State users: Array<UserAccountModel> = [];
  @State roles: Array<UserRoleModel> = [];
  @State loading: boolean = true;
  @State refreshing: boolean = false;
  @State errorMsg: string = '';
  @State operating: boolean = false;
  @State selectionMode: boolean = false;
  @State selectedIds: Array<number> = [];
  @State sheetOpen: boolean = false;
  @State sheetMode: string = '';
  // 创建表单
  @State cuUsername: string = '';
  @State cuPassword: string = '';
  @State cuRole: string = '';
  @State cuDisplayName: string = '';
  @State cuEmail: string = '';
  @State cuQuota: string = '';
  @State cuMaxAgents: string = '';
  // 编辑表单
  @State editing: UserAccountModel | null = null;
  @State edDisplayName: string = '';
  @State edRole: string = '';
  @State edEmail: string = '';
  // 重置密码
  @State resetTarget: UserAccountModel | null = null;
  @State resetText: string = '';
  // 角色表单（editing 为空 = 创建）
  @State roleEditing: UserRoleModel | null = null;
  @State roleNameText: string = '';
  @State roleIdText: string = '';
  @State roleDescText: string = '';
  // 批量数值输入（set_token_quota / set_max_agents）
  @State batchAction: string = '';
  @State batchText: string = '';
  // 菜单半模态
  @State menuOpen: boolean = false;
  @State menuTitle: string = '';
  @State menuMessage: string = '';
  @State menuOptions: Array<MenuSheetOption> = [];
  private menuActions: Array<() => void> = [];

  private onNavReady(ctx: NavDestinationContext): void {
    this.load();
  }

  private async load(): Promise<void> {
    this.loading = this.users.length === 0;
    this.errorMsg = '';
    try {
      this.users = await UserService.list();
    } catch (e) {
      this.errorMsg = e instanceof OctopApiError ? e.message : '用户列表加载失败';
      this.loading = false;
      return;
    }
    try {
      this.roles = await UserRoleService.list();
    } catch (e) {
      this.roles = [];
    }
    this.loading = false;
  }

  private toastError(e: Object, fallback: string): void {
    const message: string = e instanceof OctopApiError ? e.message : fallback;
    this.getUIContext().getPromptAction().showToast({ message });
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

  private exitSelection(): void {
    this.selectionMode = false;
    this.selectedIds = [];
  }

  private roleOptions(): Array<SelectOption> {
    const options: Array<SelectOption> = [];
    for (const role of this.roles) {
      options.push({ value: role.name === '' ? role.id : `${role.name} (${role.id})` });
    }
    return options;
  }

  private roleIndex(roleId: string): number {
    for (let i = 0; i < this.roles.length; i++) {
      if (this.roles[i].id === roleId) {
        return i;
      }
    }
    return -1;
  }

  private openCreate(): void {
    this.cuUsername = '';
    this.cuPassword = '';
    this.cuRole = this.roles.length > 0 ? this.roles[0].id : '';
    this.cuDisplayName = '';
    this.cuEmail = '';
    this.cuQuota = '';
    this.cuMaxAgents = '';
    this.sheetMode = 'create';
    this.sheetOpen = true;
  }

  private static parseOptionalInt(text: string): number | null {
    const trimmed: string = text.trim();
    if (trimmed === '') {
      return null;
    }
    const value: number = Number(trimmed);
    if (Number.isNaN(value) || value < 0) {
      return null;
    }
    return Math.floor(value);
  }

  private async submitCreate(): Promise<void> {
    if (this.operating) {
      return;
    }
    const username: string = this.cuUsername.trim();
    const password: string = this.cuPassword.trim();
    if (username === '' || password === '' || this.cuRole === '') {
      this.getUIContext().getPromptAction().showToast({ message: '请填写用户名、密码并选择角色' });
      return;
    }
    const quota: number | null = UsersPage.parseOptionalInt(this.cuQuota);
    const maxAgents: number | null = UsersPage.parseOptionalInt(this.cuMaxAgents);
    if (this.cuQuota.trim() !== '' && quota === null) {
      this.getUIContext().getPromptAction().showToast({ message: 'Token 配额须为非负整数' });
      return;
    }
    if (this.cuMaxAgents.trim() !== '' && maxAgents === null) {
      this.getUIContext().getPromptAction().showToast({ message: '最大专家数须为非负整数' });
      return;
    }
    this.operating = true;
    const body: Record<string, Object> = {
      'username': username,
      'password': password,
      'role': this.cuRole
    };
    if (this.cuDisplayName.trim() !== '') {
      body['display_name'] = this.cuDisplayName.trim();
    }
    if (this.cuEmail.trim() !== '') {
      body['email'] = this.cuEmail.trim();
    }
    if (quota !== null) {
      body['token_quota'] = quota;
    }
    if (maxAgents !== null) {
      body['max_agents'] = maxAgents;
    }
    try {
      await UserService.create(JSON.stringify(body));
      this.sheetOpen = false;
      this.getUIContext().getPromptAction().showToast({ message: '用户已创建' });
      await this.load();
    } catch (e) {
      this.toastError(e, '创建失败');
    } finally {
      this.operating = false;
    }
  }

  private openEdit(user: UserAccountModel): void {
    this.editing = user;
    this.edDisplayName = user.displayName === user.username ? '' : user.displayName;
    this.edRole = user.role;
    this.edEmail = user.email;
    this.sheetMode = 'edit';
    this.sheetOpen = true;
  }

  private async submitEdit(): Promise<void> {
    if (this.operating || this.editing === null) {
      return;
    }
    if (this.edRole === '') {
      this.getUIContext().getPromptAction().showToast({ message: '请选择角色' });
      return;
    }
    this.operating = true;
    const body: Record<string, Object> = {
      'role': this.edRole,
      'display_name': this.edDisplayName.trim(),
      'email': this.edEmail.trim()
    };
    try {
      await UserService.patch(this.editing.id, JSON.stringify(body));
      this.sheetOpen = false;
      this.getUIContext().getPromptAction().showToast({ message: '已保存' });
      await this.load();
    } catch (e) {
      this.toastError(e, '保存失败');
    } finally {
      this.operating = false;
    }
  }

  private openReset(user: UserAccountModel): void {
    this.resetTarget = user;
    this.resetText = '';
    this.sheetMode = 'reset';
    this.sheetOpen = true;
  }

  private async submitReset(): Promise<void> {
    if (this.operating || this.resetTarget === null) {
      return;
    }
    const password: string = this.resetText.trim();
    if (password === '') {
      this.getUIContext().getPromptAction().showToast({ message: '请输入新密码' });
      return;
    }
    this.operating = true;
    try {
      await UserService.resetPassword(this.resetTarget.id, password);
      this.sheetOpen = false;
      this.getUIContext().getPromptAction().showToast({ message: '密码已重置' });
    } catch (e) {
      this.toastError(e, '重置失败');
    } finally {
      this.operating = false;
    }
  }

  private showUserMenu(user: UserAccountModel): void {
    if (this.selectionMode) {
      return;
    }
    this.menuTitle = user.displayName;
    this.menuMessage = `@${user.username}`;
    this.menuOptions = [
      new MenuSheetOption($r('sys.symbol.person'), '编辑资料', '修改昵称、角色与配额', false),
      new MenuSheetOption(user.disabled ? $r('sys.symbol.checkmark_circle') : $r('sys.symbol.xmark_circle'),
        user.disabled ? '启用账号' : '停用账号', '', false),
      new MenuSheetOption($r('sys.symbol.key'), '重置密码', '', false),
      new MenuSheetOption($r('sys.symbol.trash'), '删除用户', '', true)
    ];
    this.menuActions = [
      (): void => {
        this.openEdit(user);
      },
      (): void => {
        this.toggleDisabled(user);
      },
      (): void => {
        this.openReset(user);
      },
      (): void => {
        this.confirmDeleteUser(user);
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

  private async toggleDisabled(user: UserAccountModel): Promise<void> {
    if (this.operating) {
      return;
    }
    this.operating = true;
    const body: Record<string, Object> = { 'disabled': !user.disabled };
    try {
      await UserService.patch(user.id, JSON.stringify(body));
      this.getUIContext().getPromptAction().showToast({ message: user.disabled ? '已启用' : '已停用' });
      await this.load();
    } catch (e) {
      this.toastError(e, '操作失败');
    } finally {
      this.operating = false;
    }
  }

  private confirmDeleteUser(user: UserAccountModel): void {
    this.getUIContext().showAlertDialog({
      title: '删除用户',
      message: `确定删除「${user.displayName}」吗？该操作不可恢复。`,
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
      await UserService.remove(user.id);
      this.getUIContext().getPromptAction().showToast({ message: '已删除' });
      await this.load();
    } catch (e) {
      this.toastError(e, '删除失败');
    } finally {
      this.operating = false;
    }
  }

  private showBatchMenu(): void {
    if (this.selectedIds.length === 0) {
      this.getUIContext().getPromptAction().showToast({ message: '请先选择用户' });
      return;
    }
    this.menuTitle = `已选 ${this.selectedIds.length} 位用户`;
    this.menuMessage = '选择批量操作';
    this.menuOptions = [
      new MenuSheetOption($r('sys.symbol.checkmark_circle'), '启用', '', false),
      new MenuSheetOption($r('sys.symbol.xmark_circle'), '停用', '', false),
      new MenuSheetOption($r('sys.symbol.slider_horizontal_2'), '设置 Token 配额', '留空为不限', false),
      new MenuSheetOption($r('sys.symbol.robot'), '设置最大专家数', '留空为不限', false),
      new MenuSheetOption($r('sys.symbol.trash'), '删除', '', true)
    ];
    this.menuActions = [
      (): void => {
        this.runBatch('enable');
      },
      (): void => {
        this.runBatch('disable');
      },
      (): void => {
        this.batchAction = 'set_token_quota';
        this.batchText = '';
        this.sheetMode = 'batch';
        this.sheetOpen = true;
      },
      (): void => {
        this.batchAction = 'set_max_agents';
        this.batchText = '';
        this.sheetMode = 'batch';
        this.sheetOpen = true;
      },
      (): void => {
        this.confirmBatchDelete();
      }
    ];
    this.menuOpen = true;
  }

  private confirmBatchDelete(): void {
    this.getUIContext().showAlertDialog({
      title: '批量删除',
      message: `确定删除已选的 ${this.selectedIds.length} 位用户吗？不可恢复。`,
      primaryButton: {
        value: $r('app.string.common_cancel'),
        action: (): void => {
        }
      },
      secondaryButton: {
        value: $r('app.string.common_confirm'),
        action: (): void => {
          this.runBatch('delete');
        }
      },
      alignment: DialogAlignment.Bottom
    });
  }

  private async runBatch(action: string, value: number | null = null): Promise<void> {
    if (this.operating) {
      return;
    }
    this.operating = true;
    try {
      if (action === 'set_token_quota') {
        await UserService.batch(this.selectedIds, action, value, null);
      } else if (action === 'set_max_agents') {
        await UserService.batch(this.selectedIds, action, null, value);
      } else {
        await UserService.batch(this.selectedIds, action);
      }
      this.getUIContext().getPromptAction().showToast({ message: '批量操作已执行' });
      this.exitSelection();
      await this.load();
    } catch (e) {
      this.toastError(e, '批量操作失败');
    } finally {
      this.operating = false;
    }
  }

  private submitBatchValue(): void {
    const parsed: number | null = UsersPage.parseOptionalInt(this.batchText);
    if (this.batchText.trim() !== '' && parsed === null) {
      this.getUIContext().getPromptAction().showToast({ message: '请输入非负整数（留空为不限）' });
      return;
    }
    this.sheetOpen = false;
    this.runBatch(this.batchAction, parsed);
  }

  private openRoleCreate(): void {
    this.roleEditing = null;
    this.roleNameText = '';
    this.roleIdText = '';
    this.roleDescText = '';
    this.sheetMode = 'role';
    this.sheetOpen = true;
  }

  private openRoleEdit(role: UserRoleModel): void {
    this.roleEditing = role;
    this.roleNameText = role.name;
    this.roleIdText = role.id;
    this.roleDescText = role.description;
    this.sheetMode = 'role';
    this.sheetOpen = true;
  }

  private showRoleMenu(role: UserRoleModel): void {
    this.menuTitle = role.name;
    this.menuMessage = role.id;
    this.menuOptions = [
      new MenuSheetOption($r('sys.symbol.square_and_pencil'), '编辑角色', '修改名称与描述', false),
      new MenuSheetOption($r('sys.symbol.trash'), '删除角色', '', true)
    ];
    this.menuActions = [
      (): void => {
        this.openRoleEdit(role);
      },
      (): void => {
        this.confirmDeleteRole(role);
      }
    ];
    this.menuOpen = true;
  }

  private async submitRole(): Promise<void> {
    if (this.operating) {
      return;
    }
    const name: string = this.roleNameText.trim();
    if (name === '') {
      this.getUIContext().getPromptAction().showToast({ message: '请填写角色名称' });
      return;
    }
    this.operating = true;
    try {
      if (this.roleEditing === null) {
        const body: Record<string, Object> = { 'user_role_name': name };
        if (this.roleIdText.trim() !== '') {
          body['user_role_id'] = this.roleIdText.trim();
        }
        if (this.roleDescText.trim() !== '') {
          body['description'] = this.roleDescText.trim();
        }
        await UserRoleService.create(JSON.stringify(body));
      } else {
        const body: Record<string, Object> = {
          'user_role_name': name,
          'description': this.roleDescText.trim()
        };
        await UserRoleService.patch(this.roleEditing.id, JSON.stringify(body));
      }
      this.sheetOpen = false;
      this.getUIContext().getPromptAction().showToast({ message: this.roleEditing === null ? '角色已创建' : '角色已保存' });
      await this.load();
    } catch (e) {
      this.toastError(e, '保存失败');
    } finally {
      this.operating = false;
    }
  }

  private confirmDeleteRole(role: UserRoleModel): void {
    this.getUIContext().showAlertDialog({
      title: '删除角色',
      message: `确定删除角色「${role.name}」吗？仍有用户使用时将失败。`,
      primaryButton: {
        value: $r('app.string.common_cancel'),
        action: (): void => {
        }
      },
      secondaryButton: {
        value: $r('app.string.common_confirm'),
        action: (): void => {
          this.deleteRole(role);
        }
      },
      alignment: DialogAlignment.Bottom
    });
  }

  private async deleteRole(role: UserRoleModel): Promise<void> {
    if (this.operating) {
      return;
    }
    this.operating = true;
    try {
      await UserRoleService.remove(role.id);
      this.getUIContext().getPromptAction().showToast({ message: '角色已删除' });
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
          PageHeader({ title: '用户管理' })

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
              List({ space: 10 }) {
                ListItem() {
                  Row() {
                    Text(`用户（${this.users.length}）`)
                      .fontSize(14)
                      .fontWeight(FontWeight.Bold)
                      .fontColor($r('app.color.text_primary'))
                      .layoutWeight(1)
                    Button(this.selectionMode ? '取消批量' : '批量操作')
                      .fontSize(12)
                      .height(30)
                      .borderRadius(15)
                      .backgroundColor($r('app.color.bg_input'))
                      .fontColor($r('app.color.text_secondary'))
                      .onClick((): void => {
                        if (this.selectionMode) {
                          this.exitSelection();
                        } else {
                          this.selectionMode = true;
                        }
                      })
                  }
                  .width('100%')
                }

                if (this.users.length === 0) {
                  ListItem() {
                    Column() {
                      EmptyView({
                        title: '暂无用户',
                        subtitle: '点击右下角按钮创建',
                        icon: $r('sys.symbol.person')
                      })
                    }
                    .width('100%')
                    .padding({ top: 10, bottom: 10 })
                  }
                } else {
                  ForEach(this.users, (user: UserAccountModel) => {
                    ListItem() {
                      Row({ space: 12 }) {
                        if (this.selectionMode) {
                          Column() {
                            if (this.isSelected(user.id)) {
                              SymbolGlyph($r('sys.symbol.checkmark'))
                                .fontSize(16)
                                .fontColor([$r('app.color.text_on_brand')])
                            }
                          }
                          .width(26)
                          .height(26)
                          .borderRadius(13)
                          .justifyContent(FlexAlign.Center)
                          .alignItems(HorizontalAlign.Center)
                          .backgroundColor(this.isSelected(user.id)
                            ? $r('app.color.brand') : $r('app.color.bg_input'))
                          .border({ width: 1, color: this.isSelected(user.id)
                            ? $r('app.color.brand') : $r('app.color.card_stroke') })
                        } else {
                          Column() {
                            Text(user.username.length > 0 ? user.username.substring(0, 1).toUpperCase() : '?')
                              .fontSize(15)
                              .fontWeight(FontWeight.Bold)
                              .fontColor($r('app.color.brand'))
                          }
                          .width(38)
                          .height(38)
                          .borderRadius(12)
                          .justifyContent(FlexAlign.Center)
                          .alignItems(HorizontalAlign.Center)
                          .backgroundColor($r('app.color.brand_light'))
                          .opacity(user.disabled ? 0.5 : 1)
                        }

                        Column({ space: 4 }) {
                          Row({ space: 6 }) {
                            Text(user.displayName)
                              .fontSize(15)
                              .fontWeight(FontWeight.Medium)
                              .fontColor(user.disabled
                                ? $r('app.color.text_tertiary') : $r('app.color.text_primary'))
                              .maxLines(1)
                              .textOverflow({ overflow: TextOverflow.Ellipsis })
                            Text(`@${user.username}`)
                              .fontSize(11)
                              .fontColor($r('app.color.text_secondary'))
                              .maxLines(1)
                              .textOverflow({ overflow: TextOverflow.Ellipsis })
                          }
                          .width('100%')
                          Row({ space: 6 }) {
                            Text(user.roleName === '' ? user.role : user.roleName)
                              .fontSize(10)
                              .fontColor($r('app.color.brand'))
                              .backgroundColor($r('app.color.brand_light'))
                              .borderRadius(5)
                              .padding({ left: 6, right: 6, top: 2, bottom: 2 })
                              .maxLines(1)
                            if (user.disabled) {
                              Text('已停用')
                                .fontSize(10)
                                .fontColor($r('app.color.danger'))
                                .backgroundColor($r('app.color.danger_soft'))
                                .borderRadius(5)
                                .padding({ left: 6, right: 6, top: 2, bottom: 2 })
                            }
                            if (user.loginLocked) {
                              Text('已锁定')
                                .fontSize(10)
                                .fontColor($r('app.color.warning'))
                                .backgroundColor($r('app.color.bg_input'))
                                .borderRadius(5)
                                .padding({ left: 6, right: 6, top: 2, bottom: 2 })
                            }
                            if (user.ssoLinked) {
                              Text('SSO')
                                .fontSize(10)
                                .fontColor($r('app.color.success'))
                                .backgroundColor($r('app.color.success_soft'))
                                .borderRadius(5)
                                .padding({ left: 6, right: 6, top: 2, bottom: 2 })
                            }
                          }
                          .width('100%')
                        }
                        .layoutWeight(1)
                        .alignItems(HorizontalAlign.Start)
                      }
                      .width('100%')
                      .padding(12)
                      .borderRadius(14)
                      .backgroundColor($r('app.color.bg_card'))
                      .border({ width: 1, color: $r('app.color.card_stroke') })
                      .onClick((): void => {
                        if (this.selectionMode) {
                          this.toggleSelected(user.id);
                        }
                      })
                      .gesture(
                        LongPressGesture()
                          .onAction((event: GestureEvent): void => {
                            this.showUserMenu(user);
                          })
                      )
                    }
                  }, (user: UserAccountModel) => `${user.id}-${user.username}`)
                }

                ListItem() {
                  Row() {
                    Text(`角色（${this.roles.length}）`)
                      .fontSize(14)
                      .fontWeight(FontWeight.Bold)
                      .fontColor($r('app.color.text_primary'))
                      .layoutWeight(1)
                    Button('新建角色')
                      .fontSize(12)
                      .height(30)
                      .borderRadius(15)
                      .backgroundColor($r('app.color.bg_input'))
                      .fontColor($r('app.color.text_secondary'))
                      .onClick((): void => {
                        this.openRoleCreate();
                      })
                  }
                  .width('100%')
                  .margin({ top: 8 })
                }

                ForEach(this.roles, (role: UserRoleModel) => {
                  ListItem() {
                    Row({ space: 12 }) {
                      Column() {
                        SymbolGlyph($r('sys.symbol.gearshape'))
                          .fontSize(16)
                          .fontColor([$r('app.color.text_secondary')])
                      }
                      .width(32)
                      .height(32)
                      .justifyContent(FlexAlign.Center)
                      .alignItems(HorizontalAlign.Center)
                      .backgroundColor($r('app.color.bg_input'))
                      .borderRadius(10)

                      Column({ space: 3 }) {
                        Row({ space: 6 }) {
                          Text(role.name)
                            .fontSize(14)
                            .fontWeight(FontWeight.Medium)
                            .fontColor($r('app.color.text_primary'))
                            .maxLines(1)
                            .textOverflow({ overflow: TextOverflow.Ellipsis })
                          Text(role.id)
                            .fontSize(10)
                            .fontColor($r('app.color.text_secondary'))
                            .backgroundColor($r('app.color.bg_input'))
                            .borderRadius(5)
                            .padding({ left: 6, right: 6, top: 2, bottom: 2 })
                            .maxLines(1)
                        }
                        .width('100%')
                        if (role.description !== '') {
                          Text(role.description)
                            .fontSize(11)
                            .fontColor($r('app.color.text_tertiary'))
                            .maxLines(2)
                            .textOverflow({ overflow: TextOverflow.Ellipsis })
                        }
                      }
                      .layoutWeight(1)
                      .alignItems(HorizontalAlign.Start)
                    }
                    .width('100%')
                    .padding(10)
                    .borderRadius(14)
                    .backgroundColor($r('app.color.bg_card'))
                    .border({ width: 1, color: $r('app.color.card_stroke') })
                    .gesture(
                      LongPressGesture()
                        .onAction((event: GestureEvent): void => {
                          this.showRoleMenu(role);
                        })
                    )
                  }
                }, (role: UserRoleModel) => role.id)
              }
              .width('100%')
              .height('100%')
              .padding({ left: 14, right: 14, top: 4, bottom: 90 })
              .scrollBar(BarState.Off)
            }
            .layoutWeight(1)
            .width('100%')
            .onRefreshing((): void => {
              this.load();
            })
            .bindSheet($$this.sheetOpen, this.sheetSwitchBuilder, {
              systemMaterial: UiMaterialKit.sheet(),
              detents: [SheetSize.LARGE],
              showClose: true,
              onDisappear: (): void => {
                this.sheetMode = '';
              }
            })
          }
        }
        .width('100%')
        .height('100%')

        if (this.selectionMode) {
          Row({ space: 10 }) {
            Text(`已选 ${this.selectedIds.length} 人`)
              .fontSize(13)
              .fontWeight(FontWeight.Medium)
              .fontColor($r('app.color.text_primary'))
              .layoutWeight(1)
            Button('全选')
              .fontSize(13)
              .height(34)
              .borderRadius(17)
              .backgroundColor($r('app.color.bg_input'))
              .fontColor($r('app.color.text_secondary'))
              .onClick((): void => {
                const ids: Array<number> = [];
                for (const user of this.users) {
                  ids.push(user.id);
                }
                this.selectedIds = ids;
              })
            Button('操作')
              .fontSize(13)
              .height(34)
              .borderRadius(17)
              .linearGradient({
                angle: 140,
                colors: [[$r('app.color.brand_grad_start'), 0], [$r('app.color.brand_grad_end'), 1]]
              })
              .fontColor($r('app.color.text_on_brand'))
              .onClick((): void => {
                this.showBatchMenu();
              })
          }
          .width('100%')
          .padding({ left: 16, right: 16, top: 12, bottom: 12 })
          .backgroundColor($r('app.color.bg_card'))
          .border({ width: 1, color: $r('app.color.card_stroke') })
          .margin({ left: 14, right: 14, bottom: 14 })
          .borderRadius(18)
        } else {
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
            this.openCreate();
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

  /** 单 bindSheet 分发：create / edit / reset / role / batch */
  @Builder
  sheetSwitchBuilder() {
    if (this.sheetMode === 'create') {
      this.createBuilder()
    } else if (this.sheetMode === 'edit') {
      this.editBuilder()
    } else if (this.sheetMode === 'reset') {
      this.resetBuilder()
    } else if (this.sheetMode === 'role') {
      this.roleBuilder()
    } else if (this.sheetMode === 'batch') {
      this.batchValueBuilder()
    }
  }

  @Builder
  createBuilder() {
    Column({ space: 14 }) {
      Text('创建用户')
        .fontSize(17)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.text_primary'))
        .width('100%')

      TextInput({
        text: this.cuUsername,
        placeholder: '用户名 *'
      })
        .fontSize(14)
        .height(42)
        .backgroundColor($r('app.color.bg_input'))
        .borderRadius(12)
        .onChange((value: string): void => {
          this.cuUsername = value;
        })

      TextInput({
        text: this.cuPassword,
        placeholder: '密码 *'
      })
        .fontSize(14)
        .height(42)
        .backgroundColor($r('app.color.bg_input'))
        .borderRadius(12)
        .type(InputType.Password)
        .onChange((value: string): void => {
          this.cuPassword = value;
        })

      Column({ space: 5 }) {
        Text('角色 *')
          .fontSize(12)
          .fontColor($r('app.color.text_tertiary'))
          .width('100%')
        Select(this.roleOptions())
          .selected(this.roleIndex(this.cuRole))
          .value(this.cuRole === '' ? '请选择角色' : this.cuRole)
          .fontColor($r('app.color.text_primary'))
          .font({ size: 14 })
          .backgroundColor(Color.Transparent)
          .borderRadius(12)
          .width('100%')
          .systemMaterial(UiMaterialKit.button())
          .menuSystemMaterial(UiMaterialKit.sheet())
          .onSelect((index: number, value: string): void => {
            if (index >= 0 && index < this.roles.length) {
              this.cuRole = this.roles[index].id;
            }
          })
      }
      .width('100%')

      TextInput({
        text: this.cuDisplayName,
        placeholder: '显示名称（可选）'
      })
        .fontSize(14)
        .height(42)
        .backgroundColor($r('app.color.bg_input'))
        .borderRadius(12)
        .onChange((value: string): void => {
          this.cuDisplayName = value;
        })

      TextInput({
        text: this.cuEmail,
        placeholder: '邮箱（可选）'
      })
        .fontSize(14)
        .height(42)
        .backgroundColor($r('app.color.bg_input'))
        .borderRadius(12)
        .onChange((value: string): void => {
          this.cuEmail = value;
        })

      Row({ space: 12 }) {
        Column({ space: 5 }) {
          Text('Token 配额')
            .fontSize(12)
            .fontColor($r('app.color.text_tertiary'))
            .width('100%')
          TextInput({
            text: this.cuQuota,
            placeholder: '不限'
          })
            .fontSize(14)
            .height(42)
            .backgroundColor($r('app.color.bg_input'))
            .borderRadius(12)
            .type(InputType.Number)
            .onChange((value: string): void => {
              this.cuQuota = value;
            })
        }
        .layoutWeight(1)

        Column({ space: 5 }) {
          Text('最大专家数')
            .fontSize(12)
            .fontColor($r('app.color.text_tertiary'))
            .width('100%')
          TextInput({
            text: this.cuMaxAgents,
            placeholder: '不限'
          })
            .fontSize(14)
            .height(42)
            .backgroundColor($r('app.color.bg_input'))
            .borderRadius(12)
            .type(InputType.Number)
            .onChange((value: string): void => {
              this.cuMaxAgents = value;
            })
        }
        .layoutWeight(1)
      }
      .width('100%')

      Button(this.operating ? '创建中...' : '创建')
        .fontSize(14)
        .height(42)
        .borderRadius(21)
        .width('100%')
        .linearGradient({
          angle: 140,
          colors: [[$r('app.color.brand_grad_start'), 0], [$r('app.color.brand_grad_end'), 1]]
        })
        .fontColor($r('app.color.text_on_brand'))
        .enabled(!this.operating)
        .onClick((): void => {
          this.submitCreate();
        })
    }
    .padding({ left: 20, right: 20, top: 20, bottom: 30 })
    .width('100%')
  }

  @Builder
  editBuilder() {
    Column({ space: 14 }) {
      Text(`编辑：${this.editing === null ? '' : this.editing.username}`)
        .fontSize(17)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.text_primary'))
        .width('100%')

      TextInput({
        text: this.edDisplayName,
        placeholder: '显示名称'
      })
        .fontSize(14)
        .height(42)
        .backgroundColor($r('app.color.bg_input'))
        .borderRadius(12)
        .onChange((value: string): void => {
          this.edDisplayName = value;
        })

      Column({ space: 5 }) {
        Text('角色')
          .fontSize(12)
          .fontColor($r('app.color.text_tertiary'))
          .width('100%')
        Select(this.roleOptions())
          .selected(this.roleIndex(this.edRole))
          .value(this.edRole === '' ? '请选择角色' : this.edRole)
          .fontColor($r('app.color.text_primary'))
          .font({ size: 14 })
          .backgroundColor($r('app.color.bg_input'))
          .borderRadius(12)
          .width('100%')
          .onSelect((index: number, value: string): void => {
            if (index >= 0 && index < this.roles.length) {
              this.edRole = this.roles[index].id;
            }
          })
      }
      .width('100%')

      TextInput({
        text: this.edEmail,
        placeholder: '邮箱'
      })
        .fontSize(14)
        .height(42)
        .backgroundColor($r('app.color.bg_input'))
        .borderRadius(12)
        .onChange((value: string): void => {
          this.edEmail = value;
        })

      Button(this.operating ? '保存中...' : '保存')
        .fontSize(14)
        .height(42)
        .borderRadius(21)
        .width('100%')
        .linearGradient({
          angle: 140,
          colors: [[$r('app.color.brand_grad_start'), 0], [$r('app.color.brand_grad_end'), 1]]
        })
        .fontColor($r('app.color.text_on_brand'))
        .enabled(!this.operating)
        .onClick((): void => {
          this.submitEdit();
        })
    }
    .padding({ left: 20, right: 20, top: 20, bottom: 30 })
    .width('100%')
  }

  @Builder
  resetBuilder() {
    Column({ space: 14 }) {
      Text(`重置密码：${this.resetTarget === null ? '' : this.resetTarget.username}`)
        .fontSize(17)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.text_primary'))
        .width('100%')

      TextInput({
        text: this.resetText,
        placeholder: '新密码'
      })
        .fontSize(14)
        .height(42)
        .backgroundColor($r('app.color.bg_input'))
        .borderRadius(12)
        .type(InputType.Password)
        .onChange((value: string): void => {
          this.resetText = value;
        })

      Button(this.operating ? '重置中...' : '确认重置')
        .fontSize(14)
        .height(42)
        .borderRadius(21)
        .width('100%')
        .linearGradient({
          angle: 140,
          colors: [[$r('app.color.brand_grad_start'), 0], [$r('app.color.brand_grad_end'), 1]]
        })
        .fontColor($r('app.color.text_on_brand'))
        .enabled(!this.operating)
        .onClick((): void => {
          this.submitReset();
        })
    }
    .padding({ left: 20, right: 20, top: 20, bottom: 30 })
    .width('100%')
  }

  @Builder
  roleBuilder() {
    Column({ space: 14 }) {
      Text(this.roleEditing === null ? '新建角色' : `编辑角色：${this.roleEditing.name}`)
        .fontSize(17)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.text_primary'))
        .width('100%')

      TextInput({
        text: this.roleNameText,
        placeholder: '角色名称 *'
      })
        .fontSize(14)
        .height(42)
        .backgroundColor($r('app.color.bg_input'))
        .borderRadius(12)
        .onChange((value: string): void => {
          this.roleNameText = value;
        })

      if (this.roleEditing === null) {
        TextInput({
          text: this.roleIdText,
          placeholder: '角色 ID（可选，字母/下划线，缺省自动分配）'
        })
          .fontSize(14)
          .height(42)
          .backgroundColor($r('app.color.bg_input'))
          .borderRadius(12)
          .onChange((value: string): void => {
            this.roleIdText = value;
          })
      }

      TextArea({
        text: this.roleDescText,
        placeholder: '角色描述（可选）'
      })
        .fontSize(14)
        .height(80)
        .backgroundColor($r('app.color.bg_input'))
        .borderRadius(12)
        .onChange((value: string): void => {
          this.roleDescText = value;
        })

      Button(this.operating ? '保存中...' : '保存')
        .fontSize(14)
        .height(42)
        .borderRadius(21)
        .width('100%')
        .linearGradient({
          angle: 140,
          colors: [[$r('app.color.brand_grad_start'), 0], [$r('app.color.brand_grad_end'), 1]]
        })
        .fontColor($r('app.color.text_on_brand'))
        .enabled(!this.operating)
        .onClick((): void => {
          this.submitRole();
        })
    }
    .padding({ left: 20, right: 20, top: 20, bottom: 30 })
    .width('100%')
  }

  @Builder
  batchValueBuilder() {
    Column({ space: 14 }) {
      Text(this.batchAction === 'set_token_quota' ? '设置 Token 配额' : '设置最大专家数')
        .fontSize(17)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.text_primary'))
        .width('100%')

      Text(`将应用到已选的 ${this.selectedIds.length} 位用户`)
        .fontSize(12)
        .fontColor($r('app.color.text_tertiary'))
        .width('100%')

      TextInput({
        text: this.batchText,
        placeholder: '非负整数，留空为不限'
      })
        .fontSize(14)
        .height(42)
        .backgroundColor($r('app.color.bg_input'))
        .borderRadius(12)
        .type(InputType.Number)
        .onChange((value: string): void => {
          this.batchText = value;
        })

      Button(this.operating ? '执行中...' : '确认')
        .fontSize(14)
        .height(42)
        .borderRadius(21)
        .width('100%')
        .linearGradient({
          angle: 140,
          colors: [[$r('app.color.brand_grad_start'), 0], [$r('app.color.brand_grad_end'), 1]]
        })
        .fontColor($r('app.color.text_on_brand'))
        .enabled(!this.operating)
        .onClick((): void => {
          this.submitBatchValue();
        })
    }
    .padding({ left: 20, right: 20, top: 20, bottom: 30 })
    .width('100%')
  }
}
