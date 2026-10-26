import { AgentService } from '../service/AgentService';

/**
 * 通用专家头像（共享组件）：
 * - iconUrl 优先（AgentService.assetUrl 转绝对地址）
 * - 回退 agentId 头像接口（avatarUrl）
 * - 两者皆空或加载失败回退应用 logo
 */
@Component
export struct AgentAvatar {
  @Prop agentId: string = '';
  @Prop iconUrl: string = '';
  @Prop avatarSize: number = 42;
  @State failed: boolean = false;

  private src(): string {
    if (this.iconUrl !== '') {
      return AgentService.assetUrl(this.iconUrl);
    }
    return AgentService.avatarUrl(this.agentId);
  }

  build() {
    if (this.failed || (this.iconUrl === '' && this.agentId === '')) {
      Image($r('app.media.octop_logo'))
        .width(this.avatarSize)
        .height(this.avatarSize)
        .borderRadius(this.avatarSize / 2)
        .backgroundColor($r('app.color.brand_light'))
        .objectFit(ImageFit.Cover)
    } else {
      Image(this.src())
        .width(this.avatarSize)
        .height(this.avatarSize)
        .borderRadius(this.avatarSize / 2)
        .backgroundColor($r('app.color.brand_light'))
        .objectFit(ImageFit.Cover)
        .onError((event: ImageError): void => {
          this.failed = true;
        })
    }
  }
}
