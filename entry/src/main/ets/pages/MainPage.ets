import { window, uiMaterial } from '@kit.ArkUI';
import { resourceManager } from '@kit.LocalizationKit';
import { SessionStore } from '../store/SessionStore';
import { UiMaterialKit } from '../components/UiMaterialKit';
import { ExpertListPage } from './expert/ExpertListPage';
import { ChatHomeTab } from './chat/ChatHomeTab';
import { WorkspaceTab } from './workspace/WorkspaceTab';
import { MeTab } from './me/MeTab';

/** 主页：4-Tab + API 26 悬浮胶囊导航栏（barFloatingStyle + ImmersiveMaterial 沉浸材质光感） */
@Component
export struct MainPage {
  @StorageLink(SessionStore.KEY_MAIN_TAB) mainTab: number = 0;
  @StorageLink(SessionStore.KEY_ACTIVE_THREAD_ID) @Watch('onThreadPicked') activeThreadId: string = '';
  @State topInset: number = 0;
  @State bottomInset: number = 0;

  aboutToAppear(): void {
    const ui = this.getUIContext();
    window.getLastWindow(getContext(this)).then((win: window.Window) => {
      this.topInset = ui.px2vp(win.getWindowAvoidArea(window.AvoidAreaType.TYPE_SYSTEM).topRect.height);
      this.bottomInset =
        ui.px2vp(win.getWindowAvoidArea(window.AvoidAreaType.TYPE_NAVIGATION_INDICATOR).bottomRect.height);
      const colorMode = getContext(this).resourceManager.getConfigurationSync().colorMode;
      const isDark = colorMode === resourceManager.ColorMode.DARK;
      win.setWindowSystemBarProperties({ statusBarContentColor: isDark ? '#FFFFFF' : '#182431' });
    }).catch((): void => {
    });
  }

  /** 会话被选中（会话 Tab/命令面板点击）时切回聊天 Tab */
  private onThreadPicked(): void {
    if (this.activeThreadId !== '') {
      this.mainTab = 1;
    }
  }

  /** 悬浮栏距屏幕底部距离：避开手势指示条（安全区高度 + 8），不低于系统默认 28 */
  private floatingBarBottomMargin(): number {
    return Math.max(28, this.bottomInset + 8);
  }

  /** 内容底部预留：悬浮栏高度 56 + 底边距 + 间隙 12 */
  private contentBottomPad(): number {
    return this.floatingBarBottomMargin() + 68;
  }

  /** 悬浮栏材质：支持沉浸材质时薄玻璃+光感跟随，否则降级毛玻璃底色 */
  private floatingBarStyle(): FloatingTabBarStyle {
    const barWidth: FloatingTabBarWidth = {
      smallBarWidth: 320,
      mediumBarWidth: 380,
      largeBarWidth: 460
    };
    const mat: uiMaterial.ImmersiveMaterial | null = UiMaterialKit.navBarMaterial();
    if (mat !== null) {
      const style: FloatingTabBarStyle = {
        barWidth: barWidth,
        barBottomMargin: this.floatingBarBottomMargin(),
        systemMaterial: mat
      };
      return style;
    }
    const fallback: FloatingTabBarStyle = {
      barWidth: barWidth,
      barBottomMargin: this.floatingBarBottomMargin(),
      maskColor: $r('app.color.bar_glass')
    };
    return fallback;
  }

  @Builder
  tabBarItem(icon: Resource, title: Resource, index: number) {
    Column({ space: 2 }) {
      SymbolGlyph(icon)
        .fontSize(21)
        .fontColor([index === this.mainTab ? $r('app.color.brand') : $r('app.color.tab_inactive')])
      Text(title)
        .fontSize(10)
        .fontWeight(index === this.mainTab ? FontWeight.Medium : FontWeight.Normal)
        .fontColor(index === this.mainTab ? $r('app.color.brand') : $r('app.color.tab_inactive'))
        .maxLines(1)
    }
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
    .padding({ left: 12, right: 12, top: 6, bottom: 4 })
  }

  build() {
    Tabs({ index: this.mainTab }) {
      TabContent() {
        ExpertListPage({ topInset: this.topInset, bottomPad: this.contentBottomPad() })
      }
      .tabBar(this.tabBarItem($r('sys.symbol.robot'), $r('app.string.tab_expert'), 0))

      TabContent() {
        ChatHomeTab({ topInset: this.topInset, bottomPad: this.contentBottomPad() })
      }
      .tabBar(this.tabBarItem($r('sys.symbol.message'), $r('app.string.tab_chat'), 1))

      TabContent() {
        WorkspaceTab({ topInset: this.topInset, bottomPad: this.contentBottomPad() })
      }
      .tabBar(this.tabBarItem($r('sys.symbol.square_grid_2x2'), $r('app.string.tab_workspace'), 2))

      TabContent() {
        MeTab({ topInset: this.topInset, bottomPad: this.contentBottomPad() })
      }
      .tabBar(this.tabBarItem($r('sys.symbol.person'), $r('app.string.tab_me'), 3))
    }
    .height('100%')
    .width('100%')
    .barPosition(BarPosition.End)
    .barMode(BarMode.Fixed)
    .barOverlap(true)
    .barHeight(56)
    .barFloatingStyle(this.floatingBarStyle())
    .scrollable(true)
    .vertical(false)
    .backgroundColor($r('app.color.bg_page'))
    .onChange((index: number): void => {
      this.mainTab = index;
    })
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
  }
}
