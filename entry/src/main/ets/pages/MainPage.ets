import { window, uiMaterial } from '@kit.ArkUI';
import { resourceManager } from '@kit.LocalizationKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { SessionStore } from '../store/SessionStore';
import { NotifyService, PushMessage } from '../service/NotifyService';
import { UiMaterialKit } from '../components/UiMaterialKit';
import { ExpertListPage } from './expert/ExpertListPage';
import { ChatHomeTab } from './chat/ChatHomeTab';
import { WorkspaceTab } from './workspace/WorkspaceTab';
import { MeTab } from './me/MeTab';

/** 主页：系统 Tabs 底部 TabBar（barFloatingStyle 悬浮样式 + ImmersiveMaterial 沉浸材质光感） */
@Component
export struct MainPage {
  @StorageLink(SessionStore.KEY_MAIN_TAB) mainTab: number = 0;
  @StorageLink('immersive.light.on') immersiveOn: boolean = true;
  // 注意：activeThreadId 不能挂 @Watch 自动跳聊天 Tab——聊天页首次挂载时会自动恢复最近会话
  // （loadThreads 写入 activeThreadId），从专家页点工作台时滑动动画经过聊天页触发挂载，
  // 会把 Tab 强拉回聊天（稳定复现的跳 Tab bug）。显式选会话的流程（命令面板/会话列表/开始对话）
  // 都会自己写 KEY_MAIN_TAB = 1，无需这里代跳。
  @StorageLink(SessionStore.KEY_ACTIVE_THREAD_ID) activeThreadId: string = '';
  @StorageLink(SessionStore.KEY_CHAT_UNREAD) chatUnread: number = 0;
  @State topInset: number = 0;
  @State bottomInset: number = 0;
  /** 软键盘高度（vp）：仅作用于悬浮 TabBar 的 barBottomMargin（把 TabBar 推回原屏幕位置，不随压缩视口上浮）；
   *  严禁进入 contentBottomPad()/floatingBarBottomMargin() 公共链路（否则输入卡被二次推高、气泡停止位失真） */
  @State kbHeight: number = 0;
  /** US3 悬浮 TabBar 宽度数值化：窗口宽（vp），barWidth = min(winWidthVp - 32, 输入卡 maxWidth 断点)（左右边缘与实际渲染的输入卡对齐）；0 = 窗口未就绪 */
  @State winWidthVp: number = 0;
  private win: window.Window | null = null;

  aboutToAppear(): void {
    this.registerPushHandler();
    hilog.info(0x0000, 'OctopUiMaterial',
      'supported=%{public}s level=%{public}d',
      UiMaterialKit.isSupported().toString(), uiMaterial.getGlobalMaterialLevel());
    const ui = this.getUIContext();
    window.getLastWindow(getContext(this)).then((win: window.Window) => {
      this.win = win;
      // 键盘弹出（RESIZE 压缩视口）时把悬浮 TabBar 的底边距增补键盘高度——
      // TabBar 被推回原屏幕位置（压缩视口外被裁剪，等效原地被键盘覆盖），收起后恢复。
      // kbHeight 的更新包一层 animateTo：TabBar 收缩、输入卡边距（inputBottomInset）、
      // 列表 contentEndOffset 全部随 260ms 过渡与系统键盘动画同步——
      // 否则二值翻转瞬间落位，而窗口 RESIZE 动画还在跑，画面来回跳（实测）
      win.on('keyboardHeightChange', (height: number): void => {
        const h: number = ui.px2vp(height);
        if (Math.abs(this.kbHeight - h) < 0.5) {
          return;
        }
        ui.animateTo({
          duration: 260,
          curve: Curve.EaseInOut
        }, () => {
          this.kbHeight = h;
        });
      });
      // 模拟器的 TYPE_SYSTEM 避让区可能上报接近 0 的值，而 HDS 标题栏实际避让了整个状态栏，
      // 这里钳到真实状态栏的高度下限，保证各页 spacer/偏移计算不塌陷
      this.topInset = Math.max(ui.px2vp(win.getWindowAvoidArea(window.AvoidAreaType.TYPE_SYSTEM).topRect.height), 36);
      this.bottomInset =
        ui.px2vp(win.getWindowAvoidArea(window.AvoidAreaType.TYPE_NAVIGATION_INDICATOR).bottomRect.height);
      // US3：记录窗口宽（vp），供 barWidth 数值化（winWidthVp - 32 与输入卡左右边缘对齐）
      this.winWidthVp = ui.px2vp(win.getWindowProperties().windowRect.width);
      const colorMode = getContext(this).resourceManager.getConfigurationSync().colorMode;
      const isDark = colorMode === resourceManager.ColorMode.DARK;
      win.setWindowSystemBarProperties({ statusBarContentColor: isDark ? '#FFFFFF' : '#182431' });
    }).catch((): void => {
    });
  }

  aboutToDisappear(): void {
    if (this.win !== null) {
      this.win.off('keyboardHeightChange');
      this.win = null;
    }
  }

  /** 通知推送：聊天 Tab 红点 + toast（正在聊天页时只刷新不计数） */
  private registerPushHandler(): void {
    NotifyService.setPushHandler((msg: PushMessage): void => {
      AppStorage.setOrCreate(SessionStore.KEY_THREADS_DIRTY, true);
      if (this.mainTab !== 1) {
        this.chatUnread += 1;
      }
      const who: string = msg.agentName !== '' ? msg.agentName : '专家';
      const preview: string = msg.text !== '' ? msg.text : '你收到一条新消息';
      this.getUIContext().getPromptAction().showToast({ message: `${who}：${preview}` });
    });
  }

