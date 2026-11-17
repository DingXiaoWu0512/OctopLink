import { preferences } from '@kit.ArkData';
import { Log } from '../utils/Logger';

const PREF_NAME = 'octop_link_prefs';
const KEY_SERVER_URL = 'server_url';
const KEY_USERNAME = 'username';
const KEY_DISPLAY_NAME = 'display_name';
const KEY_ROLE = 'role';
const KEY_APPEARANCE = 'appearance_mode';
const KEY_IMMERSIVE = 'immersive_light';
const KEY_PET_VISIBLE = 'pet_visible';
const KEY_TTS_SPEED = 'tts_speed';
const KEY_TTS_PITCH = 'tts_pitch';
const KEY_TTS_VOLUME = 'tts_volume';
const KEY_TTS_PERSON = 'tts_person';
const KEY_TTS_ONLINE = 'tts_online';
const KEY_LAST_AGENT_ID = 'last_agent_id';

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

  /** 专家记忆：上次使用的专家 agentId（'' 表无记录/清除；logout clearAll 自动连带清除，换账号不串专家） */
  async getLastAgentId(): Promise<string> {
    return await this.getString(KEY_LAST_AGENT_ID);
  }

  async setLastAgentId(id: string): Promise<void> {
    await this.putString(KEY_LAST_AGENT_ID, id);
  }

  async getImmersiveLight(): Promise<boolean> {
    if (this.store === null) {
      return true;
    }
    try {
      const v = await this.store.get(KEY_IMMERSIVE, true);
      return v === true;
    } catch (e) {
      Log.error('get immersive light failed');
      return true;
    }
  }

  async setImmersiveLight(on: boolean): Promise<void> {
    if (this.store === null) {
      return;
    }
    try {
      await this.store.put(KEY_IMMERSIVE, on);
      await this.store.flush();
    } catch (e) {
      Log.error('set immersive light failed');
    }
  }

  /** 聊天页头部宠物显隐（默认开） */
  async getPetVisible(): Promise<boolean> {
    if (this.store === null) {
      return true;
    }
    try {
      const v = await this.store.get(KEY_PET_VISIBLE, true);
      return v === true;
    } catch (e) {
      Log.error('get pet visible failed');
      return true;
    }
  }

  async setPetVisible(on: boolean): Promise<void> {
    if (this.store === null) {
      return;
    }
    try {
      await this.store.put(KEY_PET_VISIBLE, on);
      await this.store.flush();
    } catch (e) {
      Log.error('set pet visible failed');
    }
  }

  async getAppearance(): Promise<string> {
    return await this.getString(KEY_APPEARANCE);
  }

  async setAppearance(mode: string): Promise<void> {
    await this.putString(KEY_APPEARANCE, mode);
  }

  async getTtsSpeed(): Promise<number> {
    return await this.getNumber(KEY_TTS_SPEED, 1.0);
  }

  async setTtsSpeed(value: number): Promise<void> {
    await this.putString(KEY_TTS_SPEED, `${value}`);
  }

  async getTtsPitch(): Promise<number> {
    return await this.getNumber(KEY_TTS_PITCH, 1.0);
  }

  async setTtsPitch(value: number): Promise<void> {
    await this.putString(KEY_TTS_PITCH, `${value}`);
  }

  async getTtsVolume(): Promise<number> {
    return await this.getNumber(KEY_TTS_VOLUME, 2);
  }

  async setTtsVolume(value: number): Promise<void> {
    await this.putString(KEY_TTS_VOLUME, `${value}`);
  }

  async getTtsPerson(): Promise<number> {
    return await this.getNumber(KEY_TTS_PERSON, 13);
  }

  async setTtsPerson(value: number): Promise<void> {
    await this.putString(KEY_TTS_PERSON, `${value}`);
  }

  async getTtsOnline(): Promise<number> {
    return await this.getNumber(KEY_TTS_ONLINE, 1);
  }

  async setTtsOnline(value: number): Promise<void> {
    await this.putString(KEY_TTS_ONLINE, `${value}`);
  }

  /** 数值键读取：字符串 → number 归一，NaN/缺失回退默认值 */
  private async getNumber(key: string, def: number): Promise<number> {
    const raw = await this.getString(key);
    if (raw === '') {
      return def;
    }
    const value = Number(raw);
    return Number.isNaN(value) ? def : value;
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
