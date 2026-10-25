import { ConfigurationConstant } from '@kit.AbilityKit';
import { AppPrefs } from './AppPrefs';
import { Log } from '../utils/Logger';

/**
 * 外观模式存储与应用：浅色 / 深色 / 跟随系统。
 * - AppStorage 键供 UI 响应当前选择；AppPrefs 持久化跨启动。
 * - 通过 ApplicationContext.setColorMode 全局生效（深浅色资源自动切换）。
 */
export class AppearanceStore {
  static readonly KEY_APPEARANCE = 'appearance.mode';
  static readonly MODE_LIGHT = 'light';
  static readonly MODE_DARK = 'dark';
  static readonly MODE_AUTO = 'auto';

  /** 立即应用颜色模式（不落盘） */
  static applyMode(mode: string, context: Context): void {
    try {
      const appContext = context.getApplicationContext();
      if (mode === AppearanceStore.MODE_LIGHT) {
        appContext.setColorMode(ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT);
      } else if (mode === AppearanceStore.MODE_DARK) {
        appContext.setColorMode(ConfigurationConstant.ColorMode.COLOR_MODE_DARK);
      } else {
        appContext.setColorMode(ConfigurationConstant.ColorMode.COLOR_MODE_NOT_SET);
      }
    } catch (e) {
      Log.warn('apply color mode failed');
    }
  }

  /** 启动恢复：读取持久化外观并应用 */
  static async restore(context: Context): Promise<void> {
    const saved: string = await AppPrefs.getInstance().getAppearance();
    const mode: string = saved === AppearanceStore.MODE_LIGHT || saved === AppearanceStore.MODE_DARK
      ? saved : AppearanceStore.MODE_AUTO;
    AppStorage.setOrCreate(AppearanceStore.KEY_APPEARANCE, mode);
    AppearanceStore.applyMode(mode, context);
  }

  /** 切换外观：更新全局状态 + 落盘 + 立即生效 */
  static async setMode(mode: string, context: Context): Promise<void> {
    AppStorage.setOrCreate(AppearanceStore.KEY_APPEARANCE, mode);
    AppearanceStore.applyMode(mode, context);
    await AppPrefs.getInstance().setAppearance(mode);
  }
}