  /** 悬浮 TabBar 距屏幕底部距离（barBottomMargin）：避开手势指示条（安全区高度 + 8），不低于系统默认 28 */
  private floatingBarBottomMargin(): number {
    return Math.max(28, this.bottomInset + 8);
  }

  /** 内容底部预留：悬浮 TabBar 高度 56 + 底边距 + 间隙 12（bottomPad prop 链自动传导） */
  private contentBottomPad(): number {
    return this.floatingBarBottomMargin() + 68;
  }

  /** TabBar 悬浮样式（读 @StorageLink immersiveOn，开关切换即时重渲染）：
   *  沉浸光感开启且材质可用时挂 systemMaterial（THIN 玻璃光感，仅系统 TabBar 可承载）；
   *  关闭/不支持时返回普通悬浮样式（无材质，普通底色）。
   *  键盘弹出时不改 margin——负 margin 实测被框架钳到最小 28vp 仍悬于键盘上方，
   *  改由 build() 里 barHeight 随 kbHeight 置 0 隐藏 TabBar（kbHeight>0 时），收起后恢复 */
  private floatingBarStyle(): FloatingTabBarStyle {
    const mat: uiMaterial.ImmersiveMaterial | null = UiMaterialKit.navBarMaterial();
    if (this.immersiveOn && mat !== null) {
      const style: FloatingTabBarStyle = {
        barBottomMargin: this.floatingBarBottomMargin(),
        systemMaterial: mat
      };
      return style;
    }
    const fallback: FloatingTabBarStyle = {
      barBottomMargin: this.floatingBarBottomMargin()
    };
    return fallback;
  }

  /** 切换 Tab（点击/滑动统一经 onChange 入口）：写回 mainTab 并清聊天红点 */
  private switchTab(index: number): void {
    this.mainTab = index;
    if (index === 1 && this.chatUnread > 0) {
      this.chatUnread = 0;
    }
  }

  @Builder
  tabBarItem(icon: Resource, title: Resource, index: number) {
    Column({ space: 2 }) {
      Stack({ alignContent: Alignment.TopEnd }) {
        SymbolGlyph(icon)
          .fontSize(21)
          .fontColor([index === this.mainTab ? $r('app.color.brand') : $r('app.color.tab_inactive')])
        if (index === 1 && this.chatUnread > 0) {
          Text(this.chatUnread > 99 ? '99+' : `${this.chatUnread}`)
            .fontSize(this.chatUnread > 99 ? 8 : 9)
            .fontWeight(FontWeight.Medium)
            .fontColor($r('app.color.text_on_brand'))
            .backgroundColor($r('app.color.danger'))
            .borderRadius(8)
            .constraintSize({ minWidth: 16, minHeight: 16 })
            .padding({ left: 4, right: 4 })
            .textAlign(TextAlign.Center)
            .offset({ x: this.chatUnread > 99 ? 8 : 6, y: -4 })
        }
      }

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
        ChatHomeTab({ topInset: this.topInset, bottomPad: this.contentBottomPad(), kbHeight: this.kbHeight })
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
    // 键盘弹出（kbHeight>0）时隐藏悬浮 TabBar（不再随压缩视口上浮到键盘上方），收起后恢复 56
    .barHeight(this.kbHeight > 0 ? 0 : 56)
    // US4 键盘残留修复：barHeight 置 0 后 pill 容器仍有默认宽度残留（约 28px 高亮条），
    // 键盘期同步 barWidth 置 0 彻底不可见；收起后 barWidth 复原——
    // US3 数值化收敛为与输入卡同宽：输入卡实际宽 = min(窗口宽-32, inputMaxWidth 断点上限)，
    // 断点与 ChatHomeTab L167 一致（<600→320 / <840→380 / else 460）——仅取窗口宽-32 在窄屏会
    // 比被 320 上限封顶居中的输入卡宽 24px（左右边距 56 vs 80），故同步取 min 保证两侧边缘对齐；
    // 未就绪首帧回退 '100%'
    .barWidth(this.kbHeight > 0 ? 0 : (this.winWidthVp > 0 ? Math.min(this.winWidthVp - 32, this.winWidthVp < 600 ? 320 : (this.winWidthVp < 840 ? 380 : 460)) : '100%'))
    .barBackgroundColor(Color.Transparent)
    // US4b 横杠彻底清除：官方文档 barFloatingStyle(style: Optional<FloatingTabBarStyle>) 传 undefined
    // 取消悬浮样式恢复默认——pill 胶囊（104×28px 横杠）与 maskColor 蒙层（暗带）均为悬浮样式装饰物，
    // 随之消失；与上方 barHeight(0)/barWidth(0) 双保险。收起后（kbHeight===0）恢复原悬浮样式（FR-014）
    .barFloatingStyle(this.kbHeight > 0 ? undefined : this.floatingBarStyle())
    .scrollable(true)
    .vertical(false)
    .backgroundColor($r('app.color.bg_page'))
    .onChange((index: number): void => {
      this.switchTab(index);
    })
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
  }
}
