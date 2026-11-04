/** 流式轨道指示器：5 节点绕轨步进旋转，头部节点大而亮、尾部小而淡（conduit Orbit 复刻） */
@Component
export struct StreamingOrbit {
  @Prop orbitSize: number = 20;
  @Prop orbitColor: ResourceColor = $r('app.color.brand');
  @State phase: number = 0;
  private timerId: number = -1;

  aboutToAppear(): void {
    this.timerId = setInterval((): void => {
      this.phase = (this.phase + 1) % 5;
    }, 400);
  }

  aboutToDisappear(): void {
    if (this.timerId >= 0) {
      clearInterval(this.timerId);
      this.timerId = -1;
    }
  }

  private nodePhase(index: number): number {
    return ((this.phase - index) % 5 + 5) % 5;
  }

  private nodeDiameter(index: number): number {
    return 6.4 - this.nodePhase(index) * 0.75;
  }

  private nodeOpacity(index: number): number {
    return 1 - this.nodePhase(index) * 0.19;
  }

  private nodeX(index: number): number {
    const half: number = this.orbitSize / 2;
    const angle: number = this.nodePhase(index) * (Math.PI * 2 / 5) - Math.PI / 2;
    return half + (half - 3.6) * Math.cos(angle) - this.nodeDiameter(index) / 2;
  }

  private nodeY(index: number): number {
    const half: number = this.orbitSize / 2;
    const angle: number = this.nodePhase(index) * (Math.PI * 2 / 5) - Math.PI / 2;
    return half + (half - 3.6) * Math.sin(angle) - this.nodeDiameter(index) / 2;
  }

  build() {
    Stack() {
      Circle()
        .width(this.orbitSize - 1)
        .height(this.orbitSize - 1)
        .fill(Color.Transparent)
        .stroke(this.orbitColor)
        .strokeWidth(1)
        .strokeOpacity(0.18)
      Circle()
        .width(this.nodeDiameter(0))
        .height(this.nodeDiameter(0))
        .fill(this.orbitColor)
        .fillOpacity(this.nodeOpacity(0))
        .position({ x: this.nodeX(0), y: this.nodeY(0) })
      Circle()
        .width(this.nodeDiameter(1))
        .height(this.nodeDiameter(1))
        .fill(this.orbitColor)
        .fillOpacity(this.nodeOpacity(1))
        .position({ x: this.nodeX(1), y: this.nodeY(1) })
      Circle()
        .width(this.nodeDiameter(2))
        .height(this.nodeDiameter(2))
        .fill(this.orbitColor)
        .fillOpacity(this.nodeOpacity(2))
        .position({ x: this.nodeX(2), y: this.nodeY(2) })
      Circle()
        .width(this.nodeDiameter(3))
        .height(this.nodeDiameter(3))
        .fill(this.orbitColor)
        .fillOpacity(this.nodeOpacity(3))
        .position({ x: this.nodeX(3), y: this.nodeY(3) })
      Circle()
        .width(this.nodeDiameter(4))
        .height(this.nodeDiameter(4))
        .fill(this.orbitColor)
        .fillOpacity(this.nodeOpacity(4))
        .position({ x: this.nodeX(4), y: this.nodeY(4) })
    }
    .width(this.orbitSize)
    .height(this.orbitSize)
  }
}

/**
 * 等待回复气泡内的"Octop 在忙"动效：
 * 打字章鱼（type.webp）做 Working 心情同款快呼吸 + 上下浮动，右侧三点渐次呼吸示意输出中。
 * 替代原五点绕轨指示器（视觉太机械）；LTPO 30Hz 期望帧率低功耗。
 */
@Component
export struct BusyOctop {
  @State private breathe: number = 1;
  @State private bob: number = 0;
  @State private dotPhase: number = 0;
  private timerId: number = -1;
  private readonly dotIdx: number[] = [0, 1, 2];

  aboutToAppear(): void {
    this.getUIContext().animateTo({
      duration: 700,
      curve: Curve.EaseInOut,
      iterations: -1,
      playMode: PlayMode.Alternate,
      expectedFrameRateRange: { expected: 30, min: 0, max: 120 }
    }, (): void => {
      this.breathe = 1.07;
      this.bob = -1.5;
    });
    this.timerId = setInterval((): void => {
      this.dotPhase = (this.dotPhase + 1) % 3;
    }, 350);
  }

  aboutToDisappear(): void {
    if (this.timerId >= 0) {
      clearInterval(this.timerId);
      this.timerId = -1;
    }
  }

  build() {
    Row({ space: 7 }) {
      Image($rawfile('pet/type.webp'))
        .width(46)
        .height(26)
        .objectFit(ImageFit.Contain)
        .interpolation(ImageInterpolation.None)
        .scale({ x: this.breathe, y: this.breathe })
        .translate({ y: this.bob })

      ForEach(this.dotIdx, (i: number) => {
        Circle()
          .width(4.6)
          .height(4.6)
          .fill($r('app.color.brand'))
          .fillOpacity(this.dotPhase === i ? 0.95 : 0.3)
          .scale({ x: this.dotPhase === i ? 1.25 : 1, y: this.dotPhase === i ? 1.25 : 1 })
          .margin({ top: 8 })
      }, (i: number) => `${i}`)
    }
    .alignItems(VerticalAlign.Center)
  }
}
