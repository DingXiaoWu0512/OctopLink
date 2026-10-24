import { JsonHelper } from '../utils/JsonHelper';
import { OctopApiError } from '../net/HttpClient';

/**
 * 专家模板与欢迎卡片模型：
 * - BuiltinExpertModel：GET /api/experts 内置专家模板
 * - HubExpertModel / HubExpertListModel：GET /api/experts/hub 市场专家
 * - WelcomeCardModel：GET /api/agents/{id}/chat/welcome 空会话欢迎卡片
 */

/** 内置专家模板（GET /api/experts 列表项） */
export class BuiltinExpertModel {
  readonly id: string;
  readonly label: string;
  readonly description: string;
  readonly welcomeMessage: string;
  readonly iconName: string;
  readonly iconUrl: string;
  readonly color: string;
  readonly quickPrompts: Array<string>;
  readonly taskExamples: Array<string>;

  constructor(id: string, label: string, description: string, welcomeMessage: string,
    iconName: string, iconUrl: string, color: string, quickPrompts: Array<string>,
    taskExamples: Array<string>) {
    this.id = id;
    this.label = label === '' ? '专家模板' : label;
    this.description = description;
    this.welcomeMessage = welcomeMessage;
    this.iconName = iconName;
    this.iconUrl = iconUrl;
    this.color = color;
    this.quickPrompts = quickPrompts;
    this.taskExamples = taskExamples;
  }

  static fromRecord(rec: Record<string, Object>): BuiltinExpertModel {
    return new BuiltinExpertModel(
      JsonHelper.getString(rec, 'id', ''),
      ExpertJsonHelper.localizedString(rec, 'label'),
      ExpertJsonHelper.localizedString(rec, 'description'),
      ExpertJsonHelper.localizedString(rec, 'welcome_message'),
      JsonHelper.getString(rec, 'icon_name', ''),
      JsonHelper.getString(rec, 'icon_url', ''),
      JsonHelper.getString(rec, 'color', ''),
      ExpertJsonHelper.localizedStringArray(rec, 'quick_prompts'),
      ExpertJsonHelper.localizedStringArray(rec, 'task_examples')
    );
  }

  static parseList(text: string): Array<BuiltinExpertModel> {
    const result: Array<BuiltinExpertModel> = [];
    const arr = JsonHelper.parseArray(text);
    if (arr !== null) {
      for (const rec of arr) {
        result.push(BuiltinExpertModel.fromRecord(rec));
      }
      return result;
    }
    const obj = JsonHelper.parse(text);
    const items = JsonHelper.getRecordArray(obj, 'experts');
    for (const rec of items) {
      result.push(BuiltinExpertModel.fromRecord(rec));
    }
    return result;
  }
}

/** 市场专家卡片（GET /api/experts/hub items 元素） */
export class HubExpertModel {
  readonly id: string;
  readonly slug: string;
  readonly label: string;
  readonly description: string;
  readonly scene: string;
  readonly subScene: string;
  readonly iconUrl: string;
  readonly iconName: string;
  readonly color: string;
  readonly skillCount: number;
  readonly quickPrompts: Array<string>;

  constructor(id: string, slug: string, label: string, description: string, scene: string,
    subScene: string, iconUrl: string, iconName: string, color: string, skillCount: number,
    quickPrompts: Array<string>) {
    this.id = id;
    this.slug = slug;
    this.label = label === '' ? slug : label;
    this.description = description;
    this.scene = scene;
    this.subScene = subScene;
    this.iconUrl = iconUrl;
    this.iconName = iconName;
    this.color = color;
    this.skillCount = skillCount;
    this.quickPrompts = quickPrompts;
  }

  static fromRecord(rec: Record<string, Object>): HubExpertModel {
    return new HubExpertModel(
      JsonHelper.getString(rec, 'id', ''),
      JsonHelper.getString(rec, 'slug', ''),
      ExpertJsonHelper.localizedString(rec, 'label'),
      ExpertJsonHelper.localizedString(rec, 'description'),
      JsonHelper.getString(rec, 'scene', ''),
      JsonHelper.getString(rec, 'sub_scene', ''),
      JsonHelper.getString(rec, 'icon_url', ''),
      JsonHelper.getString(rec, 'icon_name', ''),
      JsonHelper.getString(rec, 'color', ''),
      JsonHelper.getNumber(rec, 'skill_count', 0),
      ExpertJsonHelper.localizedStringArray(rec, 'quick_prompts')
    );
  }
}

