import { preferences } from '@kit.ArkData';
import { Log } from '../utils/Logger';

const PREF_NAME = 'octop_link_prefs';
const KEY_SERVER_URL = 'server_url';
const KEY_USERNAME = 'username';
const KEY_DISPLAY_NAME = 'display_name';
const KEY_ROLE = 'role';

/** 本地持久化的用户资料（仅展示用途，敏感数据不落盘） */
export class UserProfilePref {
  username: string;
  displayName: string;
  role: string;

  constructor(username: string, displayName: string, role: string) {
    this.username = username;
    this.displayName = displayName;
    this.role = role;
  }
}

/** 轻量偏好存储：服务器地址与上次登录用户资料 */
export class AppPrefs {
  private static instance: AppPrefs | null = null;
  private store: preferences.Preferences | null = null;

  static getInstance(): AppPrefs {
    if (AppPrefs.instance === null) {
      AppPrefs.instance = new AppPrefs();
    }
    return AppPrefs.instance;
  }

  async init(context: Context): Promise<void> {
    if (this.store !== null) {
      return;
    }
    try {
      this.store = await preferences.getPreferences(context, PREF_NAME);
    } catch (e) {
      Log.error('AppPrefs init failed');
    }
  }

  async getServerUrl(): Promise<string> {
    return await this.getString(KEY_SERVER_URL);
  }

  async setServerUrl(url: string): Promise<void> {
    await this.putString(KEY_SERVER_URL, url);
  }

  async saveProfile(profile: UserProfilePref): Promise<void> {
    await this.putString(KEY_USERNAME, profile.username);
    await this.putString(KEY_DISPLAY_NAME, profile.displayName);
    await this.putString(KEY_ROLE, profile.role);
  }

  async getProfile(): Promise<UserProfilePref> {
    const username = await this.getString(KEY_USERNAME);
    const displayName = await this.getString(KEY_DISPLAY_NAME);
    const role = await this.getString(KEY_ROLE);
    return new UserProfilePref(username, displayName, role);
  }

  async clearAll(): Promise<void> {
    const store = this.store;
    if (store === null) {
      return;
    }
    try {
      await store.clear();
      await store.flush();
    } catch (e) {
      Log.error('AppPrefs clear failed');
    }
  }

  private async getString(key: string): Promise<string> {
    const store = this.store;
    if (store === null) {
      return '';
    }
    try {
      const value = await store.get(key, '');
      if (typeof value === 'string') {
        return value;
      }
      return '';
    } catch (e) {
      return '';
    }
  }

  private async putString(key: string, value: string): Promise<void> {
    const store = this.store;
    if (store === null) {
      return;
    }
    try {
      await store.put(key, value);
      await store.flush();
    } catch (e) {
      Log.error(`AppPrefs put ${key} failed`);
    }
  }
}
