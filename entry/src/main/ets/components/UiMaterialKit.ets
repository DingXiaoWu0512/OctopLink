import { uiMaterial } from '@kit.ArkUI';

/**
 * 沉浸系统材质（API 26）统一封装：
 * - 支持性探测缓存（isImmersiveMaterialSupported）
 * - navBarMaterial()：悬浮导航栏材质（薄玻璃 + 光感跟随 + 自动补色），供 Tabs barFloatingStyle
 * - sheet()：Sheet/面板材质（REGULAR），供 bindSheet systemMaterial
 * - 不支持时返回 null / Material.empty，调用方走降级分支
 */
export class UiMaterialKit {
  private static supported: boolean | null = null;

  static isSupported(): boolean {
    if (UiMaterialKit.supported === null) {
      UiMaterialKit.supported = uiMaterial.isImmersiveMaterialSupported();
    }
    return UiMaterialKit.supported;
  }

  /** 悬浮导航栏：超薄玻璃 + 交互变形 + 光感跟随反馈 + 自动补色 + 阴影；不支持返回 null */
  static navBarMaterial(): uiMaterial.ImmersiveMaterial | null {
    if (!UiMaterialKit.isSupported()) {
      return null;
    }
    return new uiMaterial.ImmersiveMaterial({
      style: uiMaterial.ImmersiveStyle.ULTRA_THIN,
      colorInvert: true,
      applyShadow: true,
      interactive: true,
      lightEffect: { color: '#80FFFFFF' }
    });
  }

  /** Sheet/面板：常规厚度 + 自动补色；不支持返回 Material.empty */
  static sheet(): uiMaterial.Material {
    if (!UiMaterialKit.isSupported()) {
      return uiMaterial.Material.empty;
    }
    return new uiMaterial.ImmersiveMaterial({
      style: uiMaterial.ImmersiveStyle.REGULAR,
      colorInvert: true
    });
  }

  /** 图标/胶囊按钮：超薄玻璃 + 交互形变 + 光感按压反馈；不支持返回 Material.empty（保留原背景色降级） */
  static button(): uiMaterial.Material {
    if (!UiMaterialKit.isSupported()) {
      return uiMaterial.Material.empty;
    }
    return new uiMaterial.ImmersiveMaterial({
      style: uiMaterial.ImmersiveStyle.ULTRA_THIN,
      colorInvert: true,
      applyShadow: false,
      interactive: true,
      lightEffect: { color: '#66FFFFFF' }
    });
  }

  /** 大面积玻璃卡片（可点击）：薄玻璃 + 自动补色 + 系统投影 + 交互形变；不支持返回 Material.empty */
  static card(): uiMaterial.Material {
    if (!UiMaterialKit.isSupported()) {
      return uiMaterial.Material.empty;
    }
    return new uiMaterial.ImmersiveMaterial({
      style: uiMaterial.ImmersiveStyle.THIN,
      colorInvert: true,
      applyShadow: true,
      interactive: true,
      lightEffect: { color: '#66FFFFFF' }
    });
  }
}
