import { HitlSettings, MobileCapability } from '../../model/WorkspaceModels';
import { SettingsService } from '../../service/WorkspaceService';
import { PageHeader } from '../../components/PageHeader';
import { ExpandableCard } from '../../components/ExpandableCard';
import { SettingsRow } from '../../components/SettingsRow';

/** 服务器设置（只读展示：时区/上传上限/HITL/移动端能力，分组可展开收起） */
@Component
export struct SettingsPage {
  @State loading: boolean = true;
  @State timezone: string = '…';
  @State uploadLimit: string = '…';
  @State hitlEnabled: string = '…';
  @State hitlGuard: string = '…';
  @State hitlApprovalUi: string = '…';
  @State mobileStatus: string = '…';

  private static readonly FAILED: string = '获取失败';

  private async load(): Promise<void> {
    this.loading = true;
    try {
      const tz: string = await SettingsService.getTimezone();
      this.timezone = tz === '' ? SettingsPage.FAILED : tz;
    } catch (e) {
      this.timezone = SettingsPage.FAILED;
    }
    try {
      const mb: number = await SettingsService.getMaxUploadMb();
      this.uploadLimit = mb > 0 ? `${mb} MiB` : SettingsPage.FAILED;
    } catch (e) {
      this.uploadLimit = SettingsPage.FAILED;
    }
    try {
      const hitl: HitlSettings = await SettingsService.getHitl();
      this.hitlEnabled = hitl.enabled ? '已启用' : '未启用';
      this.hitlGuard = hitl.toolGuardRequireApproval ? '需要' : '不需要';
      this.hitlApprovalUi = hitl.showApprovalUi ? '显示' : '隐藏';
    } catch (e) {
      this.hitlEnabled = SettingsPage.FAILED;
      this.hitlGuard = SettingsPage.FAILED;
      this.hitlApprovalUi = SettingsPage.FAILED;
    }
    try {
      const mobile: MobileCapability = await SettingsService.getMobileCapability();
      this.mobileStatus = mobile.enabled ? `已启用（${mobile.backend}）` : '未启用';
    } catch (e) {
      this.mobileStatus = SettingsPage.FAILED;
    }
    this.loading = false;
  }

  @Builder
  basicRows() {
    SettingsRow({
      icon: $r('sys.symbol.clock'),
      title: '服务器时区',
      trailing: this.timezone,
      trailingFailed: this.timezone === SettingsPage.FAILED,
      showChevron: false
    })
    Divider()
      .color($r('app.color.divider'))
      .margin({ left: 62 })
    SettingsRow({
      icon: $r('sys.symbol.paperclip'),
      title: '上传大小上限',
      trailing: this.uploadLimit,
      trailingFailed: this.uploadLimit === SettingsPage.FAILED,
      showChevron: false
    })
  }

  @Builder
  hitlRows() {
    SettingsRow({
      icon: $r('sys.symbol.face_smiling'),
      title: '人工审批',
      trailing: this.hitlEnabled,
      trailingFailed: this.hitlEnabled === SettingsPage.FAILED,
      showChevron: false
    })
    Divider()
      .color($r('app.color.divider'))
      .margin({ left: 62 })
    SettingsRow({
      icon: $r('sys.symbol.lock'),
      iconColor: $r('app.color.warning'),
      iconBg: $r('app.color.warning_soft'),
      title: '工具防护需审批',
      trailing: this.hitlGuard,
      trailingFailed: this.hitlGuard === SettingsPage.FAILED,
      showChevron: false
    })
    Divider()
      .color($r('app.color.divider'))
      .margin({ left: 62 })
    SettingsRow({
      icon: $r('sys.symbol.eye'),
      iconColor: $r('app.color.success'),
      iconBg: $r('app.color.success_soft'),
      title: '审批界面',
      trailing: this.hitlApprovalUi,
      trailingFailed: this.hitlApprovalUi === SettingsPage.FAILED,
      showChevron: false
    })
  }

  @Builder
  mobileRows() {
    SettingsRow({
      icon: $r('sys.symbol.dot_radiowaves_left_and_right'),
      iconColor: $r('app.color.success'),
      iconBg: $r('app.color.success_soft'),
      title: '远程移动端',
      trailing: this.mobileStatus,
      trailingFailed: this.mobileStatus === SettingsPage.FAILED,
      showChevron: false
    })
  }

  build() {
    NavDestination() {
      Column() {
        PageHeader({ title: '服务器设置' })

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
        } else {
          Scroll() {
            Column({ space: 12 }) {
              ExpandableCard({
                icon: $r('sys.symbol.gearshape'),
                title: '基本',
                subtitle: '服务器时区与上传限制',
                content: (): void => {
                  this.basicRows();
                }
              })
              ExpandableCard({
                icon: $r('sys.symbol.face_smiling'),
                iconColor: $r('app.color.warning'),
                iconBg: $r('app.color.warning_soft'),
                title: '人工审批（HITL）',
                subtitle: '审批开关与界面行为',
                content: (): void => {
                  this.hitlRows();
                }
              })
              ExpandableCard({
                icon: $r('sys.symbol.dot_radiowaves_left_and_right'),
                iconColor: $r('app.color.success'),
                iconBg: $r('app.color.success_soft'),
                title: '移动端能力',
                subtitle: '远程移动端接入状态',
                content: (): void => {
                  this.mobileRows();
                }
              })
              Text('以上为服务器只读配置，如需修改请在 Web 端管理后台操作')
                .fontSize(12)
                .fontColor($r('app.color.text_tertiary'))
                .width('100%')
                .textAlign(TextAlign.Start)
                .margin({ top: 4 })
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
      this.load();
    })
  }
}
