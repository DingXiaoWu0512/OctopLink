import { AdminService } from '../../service/AdminService';
import { OctopApiError } from '../../net/HttpClient';
import { PageHeader } from '../../components/PageHeader';
import { ErrorRetry } from '../../components/ErrorRetry';
import { UiMaterialKit } from '../../components/UiMaterialKit';
import { JsonHelper } from '../../utils/JsonHelper';

/** 粗略格式化 JSON/键值文本用于只读展示：逗号/花括号换行，截断超长值 */
function prettyAdminText(raw: string, maxLen: number): string {
  let text: string = raw.trim();
  if (text === '') {
    return '（空）';
  }
  text = text.replace(/,/g, ',\n').replace(/\{/g, '{\n  ').replace(/\}/g, '\n}');
  if (text.length > maxLen) {
    text = `${text.substring(0, maxLen)}\n...（已截断）`;
  }
  return text;
}

/** 管理端运维页：备份 / 服务更新 / 安全策略 / 环境变量 / 可观测 / TLS / 全局用量（只读+关键动作） */
@Component
export struct AdminOpsPage {
  @State loading: boolean = true;
  @State errorMsg: string = '';
  @State operating: boolean = false;

  @State backupStatusText: string = '';
  @State backupListText: string = '';
  @State backupFiles: string[] = [];
  @State updateStatusText: string = '';
  @State securityText: string = '';
  @State envsText: string = '';
  @State langfuseText: string = '';
  @State tlsText: string = '';
  @State usageText: string = '';

  private pathStack: NavPathStack | null = null;

  onNavReady(ctx: NavDestinationContext): void {
    this.pathStack = ctx.pathStack;
    this.loadAll();
  }

  private async loadAll(): Promise<void> {
    this.loading = true;
    this.errorMsg = '';
    const fail = (label: string, e: Object): string => {
      const message: string = e instanceof OctopApiError ? e.message : '加载失败';
      return `${label}不可用：${message}`;
    };
    try {
      try {
        this.backupStatusText = prettyAdminText(await AdminService.backupStatus(), 400);
      } catch (e) {
        this.backupStatusText = fail('备份状态', e);
      }
      await this.loadBackups();
      try {
        this.updateStatusText = prettyAdminText(await AdminService.updateStatus(), 500);
      } catch (e) {
        this.updateStatusText = fail('服务更新', e);
      }
      try {
        this.securityText = prettyAdminText(await AdminService.securityGet(), 1200);
      } catch (e) {
        this.securityText = fail('安全策略', e);
      }
      try {
        this.envsText = prettyAdminText(await AdminService.envsList(), 1200);
      } catch (e) {
        this.envsText = fail('环境变量', e);
      }
      try {
        this.langfuseText = prettyAdminText(await AdminService.langfuseGet(), 400);
      } catch (e) {
        this.langfuseText = fail('Langfuse', e);
      }
      try {
        this.tlsText = prettyAdminText(await AdminService.tlsStatus(), 600);
      } catch (e) {
        this.tlsText = fail('TLS', e);
      }
      try {
        this.usageText = prettyAdminText(await AdminService.usageSummary('', '', 0, ''), 800);
      } catch (e) {
        this.usageText = fail('全局用量', e);
      }
    } finally {
      this.loading = false;
    }
  }

  private async loadBackups(): Promise<void> {
    try {
      const raw: string = await AdminService.backupList();
      this.backupListText = prettyAdminText(raw, 1600);
      const rec = JsonHelper.parse(raw);
      const names: string[] = [];
      if (rec !== null) {
        let items = JsonHelper.getRecordArray(rec, 'files');
        if (items.length === 0) {
          items = JsonHelper.getRecordArray(rec, 'backups');
        }
        if (items.length === 0) {
          items = JsonHelper.getRecordArray(rec, 'items');
        }
        for (const item of items) {
          const name: string = JsonHelper.getString(item, 'filename',
            JsonHelper.getString(item, 'name', ''));
          if (name !== '') {
            names.push(name);
          }
        }
      }
      this.backupFiles = names;
    } catch (e) {
      this.backupListText = `备份列表不可用：${e instanceof OctopApiError ? e.message : '加载失败'}`;
      this.backupFiles = [];
    }
  }

