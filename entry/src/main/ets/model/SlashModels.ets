import { JsonHelper } from '../utils/JsonHelper';

/**
 * 斜杠命令规格（GET /api/slash/commands?origin=ui），
 * 与 Octop Web 端 slash 菜单同源：服务端动态下发，失败时回退 fallbackList。
 */
export class SlashCommandSpec {
  readonly name: string;
  readonly command: string;
  readonly aliases: Array<string>;
  readonly usage: string;
  readonly icon: string;
  readonly tone: string;
  readonly category: string;
  readonly clientAction: string;
  readonly labelZh: string;
  readonly labelEn: string;
  readonly descriptionZh: string;
  readonly descriptionEn: string;

  constructor(name: string, command: string, aliases: Array<string>, usage: string, icon: string,
    tone: string, category: string, clientAction: string, labelZh: string, labelEn: string,
    descriptionZh: string, descriptionEn: string) {
    this.name = name;
    this.command = command;
    this.aliases = aliases;
    this.usage = usage;
    this.icon = icon;
    this.tone = tone;
    this.category = category;
    this.clientAction = clientAction;
    this.labelZh = labelZh;
    this.labelEn = labelEn;
    this.descriptionZh = descriptionZh;
    this.descriptionEn = descriptionEn;
  }

  /** 展示标签（中文优先） */
  label(): string {
    if (this.labelZh !== '') {
      return this.labelZh;
    }
    return this.labelEn !== '' ? this.labelEn : this.name;
  }

  /** 描述（中文优先） */
  description(): string {
    if (this.descriptionZh !== '') {
      return this.descriptionZh;
    }
    return this.descriptionEn;
  }

  /** 首个命令词："/model [x] | reset" → "/model"，异常回退 "/{name}" */
  commandToken(): string {
    const cmd: string = this.command.trim();
    const spIdx: number = cmd.indexOf(' ');
    const token: string = spIdx > 0 ? cmd.substring(0, spIdx) : cmd;
    if (token.startsWith('/') && token.length > 1) {
      return token;
    }
    return `/${this.name}`;
  }

  /** 是否需要用户补参数（usage 含 <> 或 [] 占位符） */
  needsInput(): boolean {
    const text: string = this.usage !== '' ? this.usage : this.command;
    return text.indexOf('<') >= 0 || text.indexOf('[') >= 0;
  }

  /** 选中预填文本（与 Web 端 slashCommandPrefillText 对齐，/agent 特殊化） */
  prefillText(): string {
    if (this.name === 'agent') {
      return '/agent switch ';
    }
    return `${this.commandToken()} `;
  }

  /** 过滤匹配：命令词/别名前缀或标签包含 */
  matches(query: string): boolean {
    if (query === '') {
      return true;
    }
    if (this.name.startsWith(query)) {
      return true;
    }
    for (const alias of this.aliases) {
      if (alias.startsWith(query)) {
        return true;
      }
    }
    if (this.labelZh.indexOf(query) >= 0) {
      return true;
    }
    if (this.labelEn.toLowerCase().indexOf(query.toLowerCase()) >= 0) {
      return true;
    }
    return false;
  }

  static fromRecord(rec: Record<string, Object>): SlashCommandSpec {
    return new SlashCommandSpec(
      JsonHelper.getString(rec, 'name', ''),
      JsonHelper.getString(rec, 'command', ''),
      JsonHelper.getStringArray(rec, 'aliases'),
      JsonHelper.getString(rec, 'usage', ''),
      JsonHelper.getString(rec, 'icon', ''),
      JsonHelper.getString(rec, 'tone', ''),
      JsonHelper.getString(rec, 'category', 'system'),
      JsonHelper.getString(rec, 'client_action', 'none'),
      JsonHelper.getString(rec, 'label_zh', ''),
      JsonHelper.getString(rec, 'label_en', ''),
      JsonHelper.getString(rec, 'description_zh', ''),
      JsonHelper.getString(rec, 'description_en', '')
    );
  }

  /** 解析 {commands:[...]} 响应 */
  static parseList(text: string): Array<SlashCommandSpec> {
    const result: Array<SlashCommandSpec> = [];
    const obj = JsonHelper.parse(text);
    const items = JsonHelper.getRecordArray(obj, 'commands');
    for (const rec of items) {
      const spec = SlashCommandSpec.fromRecord(rec);
      if (spec.name !== '') {
        result.push(spec);
      }
    }
    return result;
  }

  /** 服务端不可用时的内置回退（与 Web 端 SLASH_FALLBACK_META 同集） */
  static fallbackList(): Array<SlashCommandSpec> {
    const list: Array<SlashCommandSpec> = [];
    list.push(new SlashCommandSpec('status', '/status', [], '/status', 'Activity', 'blue',
      'core', 'none', '会话状态', 'Status', '查看当前会话状态', 'Session status'));
    list.push(new SlashCommandSpec('compact', '/compact', [], '/compact', 'Archive', 'violet',
      'core', 'none', '压缩记忆', 'Compact', '压缩当前会话上下文', 'Compact context'));
    list.push(new SlashCommandSpec('new', '/new', ['clear'], '/new [title]', 'RefreshCw', 'emerald',
      'core', 'new_chat', '新对话', 'New', '开启一个新的对话', 'Start a new chat'));
    list.push(new SlashCommandSpec('history', '/history', [], '/history', 'BarChart3', 'blue',
      'core', 'none', '对话统计', 'History', '查看对话统计信息', 'Chat statistics'));
    list.push(new SlashCommandSpec('list', '/list', ['topics', 'sessions'], '/list', 'List', 'amber',
      'session', 'none', '会话列表', 'List', '查看会话列表', 'List sessions'));
    list.push(new SlashCommandSpec('token', '/token', [], '/token', 'Coins', 'orange',
      'core', 'none', 'Token 用量', 'Token', '查看 Token 用量', 'Token usage'));
    return list;
  }
}

/** 面板分组视图（按 category 聚合） */
export class SlashGroup {
  readonly category: string;
  readonly label: string;
  readonly items: Array<SlashCommandSpec>;

  constructor(category: string, label: string, items: Array<SlashCommandSpec>) {
    this.category = category;
    this.label = label;
    this.items = items;
  }
}

/** 分组排序与中文标签（与 Web 端 SLASH_CATEGORY_ORDER/CATEGORY_LABELS 对齐） */
export class SlashCategory {
  static order(): Array<string> {
    return ['core', 'skills', 'session', 'media', 'system', 'debug'];
  }

  static label(category: string): string {
    if (category === 'core') {
      return '核心命令';
    }
    if (category === 'skills') {
      return '技能';
    }
    if (category === 'session') {
      return '会话管理';
    }
    if (category === 'media') {
      return '多媒体';
    }
    if (category === 'system') {
      return '系统';
    }
    if (category === 'debug') {
      return '调试';
    }
    return '其他';
  }
}
