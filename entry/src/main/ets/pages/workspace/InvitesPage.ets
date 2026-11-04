import { InviteModel } from '../../model/InviteModels';
import { InviteService } from '../../service/InviteService';
import { OctopApiError } from '../../net/HttpClient';
import { EmptyView } from '../../components/EmptyView';
import { ErrorRetry } from '../../components/ErrorRetry';
import { InviteCreateDialog } from '../../components/InviteCreateDialog';
import { TimeFormat } from '../../utils/TimeFormat';
import { PageHeader } from '../../components/PageHeader';
import { UiMaterialKit } from '../../components/UiMaterialKit';
import { pasteboard } from '@kit.BasicServicesKit';
import { MenuSheetContent, MenuSheetOption } from '../../components/MenuSheet';

/** 邀请码管理：一次性用户邀请码列表（状态/过期时间）+ 创建/复制/吊销 */
@Component
export struct InvitesPage {
  @State invites: Array<InviteModel> = [];
  @State loading: boolean = true;
  @State refreshing: boolean = false;
  @State errorMsg: string = '';
  @State operating: boolean = false;
  @State menuOpen: boolean = false;
  @State menuTitle: string = '';
  @State menuMessage: string = '';
  @State menuOptions: Array<MenuSheetOption> = [];
  private menuActions: Array<() => void> = [];
  private pathStack: NavPathStack | null = null;
  private createController: CustomDialogController | null = null;

  onNavReady(ctx: NavDestinationContext): void {
    this.pathStack = ctx.pathStack;
    this.load(false);
  }

  private async load(silent: boolean): Promise<void> {
    if (!silent) {
      this.loading = true;
    }
    this.errorMsg = '';
    try {
      this.invites = await InviteService.list();
    } catch (e) {
      this.errorMsg = e instanceof OctopApiError ? e.message : '邀请码加载失败';
    } finally {
      this.loading = false;
      this.refreshing = false;
    }
  }

  private showCreate(): void {
    this.createController = new CustomDialogController({
      builder: InviteCreateDialog({
        onSaved: (): void => {
          this.load(false);
        }
      }),
      autoCancel: true,
      systemMaterial: UiMaterialKit.sheet()
    });
    this.createController.open();
  }