  private async createBackup(): Promise<void> {
    if (this.operating) {
      return;
    }
    this.operating = true;
    try {
      await AdminService.backupCreate('{}');
      this.getUIContext().getPromptAction().showToast({ message: '备份已创建' });
      await this.loadBackups();
    } catch (e) {
      const message: string = e instanceof OctopApiError ? e.message : '创建备份失败';
      this.getUIContext().getPromptAction().showToast({ message });
    } finally {
      this.operating = false;
    }
  }

  private async restoreBackup(filename: string): Promise<void> {
    if (this.operating) {
      return;
    }
    this.operating = true;
    try {
      await AdminService.backupRestore(filename, false);
      this.getUIContext().getPromptAction().showToast({ message: '已开始恢复，稍后请刷新' });
    } catch (e) {
      const message: string = e instanceof OctopApiError ? e.message : '恢复失败';
      this.getUIContext().getPromptAction().showToast({ message });
    } finally {
      this.operating = false;
    }
  }

  private async deleteBackup(filename: string): Promise<void> {
    if (this.operating) {
      return;
    }
    this.operating = true;
    try {
      await AdminService.backupDelete(filename);
      this.getUIContext().getPromptAction().showToast({ message: '备份已删除' });
      await this.loadBackups();
    } catch (e) {
      const message: string = e instanceof OctopApiError ? e.message : '删除失败';
      this.getUIContext().getPromptAction().showToast({ message });
    } finally {
      this.operating = false;
    }
  }

  private async checkUpdate(): Promise<void> {
    if (this.operating) {
      return;
    }
    this.operating = true;
    try {
      const text: string = await AdminService.updateCheck();
      this.updateStatusText = prettyAdminText(text, 500);
      this.getUIContext().getPromptAction().showToast({ message: '检查完成' });
    } catch (e) {
      const message: string = e instanceof OctopApiError ? e.message : '检查更新失败';
      this.getUIContext().getPromptAction().showToast({ message });
    } finally {
      this.operating = false;
    }
  }

  private async restartService(): Promise<void> {
    if (this.operating) {
      return;
    }
    this.operating = true;
    try {
      await AdminService.updateRestart();
      this.getUIContext().getPromptAction().showToast({ message: '已下发重启指令' });
    } catch (e) {
      const message: string = e instanceof OctopApiError ? e.message : '重启失败';
      this.getUIContext().getPromptAction().showToast({ message });
    } finally {
      this.operating = false;
    }
  }

