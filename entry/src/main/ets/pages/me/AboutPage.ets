import { bundleManager } from '@kit.AbilityKit';
import { PageHeader } from '../../components/PageHeader';

/** 关于页（路由 'about'）：居中 logo/应用名/slogan + 动态版本号卡（失败回退静态文本不空白） */
@Component
export struct AboutPage {
  @State appVersion: string = '';

  aboutToAppear(): void {
    this.loadVersion();
  }

  /** bundleManager 动态取 versionName；失败/为空回退静态版本文本 */
  private async loadVersion(): Promise<void> {
    try {
      const info: bundleManager.BundleInfo =
        await bundleManager.getBundleInfoForSelf(bundleManager.BundleFlag.GET_BUNDLE_INFO_DEFAULT);
      const v = info.versionName;
      if (typeof v === 'string' && v !== '') {
        this.appVersion = v;
        return;
      }
    } catch (e) {
      // 取包信息失败：走静态回退，不留空白
    }
    this.appVersion = '1.0.0';
  }

  build() {
    NavDestination() {
      Column() {
        PageHeader({ title: '关于' })

        Scroll() {
          Column({ space: 16 }) {
            Column({ space: 10 }) {
              Image($r('app.media.octop_logo'))
                .width(88)
                .height(88)
                .borderRadius(28)
              Text('Octop Link')
                .fontSize(22)
                .fontWeight(FontWeight.Bold)
                .fontColor($r('app.color.text_primary'))
              Text('一个界面，连接专家、对话与工作台')
                .fontSize(13)
                .fontColor($r('app.color.text_tertiary'))
            }
            .width('100%')
            .padding({ top: 48, bottom: 24 })
            .alignItems(HorizontalAlign.Center)

            Row() {
              Text('版本')
                .fontSize(15)
                .fontColor($r('app.color.text_primary'))
              Blank()
              Text(this.appVersion === '' ? '…' : this.appVersion)
                .fontSize(14)
                .fontColor($r('app.color.text_secondary'))
            }
            .width('100%')
            .padding({ left: 14, right: 14, top: 14, bottom: 14 })
            .borderRadius(16)
            .backgroundColor($r('app.color.bg_card'))
            .border({ width: 1, color: $r('app.color.card_stroke') })
            .shadow({ radius: 10, color: '#0A000000', offsetY: 3 })

            Column({ space: 6 }) {
              Text('开源致谢')
                .fontSize(15)
                .fontColor($r('app.color.text_primary'))
              Text('应用内吉祥物动效素材（探头章鱼、打字章鱼）源自开源项目 OctopPet（作者 jubaoliang），基于 MIT License 授权使用。')
                .fontSize(13)
                .fontColor($r('app.color.text_secondary'))
                .lineHeight(20)
            }
            .width('100%')
            .padding({ left: 14, right: 14, top: 14, bottom: 14 })
            .borderRadius(16)
            .backgroundColor($r('app.color.bg_card'))
            .border({ width: 1, color: $r('app.color.card_stroke') })
            .shadow({ radius: 10, color: '#0A000000', offsetY: 3 })
            .alignItems(HorizontalAlign.Start)

            Text('基于 HarmonyOS ArkUI 构建')
              .fontSize(12)
              .fontColor($r('app.color.text_tertiary'))
              .margin({ top: 8 })
          }
          .width('100%')
          .padding({ left: 14, right: 14, bottom: 40 })
          .alignItems(HorizontalAlign.Start)
        }
        .layoutWeight(1)
        .width('100%')
        .align(Alignment.Top)
        .scrollBar(BarState.Off)
        .edgeEffect(EdgeEffect.Spring)
      }
      .width('100%')
      .height('100%')
    }
    .hideTitleBar(true)
    .backgroundColor($r('app.color.bg_page'))
  }
}
