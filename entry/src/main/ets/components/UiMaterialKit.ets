import { uiMaterial } from '@kit.ArkUI';
import { AppPrefs } from '../store/AppPrefs';

/**
 * 沉浸系统材质（API 26）统一封装：
 * - 支持性探测缓存（isImmersiveMaterialSupported）
   * - navBarMaterial()：底部悬浮导航栏材质（THIN，UX 规范：底部悬浮用 THIN），供 Tabs barFloatingStyle
   * - sheet()：Sheet/面板/弹窗材质（ULTRA_THICK，UX 规范：半模态与弹出框大面积用 ULTRA_THICK），供 bindSheet/openCustomDialog
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

  /** 沉浸光感总开关（"我的"页可切换；AppStorage 供实时读取，AppPrefs 持久化跨启动） */
  static immersiveOn(): boolean {
    const v = AppStorage.get<boolean>('immersive.light.on');
    return v !== false;
  }

  /** 启动恢复：读取持久化开关到 AppStorage */
  static async restore(context: Context): Promise<void> {
    const on: boolean = await AppPrefs.getInstance().getImmersiveLight();
    AppStorage.setOrCreate('immersive.light.on', on);
  }

  /** 切换总开关：更新 AppStorage + 落盘 */
  static async setImmersiveLight(on: boolean, context: Context): Promise<void> {
    AppStorage.setOrCreate('immersive.light.on', on);
    await AppPrefs.getInstance().setImmersiveLight(on);
  }

  /** 显式关闭组件材质（总开关关闭时使用） */
  static emptyMaterial(): uiMaterial.Material {
    return uiMaterial.Material.empty;
  }

    /** Navigation 标题栏材质：总开关开启时不设置（走应用级 ENABLE 默认 ULTRA_THIN），关闭时 Material.empty 显式关闭 */
  static navigationTitleMaterial(): uiMaterial.Material | undefined {
    return UiMaterialKit.immersiveOn() ? undefined : uiMaterial.Material.empty;
  }

  /** 悬浮导航栏：超薄玻璃 + 交互变形 + 轻光感跟随；无补色白填充，保持通透 */
  static navBarMaterial(): uiMaterial.ImmersiveMaterial | null {
    if (!UiMaterialKit.isSupported() || !UiMaterialKit.immersiveOn()) {
      return null;
    }
    return new uiMaterial.ImmersiveMaterial({
      style: uiMaterial.ImmersiveStyle.THIN,
      colorInvert: false,
      applyShadow: true,
      interactive: true,
      lightEffect: { color: '#33FFFFFF' }
    });
  }

  /** Sheet/面板：常规厚度 + 自动补色；不支持返回 Material.empty */
  static sheet(): uiMaterial.Material {
    if (!UiMaterialKit.isSupported() || !UiMaterialKit.immersiveOn()) {
      return uiMaterial.Material.empty;
    }
    return new uiMaterial.ImmersiveMaterial({
      style: uiMaterial.ImmersiveStyle.ULTRA_THICK,
      colorInvert: true
    });
  }

  /** 图标/胶囊按钮：超薄玻璃 + 交互形变 + 光感按压反馈；不支持返回 Material.empty（保留原背景色降级） */
  static button(): uiMaterial.Material {
    if (!UiMaterialKit.isSupported() || !UiMaterialKit.immersiveOn()) {
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

  /** 页面标题栏：常驻超薄玻璃（Scroll 页 GRADUAL_BLUR 不生效的兜底，内容从玻璃下滚过） */
  static titleBar(): uiMaterial.Material {
    if (!UiMaterialKit.isSupported() || !UiMaterialKit.immersiveOn()) {
      return uiMaterial.Material.empty;
    }
    return new uiMaterial.ImmersiveMaterial({
      style: uiMaterial.ImmersiveStyle.ULTRA_THIN,
      colorInvert: true,
      applyShadow: false
    });
  }

  /** 大面积玻璃卡片（可点击）：薄玻璃 + 自动补色 + 系统投影 + 交互形变；不支持返回 Material.empty */
  static card(): uiMaterial.Material {
    if (!UiMaterialKit.isSupported() || !UiMaterialKit.immersiveOn()) {
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
