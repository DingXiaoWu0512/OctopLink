import { window } from '@kit.ArkUI';

/**
 * 二级页顶部标题栏：返回按钮 + 标题。
 * 沉浸式全屏布局（setWindowLayoutFullScreen）下系统标题栏不会避让状态栏，
 * 故各 NavDestination 页隐藏系统标题栏（hideTitleBar）并使用本组件替代，
 * 内部按系统状态栏高度（getWindowAvoidArea TYPE_SYSTEM）自动避让。
 */
@Component
export struct PageHeader {
  @Prop title: string = '';
  @State topInset: number = 0;
  @Consume('navStack') navStack: NavPathStack;
  /** 返回行为覆写（默认 pop 当前栈顶） */
  onBack: (() => void) | null = null;

  aboutToAppear(): void {
    const ui = this.getUIContext();
    window.getLastWindow(getContext(this)).then((win: window.Window): void => {
      this.topInset = ui.px2vp(win.getWindowAvoidArea(window.AvoidAreaType.TYPE_SYSTEM).topRect.height);
    }).catch((): void => {
    });
  }

  build() {
    Row({ space: 12 }) {
      Button({ type: ButtonType.Circle, stateEffect: true }) {
        SymbolGlyph($r('sys.symbol.arrow_left'))
          .fontSize(17)
          .fontWeight(FontWeight.Medium)
          .fontColor([$r('app.color.text_primary')])
      }
      .width(34)
      .height(34)
      .backgroundColor($r('app.color.bg_card'))
      .border({ width: 1, color: $r('app.color.card_stroke') })
      .onClick((): void => {
        if (this.onBack !== null) {
          this.onBack();
          return;
        }
        this.navStack.pop();
      })

      Text(this.title)
        .fontSize(18)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.text_primary'))
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .layoutWeight(1)
    }
    .width('100%')
    .padding({ left: 14, right: 14, top: this.topInset + 8, bottom: 8 })
  }
}
