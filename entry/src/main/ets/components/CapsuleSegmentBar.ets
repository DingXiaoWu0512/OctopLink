import { UiMaterialKit } from './UiMaterialKit';

/** 分段选项：label 为渲染文案，value 为业务值（字符串，由调用方解析） */
export class SegmentBarOption {
  readonly label: string;
  readonly value: string;

  constructor(label: string, value: string) {
    this.label = label;
    this.value = value;
  }
}

/**
 * 滑动胶囊分段控件（V1）：
 * 玻璃胶囊容器（glassBg + card_stroke 描边 + padding 3）内等分选项段，
 * 选中段衬 brand 色滑块，切换时滑块以 animateTo 220ms easeOut 平移。
 * 支持 2-5 段；高度 38；宽度由调用方指定（100% 时等分段自动均分）。
 */
@Component
export struct CapsuleSegmentBar {
  /** 分段选项（2-5 段） */
  @Prop @Watch('onOptionsChanged') options: Array<SegmentBarOption> = [];
  /** 选中段索引 */
  @Prop @Watch('onSelectedChanged') selectedIndex: number = 0;
  /** 选中回调（index） */
  onSelect: (index: number) => void = (_index: number): void => {
  };
  /** 分段轨道实测宽（vp）：滑块几何用 */
  @State private trackWidth: number = 0;
  /** 滑块当前 X 偏移（vp） */
  @State private slideX: number = 0;

  private segmentCount(): number {
    return this.options.length > 0 ? this.options.length : 1;
  }

  private segmentWidth(): number {
    return this.trackWidth / this.segmentCount();
  }

  /** 选中段变化：滑块平滑滑动到新段 */
  private onSelectedChanged(propName: string): void {
    this.animateSlide();
  }

  /** 选项数组变化（如管理员段增减）：重算滑块位置（不动画，避免宽度变化时跳动） */
  private onOptionsChanged(propName: string): void {
    if (this.trackWidth > 0) {
      this.slideX = this.selectedIndex * this.segmentWidth();
    }
  }

  private animateSlide(): void {
    if (this.trackWidth <= 0) {
      this.slideX = 0;
      return;
    }
    const targetX: number = this.selectedIndex * this.segmentWidth();
    this.getUIContext().animateTo({
      duration: 220,
      curve: Curve.EaseOut
    }, (): void => {
      this.slideX = targetX;
    });
  }

  private onTrackAreaChange(newArea: Area): void {
    const measured: number = Number(newArea.width);
    const moved: boolean = Math.abs(measured - this.trackWidth) > 0.5;
    this.trackWidth = measured;
    if (moved) {
      // 首次量宽 / 容器宽度变化：直接落位，不走动画
      this.slideX = this.selectedIndex * this.segmentWidth();
    }
  }

  private isSelected(index: number): boolean {
    return index === this.selectedIndex;
  }

  build() {
    Stack({ alignContent: Alignment.Start }) {
      // 选中段 brand 滑块（置于标签层下方，随 slideX 平移）
      Column()
        .width(this.segmentWidth())
        .height('100%')
        .borderRadius(16)
        .backgroundColor($r('app.color.brand'))
        .offset({ x: this.slideX })

      // 等分段标签层
      Row() {
        ForEach(this.options, (option: SegmentBarOption, index: number) => {
          Text(option.label)
            .fontSize(13)
            .fontWeight(this.isSelected(index) ? FontWeight.Medium : FontWeight.Normal)
            .fontColor(this.isSelected(index) ?
              $r('app.color.text_on_brand') : $r('app.color.text_secondary'))
            .textAlign(TextAlign.Center)
            .maxLines(1)
            .height('100%')
            .layoutWeight(1)
            .onClick((): void => {
              this.onSelect(index);
            })
        }, (option: SegmentBarOption) => `${option.value}_${option.label}`)
      }
      .width('100%')
      .height('100%')
      .onAreaChange((_oldArea: Area, newArea: Area): void => {
        this.onTrackAreaChange(newArea);
      })
    }
    .width('100%')
    .height(38)
    .padding(3)
    .borderRadius(19)
    .backgroundColor(UiMaterialKit.glassBg($r('app.color.bg_input')))
    .systemMaterial(UiMaterialKit.button())
    .border({ width: 1, color: $r('app.color.card_stroke') })
  }
}