  build() {
    NavDestination() {
      Column() {
        PageHeader({ title: '运维管理' })

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
                this.loadAll();
              }
            })
          }
          .layoutWeight(1)
          .width('100%')
          .justifyContent(FlexAlign.Center)
        } else {
          Scroll() {
            Column({ space: 14 }) {
              // 备份
              Column({ space: 10 }) {
                Text('备份')
                  .fontSize(15)
                  .fontWeight(FontWeight.Medium)
                  .fontColor($r('app.color.text_primary'))
                Text(this.backupStatusText)
                  .fontSize(12)
                  .fontColor($r('app.color.text_secondary'))
                  .width('100%')
                Row({ space: 10 }) {
                  Button(this.operating ? '处理中...' : '立即备份')
                    .fontSize(13)
                    .height(36)
                    .layoutWeight(1)
                    .borderRadius(18)
                    .backgroundColor($r('app.color.brand_light'))
                    .fontColor($r('app.color.brand'))
                    .enabled(!this.operating)
                    .onClick((): void => {
                      this.createBackup();
                    })
                  Button('刷新列表')
                    .fontSize(13)
                    .height(36)
                    .layoutWeight(1)
                    .borderRadius(18)
                    .backgroundColor($r('app.color.bg_input'))
                    .fontColor($r('app.color.text_secondary'))
                    .onClick((): void => {
                      this.loadBackups();
                    })
                }
                .width('100%')

                if (this.backupFiles.length > 0) {
                  ForEach(this.backupFiles, (f: string) => {
                    Row({ space: 8 }) {
                      Text(f)
                        .fontSize(12)
                        .fontColor($r('app.color.text_primary'))
                        .maxLines(1)
                        .textOverflow({ overflow: TextOverflow.Ellipsis })
                        .layoutWeight(1)
                      Text('恢复')
                        .fontSize(12)
                        .fontColor($r('app.color.brand'))
                        .padding(6)
                        .onClick((): void => {
                          this.restoreBackup(f);
                        })
                      Text('删除')
                        .fontSize(12)
                        .fontColor($r('app.color.danger'))
                        .padding(6)
                        .onClick((): void => {
                          this.deleteBackup(f);
                        })
                    }
                    .width('100%')
                    .padding({ left: 10, right: 6, top: 6, bottom: 6 })
                    .borderRadius(10)
                    .backgroundColor($r('app.color.bg_input'))
                  }, (f: string) => f)
                }
              }
              .width('100%')
              .padding(14)
              .borderRadius(16)
              .backgroundColor($r('app.color.bg_card'))
              .border({ width: 1, color: $r('app.color.card_stroke') })
              .alignItems(HorizontalAlign.Start)

              // 服务更新
              Column({ space: 10 }) {
                Text('服务更新')
                  .fontSize(15)
                  .fontWeight(FontWeight.Medium)
                  .fontColor($r('app.color.text_primary'))
                Text(this.updateStatusText)
                  .fontSize(12)
                  .fontColor($r('app.color.text_secondary'))
                  .width('100%')
                Row({ space: 10 }) {
                  Button('检查更新')
                    .fontSize(13)
                    .height(36)
                    .layoutWeight(1)
                    .borderRadius(18)
                    .backgroundColor($r('app.color.brand_light'))
                    .fontColor($r('app.color.brand'))
                    .enabled(!this.operating)
                    .onClick((): void => {
                      this.checkUpdate();
                    })
                  Button('重启服务')
                    .fontSize(13)
                    .height(36)
                    .layoutWeight(1)
                    .borderRadius(18)
                    .backgroundColor($r('app.color.bg_input'))
                    .fontColor($r('app.color.danger'))
                    .enabled(!this.operating)
                    .onClick((): void => {
                      this.restartService();
                    })
                }
                .width('100%')
              }
              .width('100%')
              .padding(14)
              .borderRadius(16)
              .backgroundColor($r('app.color.bg_card'))
              .border({ width: 1, color: $r('app.color.card_stroke') })
              .alignItems(HorizontalAlign.Start)

              this.readonlyCard('安全策略（命令守卫 / HITL / PII）', this.securityText)
              this.readonlyCard('全局环境变量', this.envsText)
              this.readonlyCard('Langfuse 可观测', this.langfuseText)
              this.readonlyCard('TLS 证书', this.tlsText)
              this.readonlyCard('全局用量', this.usageText)
            }
            .width('100%')
            .padding({ left: 14, right: 14, top: 8, bottom: 28 })
          }
          .layoutWeight(1)
          .width('100%')
          .scrollBar(BarState.Off)
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

  @Builder
  readonlyCard(title: string, body: string) {
    Column({ space: 8 }) {
      Text(title)
        .fontSize(15)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.text_primary'))
        .width('100%')
      Text(body)
        .fontSize(12)
        .fontColor($r('app.color.text_secondary'))
        .width('100%')
        .lineHeight(18)
        .fontFamily('monospace')
    }
    .width('100%')
    .padding(14)
    .borderRadius(16)
    .backgroundColor($r('app.color.bg_card'))
    .border({ width: 1, color: $r('app.color.card_stroke') })
    .alignItems(HorizontalAlign.Start)
  }
}