/** 市场专家列表（GET /api/experts/hub 响应） */
export class HubExpertListModel {
  readonly items: Array<HubExpertModel>;
  readonly scenes: Array<string>;

  constructor(items: Array<HubExpertModel>, scenes: Array<string>) {
    this.items = items;
    this.scenes = scenes;
  }

  static parse(text: string): HubExpertListModel {
    const rec = JsonHelper.parse(text);
    if (rec === null) {
      throw new OctopApiError('专家市场响应格式错误', 0, 'BAD_RESPONSE');
    }
    const items: Array<HubExpertModel> = [];
    const itemRecs = JsonHelper.getRecordArray(rec, 'items');
    for (const itemRec of itemRecs) {
      items.push(HubExpertModel.fromRecord(itemRec));
    }
    return new HubExpertListModel(items, JsonHelper.getStringArray(rec, 'scenes'));
  }
}

/** 空会话欢迎卡片（GET /api/agents/{id}/chat/welcome） */
export class WelcomeCardModel {
  readonly message: string;
  readonly quickPrompts: Array<string>;

  constructor(message: string, quickPrompts: Array<string>) {
    this.message = message;
    this.quickPrompts = quickPrompts;
  }

  static parse(text: string): WelcomeCardModel {
    const rec = JsonHelper.parse(text);
    if (rec === null) {
      throw new OctopApiError('欢迎信息响应格式错误', 0, 'BAD_RESPONSE');
    }
    return new WelcomeCardModel(
      ExpertJsonHelper.localizedString(rec, 'welcome_message'),
      ExpertJsonHelper.localizedStringArray(rec, 'quick_prompts')
    );
  }
}

/** 用户发布的私有专家模板（GET /api/experts/published 列表项） */
export class PublishedExpertModel {
  readonly id: string;
  readonly label: string;
  readonly description: string;
  readonly iconName: string;
  readonly iconUrl: string;
  readonly color: string;
  readonly welcomeMessage: string;
  readonly quickPrompts: Array<string>;
  readonly ownerUsername: string;

  constructor(id: string, label: string, description: string, iconName: string,
    iconUrl: string, color: string, welcomeMessage: string, quickPrompts: Array<string>,
    ownerUsername: string) {
    this.id = id;
    this.label = label === '' ? '已发布专家' : label;
    this.description = description;
    this.iconName = iconName;
    this.iconUrl = iconUrl;
    this.color = color;
    this.welcomeMessage = welcomeMessage;
    this.quickPrompts = quickPrompts;
    this.ownerUsername = ownerUsername;
  }

  static fromRecord(rec: Record<string, Object>): PublishedExpertModel {
    let label: string = ExpertJsonHelper.localizedString(rec, 'label');
    if (label === '') {
      label = JsonHelper.getString(rec, 'name', '');
    }
    return new PublishedExpertModel(
      JsonHelper.getString(rec, 'id', ''),
      label,
      ExpertJsonHelper.localizedString(rec, 'description'),
      JsonHelper.getString(rec, 'icon_name', ''),
      JsonHelper.getString(rec, 'icon_url', ''),
      JsonHelper.getString(rec, 'color', ''),
      ExpertJsonHelper.localizedString(rec, 'welcome_message'),
      ExpertJsonHelper.localizedStringArray(rec, 'quick_prompts'),
      JsonHelper.getString(rec, 'owner_username', '')
    );
  }

  static parseList(text: string): Array<PublishedExpertModel> {
    const result: Array<PublishedExpertModel> = [];
    const arr = JsonHelper.parseArray(text);
    if (arr !== null) {
      for (const rec of arr) {
        result.push(PublishedExpertModel.fromRecord(rec));
      }
      return result;
    }
    const obj = JsonHelper.parse(text);
    const itemRecs: Array<Record<string, Object>> = JsonHelper.getRecordArray(obj, 'experts');
    for (const rec of itemRecs) {
      result.push(PublishedExpertModel.fromRecord(rec));
    }
    const publishedRecs: Array<Record<string, Object>> = JsonHelper.getRecordArray(obj, 'published');
    for (const rec of publishedRecs) {
      result.push(PublishedExpertModel.fromRecord(rec));
    }
    return result;
  }
}

/** 模板/市场详情中的文件内容（{name, content}） */
export class NameContentModel {
  readonly name: string;
  readonly content: string;