  private showInviteMenu(invite: InviteModel): void {
    const options: Array<MenuSheetOption> = [
      new MenuSheetOption($r('sys.symbol.doc_text'), '复制邀请码', invite.code, false),
      new MenuSheetOption($r('sys.symbol.link'), '复制邀请链接', '', false)
    ];
    const actions: Array<() => void> = [
      (): void => {
        this.copyText(invite.code, '邀请码已复制');
      },
      (): void => {
        this.copyText(invite.inviteUrl, '邀请链接已复制');
      }
    ];
    if (invite.status === 'pending') {
      options.push(new MenuSheetOption($r('sys.symbol.xmark_circle'), '吊销', '吊销后不可恢复', true));
      actions.push((): void => {
        this.confirmRevoke(invite);
      });
    }
    this.menuTitle = invite.code;
    this.menuMessage = '选择操作';
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

  private async copyText(text: string, hint: string): Promise<void> {
    if (text === '') {
      return;
    }
    try {
      const board = pasteboard.getSystemPasteboard();
      const data = pasteboard.createData(pasteboard.MIMETYPE_TEXT_PLAIN, text);
      await board.setData(data);
      this.getUIContext().getPromptAction().showToast({ message: hint });
    } catch (e) {
    }
  }

  private confirmRevoke(invite: InviteModel): void {
    this.getUIContext().showAlertDialog({
      title: '吊销邀请码',
      message: `确定吊销「${invite.code}」吗？吊销后不可恢复`,
      primaryButton: {
        value: $r('app.string.common_cancel'),
        action: (): void => {
        }
      },
      secondaryButton: {
        value: $r('app.string.common_confirm'),
        action: (): void => {
          this.revokeInvite(invite);
        }
      },
      alignment: DialogAlignment.Bottom
    });
  }

  private async revokeInvite(invite: InviteModel): Promise<void> {
    if (this.operating) {
      return;
    }
    this.operating = true;
    try {
      await InviteService.revoke(invite.id);
      this.getUIContext().getPromptAction().showToast({ message: '已吊销' });
      await this.load(true);
    } catch (e) {
      const message: string = e instanceof OctopApiError ? e.message : '吊销失败';
      this.getUIContext().getPromptAction().showToast({ message });
    } finally {
      this.operating = false;
    }
  }

  build() {
    NavDestination() {
      Stack({ alignContent: Alignment.BottomEnd }) {
        Column() {
          PageHeader({ title: '邀请码' })

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
                  this.load(false);
                }
              })
            }
            .layoutWeight(1)
            .width('100%')
            .justifyContent(FlexAlign.Center)
          } else if (this.invites.length === 0) {
            Column() {
              EmptyView({
                title: '暂无邀请码',
                subtitle: '点击右下角按钮创建',
                icon: $r('sys.symbol.paperplane')
              })
            }
            .layoutWeight(1)
            .width('100%')
            .justifyContent(FlexAlign.Center)
          } else {
            Refresh({ refreshing: $$this.refreshing }) {
              List({ space: 12 }) {
                ForEach(this.invites, (invite: InviteModel) => {
                  ListItem() {
                    Row({ space: 12 }) {
                      Column() {
                        SymbolGlyph($r('sys.symbol.paperplane'))
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
                          Text(invite.code)
                            .fontSize(16)
                            .fontWeight(FontWeight.Medium)
                            .fontColor($r('app.color.text_primary'))
                            .maxLines(1)
                            .textOverflow({ overflow: TextOverflow.Ellipsis })
                            .layoutWeight(1)
                          Text(invite.statusText())
                            .fontSize(11)
                            .fontColor(invite.status === 'pending'
                              ? $r('app.color.brand')
                              : invite.status === 'used'
                              ? $r('app.color.success')
                              : invite.status === 'revoked'
                              ? $r('app.color.warning')
                              : $r('app.color.text_tertiary'))
                            .backgroundColor(invite.status === 'pending'
                              ? $r('app.color.brand_light')
                              : invite.status === 'used'
                              ? $r('app.color.success_soft')
                              : invite.status === 'revoked'
                              ? $r('app.color.warning_soft')
                              : $r('app.color.bg_input'))
                            .borderRadius(6)
                            .padding({ left: 8, right: 8, top: 3, bottom: 3 })
                        }
                        .width('100%')

                        if (invite.note !== '') {
                          Text(invite.note)
                            .fontSize(13)
                            .fontColor($r('app.color.text_secondary'))
                            .maxLines(1)
                            .textOverflow({ overflow: TextOverflow.Ellipsis })
                            .width('100%')
                        }

                        Row({ space: 8 }) {
                          SymbolGlyph($r('sys.symbol.timer'))
                            .fontSize(12)
                            .fontColor([$r('app.color.text_tertiary')])
                          if (invite.status === 'used' && invite.usedAtMs > 0) {
                            Text(`使用于 ${TimeFormat.full(invite.usedAtMs)}`)
                              .fontSize(11)
                              .fontColor($r('app.color.text_tertiary'))
                              .maxLines(1)
                          } else {
                            Text(`${TimeFormat.full(invite.expiresAtMs)} 过期`)
                              .fontSize(11)
                              .fontColor($r('app.color.text_tertiary'))
                              .maxLines(1)
                          }
                          if (invite.revokedAtMs > 0) {
                            Text(`吊销于 ${TimeFormat.list(invite.revokedAtMs)}`)
                              .fontSize(11)
                              .fontColor($r('app.color.text_tertiary'))
                              .maxLines(1)
                          }
                          if (invite.roleName !== '') {
                            Text(`角色 ${invite.roleName}`)
                              .fontSize(11)
                              .fontColor($r('app.color.text_tertiary'))
                              .maxLines(1)
                              .textOverflow({ overflow: TextOverflow.Ellipsis })
                          }
                          Blank()
                          Row({ space: 4 }) {
                            SymbolGlyph($r('sys.symbol.doc_text'))
                              .fontSize(12)
                              .fontColor([$r('app.color.brand')])
                            Text('复制')
                              .fontSize(12)
                              .fontWeight(FontWeight.Medium)
                              .fontColor($r('app.color.brand'))
                          }
                          .onClick((): void => {
                            this.copyText(invite.code, '邀请码已复制');
                          })
                        }
                        .width('100%')

                        if (invite.inviteUrl !== '') {
                          Text(invite.inviteUrl)
                            .fontSize(11)
                            .fontColor($r('app.color.text_tertiary'))
                            .maxLines(1)
                            .textOverflow({ overflow: TextOverflow.Ellipsis })
                            .width('100%')
                        }
                      }
                      .layoutWeight(1)
                      .alignItems(HorizontalAlign.Start)
                    }
                    .width('100%')
                    .padding({ left: 14, right: 14, top: 14, bottom: 14 })
                    .borderRadius(16)
                    .backgroundColor($r('app.color.bg_card'))
                    .onClick((): void => {
                      this.showInviteMenu(invite);
                    })
                  }
                }, (invite: InviteModel) => `${invite.id}`)
              }
              .width('100%')
              .height('100%')
              .padding({ left: 14, right: 14, top: 4 })
              .scrollBar(BarState.Off)
            }
            .layoutWeight(1)
            .width('100%')
            .onRefreshing((): void => {
              this.load(true);
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
