import { AppPrefs, UserProfilePref } from './AppPrefs';
import { TokenVault } from './TokenVault';
import { HttpClient } from '../net/HttpClient';
import { LoginResultModel } from '../model/AuthModels';
import { AgentModel } from '../model/AgentModels';

/**
 * 会话级全局状态（AppStorage）管理：
 * - 登录态与用户信息
 * - 当前选中的专家（agent）
 * - 线程列表脏标记（聊天页退出/切换专家后通知列表刷新）
 */
export class SessionStore {
  static readonly KEY_LOGGED_IN = 'session.loggedIn';
  static readonly KEY_BASE_URL = 'session.baseUrl';
  static readonly KEY_USERNAME = 'session.username';
  static readonly KEY_DISPLAY_NAME = 'session.displayName';
  static readonly KEY_ROLE = 'session.role';
  static readonly KEY_AGENT_ID = 'session.currentAgentId';
  static readonly KEY_AGENT_NAME = 'session.currentAgentName';
  static readonly KEY_AGENT_WELCOME = 'session.currentAgentWelcome';
  static readonly KEY_AGENT_MODEL = 'session.currentAgentModel';
  static readonly KEY_ACTIVE_THREAD_ID = 'session.activeThreadId';
  static readonly KEY_MAIN_TAB = 'session.mainTab';
  static readonly KEY_THREADS_DIRTY = 'chat.threadsDirty';
  static readonly KEY_AGENTS_DIRTY = 'expert.agentsDirty';

  /** 应用冷启动恢复：读取偏好与安全存储，重建运行时会话 */
  static async restore(context: Context): Promise<void> {
    HttpClient.getInstance().setUnauthorizedHandler((): void => {
      SessionStore.handleUnauthorized();
    });
    await AppPrefs.getInstance().init(context);
    const serverUrl: string = await AppPrefs.getInstance().getServerUrl();
    const token: string = TokenVault.loadToken();
    if (serverUrl === '' || token === '') {
      return;
    }
    const profile: UserProfilePref = await AppPrefs.getInstance().getProfile();
    const client = HttpClient.getInstance();
    client.setBaseUrl(serverUrl);
    client.setToken(token);
    AppStorage.setOrCreate(SessionStore.KEY_BASE_URL, serverUrl);
    AppStorage.setOrCreate(SessionStore.KEY_USERNAME, profile.username);
    AppStorage.setOrCreate(SessionStore.KEY_DISPLAY_NAME, profile.displayName);
    AppStorage.setOrCreate(SessionStore.KEY_ROLE, profile.role);
    AppStorage.setOrCreate(SessionStore.KEY_LOGGED_IN, true);
  }

  /** 登录成功后写入会话与持久化存储 */
  static applyLogin(baseUrl: string, result: LoginResultModel): void {
    TokenVault.saveToken(result.token);
    const client = HttpClient.getInstance();
    client.setBaseUrl(baseUrl);
    client.setToken(result.token);
    AppStorage.setOrCreate(SessionStore.KEY_BASE_URL, baseUrl);
    AppStorage.setOrCreate(SessionStore.KEY_USERNAME, result.user.username);
    AppStorage.setOrCreate(SessionStore.KEY_DISPLAY_NAME, result.user.displayName);
    AppStorage.setOrCreate(SessionStore.KEY_ROLE, result.user.role);
    AppStorage.setOrCreate(SessionStore.KEY_AGENT_ID, '');
    AppStorage.setOrCreate(SessionStore.KEY_AGENT_NAME, '');
    AppStorage.setOrCreate(SessionStore.KEY_AGENT_WELCOME, '');
    AppStorage.setOrCreate(SessionStore.KEY_AGENT_MODEL, '');
    AppStorage.setOrCreate(SessionStore.KEY_LOGGED_IN, true);
    AppPrefs.getInstance().setServerUrl(baseUrl);
    AppPrefs.getInstance().saveProfile(new UserProfilePref(
      result.user.username, result.user.displayName, result.user.role));
  }

  /** 401/Token 失效：清除会话回到登录页 */
  static handleUnauthorized(): void {
    TokenVault.clearToken();
    HttpClient.getInstance().setToken('');
    AppStorage.setOrCreate(SessionStore.KEY_AGENT_ID, '');
    AppStorage.setOrCreate(SessionStore.KEY_AGENT_NAME, '');
    AppStorage.setOrCreate(SessionStore.KEY_AGENT_WELCOME, '');
    AppStorage.setOrCreate(SessionStore.KEY_AGENT_MODEL, '');
    AppStorage.setOrCreate(SessionStore.KEY_ACTIVE_THREAD_ID, '');
    AppStorage.setOrCreate(SessionStore.KEY_MAIN_TAB, 0);
    AppStorage.setOrCreate(SessionStore.KEY_LOGGED_IN, false);
  }

  /** 用户主动退出 */
  static logout(): void {
    HttpClient.getInstance().post('/api/auth/logout', '{}').catch((): void => {
    });
    SessionStore.handleUnauthorized();
    AppPrefs.getInstance().clearAll();
  }

  /** 切换当前专家 */
  static setCurrentAgent(agent: AgentModel): void {
    AppStorage.setOrCreate(SessionStore.KEY_AGENT_ID, agent.agentId);
    AppStorage.setOrCreate(SessionStore.KEY_AGENT_NAME, agent.name);
    AppStorage.setOrCreate(SessionStore.KEY_AGENT_WELCOME, agent.welcomeMessage);
    AppStorage.setOrCreate(SessionStore.KEY_AGENT_MODEL, agent.defaultModel);
    AppStorage.setOrCreate(SessionStore.KEY_THREADS_DIRTY, true);
  }

  /** 专家列表发生变化（创建/编辑/删除/启停）后通知专家页刷新 */
  static markAgentsDirty(): void {
    AppStorage.setOrCreate(SessionStore.KEY_AGENTS_DIRTY, true);
  }
}