  constructor(name: string, content: string) {
    this.name = name;
    this.content = content;
  }
}

/** 专家模板详情（GET /api/experts/{id} / GET /api/experts/hub/{slug}） */
export class ExpertDetailModel {
  readonly label: string;
  readonly description: string;
  readonly welcomeMessage: string;
  readonly quickPrompts: Array<string>;
  readonly taskExamples: Array<string>;
  readonly fileContents: Array<NameContentModel>;

  constructor(label: string, description: string, welcomeMessage: string,
    quickPrompts: Array<string>, taskExamples: Array<string>,
    fileContents: Array<NameContentModel>) {
    this.label = label === '' ? '专家模板' : label;
    this.description = description;
    this.welcomeMessage = welcomeMessage;
    this.quickPrompts = quickPrompts;
    this.taskExamples = taskExamples;
    this.fileContents = fileContents;
  }

  static parse(text: string): ExpertDetailModel {
    const rec = JsonHelper.parse(text);
    if (rec === null) {
      throw new OctopApiError('专家详情响应格式错误', 0, 'BAD_RESPONSE');
    }
    let label: string = ExpertJsonHelper.localizedString(rec, 'label');
    if (label === '') {
      label = JsonHelper.getString(rec, 'name', '');
    }
    return new ExpertDetailModel(
      label,
      ExpertJsonHelper.localizedString(rec, 'description'),
      ExpertJsonHelper.localizedString(rec, 'welcome_message'),
      ExpertJsonHelper.localizedStringArray(rec, 'quick_prompts'),
      ExpertJsonHelper.localizedStringArray(rec, 'task_examples'),
      ExpertDetailModel.parseFileContents(rec)
    );
  }

  /** file_contents 兼容 [{name,content}] 与 {name: content} 两种形态 */
  static parseFileContents(rec: Record<string, Object>): Array<NameContentModel> {
    const result: Array<NameContentModel> = [];
    const value: Object | undefined = rec['file_contents'];
    if (value === undefined || value === null) {
      return result;
    }
    if (Array.isArray(value)) {
      const arr: Object[] = value as Object[];
      for (let i = 0; i < arr.length; i++) {
        const itemRec: Record<string, Object> | null = JsonHelper.toRecord(arr[i]);
        if (itemRec !== null) {
          result.push(new NameContentModel(
            JsonHelper.getString(itemRec, 'name', ''),
            JsonHelper.getString(itemRec, 'content', '')
          ));
        }
      }
      return result;
    }
    const mapRec: Record<string, Object> | null = JsonHelper.toRecord(value);
    if (mapRec !== null) {
      const names: Array<string> = Object.keys(mapRec);
      for (const name of names) {
        const content: Object | undefined = mapRec[name];
        if (typeof content === 'string') {
          result.push(new NameContentModel(name, content));
        }
      }
    }
    return result;
  }
}

/** 本地化字段取值：兼容 string、{zh,en} 对象、元素为本地化对象的数组 */
class ExpertJsonHelper {
  /** 取本地化字符串：string 直接返回；{zh,en} 优先 zh */
  static localizedString(rec: Record<string, Object> | null, key: string): string {
    if (rec === null) {
      return '';
    }
    const value: Object | undefined = rec[key];
    if (typeof value === 'string') {
      return value;
    }
    const locRec = JsonHelper.toRecord(value);
    if (locRec !== null) {
      const zh: string = JsonHelper.getString(locRec, 'zh', '');
      return zh !== '' ? zh : JsonHelper.getString(locRec, 'en', '');
    }
    return '';
  }

  /** 取本地化字符串数组：string[] 直接返回；[{zh,en}] 取本地化文本 */
  static localizedStringArray(rec: Record<string, Object> | null, key: string): Array<string> {
    const result: Array<string> = [];
    if (rec === null) {
      return result;
    }
    const value: Object | undefined = rec[key];
    if (value === undefined || value === null || !Array.isArray(value)) {
      return result;
    }
    const arr: Object[] = value as Object[];
    for (let i = 0; i < arr.length; i++) {
      const item: Object = arr[i];
      if (typeof item === 'string') {
        result.push(item);
      } else {
        const locRec = JsonHelper.toRecord(item);
        if (locRec !== null) {
          const zh: string = JsonHelper.getString(locRec, 'zh', '');
          result.push(zh !== '' ? zh : JsonHelper.getString(locRec, 'en', ''));
        }
      }
    }
    return result;
  }
}
