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
