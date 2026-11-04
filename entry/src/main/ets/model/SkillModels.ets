import { JsonHelper } from '../utils/JsonHelper';

/**
 * 技能域数据模型（源：octop/api/routers/skills.py、skill_packages.py、
 * subagents.py、agent_tools.py）：
 * - SkillSummaryModel / SkillDetailModel：技能摘要与详情
 * - SkillFileModel：技能文件（content_base64）
 * - SkillPackageModel：技能包
 * - SubagentDivisionModel / SubagentCatalogItemModel / InstalledSubagentModel：子代理
 * - ToolSettingItemModel：agent 工具开关
 * - HubSkillModel / HubRankingSectionModel：SkillHub 市场
 */

/** 技能文件（CreateSkillBody.files 元素） */
export class SkillFileModel {
  readonly path: string;
  readonly contentBase64: string;

  constructor(path: string, contentBase64: string) {
    this.path = path;
    this.contentBase64 = contentBase64;
  }
}

/** 技能摘要（skills.py _summary_dict + apply_skill_presentation 展示扩展） */
export class SkillSummaryModel {
  readonly slug: string;
  readonly name: string;
  readonly description: string;
  readonly enabled: boolean;
  readonly kind: string; // builtin | workspace | package
  readonly displayName: string;
  readonly labelZh: string;
  readonly labelEn: string;
  readonly summaryZh: string;
  readonly summaryEn: string;
  readonly emoji: string;
  readonly iconUrl: string;
  readonly path: string;
  readonly packageId: string;

  constructor(slug: string, name: string, description: string, enabled: boolean, kind: string,
    displayName: string, labelZh: string, labelEn: string, summaryZh: string, summaryEn: string,
    emoji: string, iconUrl: string, path: string, packageId: string) {
    this.slug = slug;
    this.name = name;
    this.description = description;
    this.enabled = enabled;
    this.kind = kind;
    this.displayName = displayName;
    this.labelZh = labelZh;
    this.labelEn = labelEn;
    this.summaryZh = summaryZh;
    this.summaryEn = summaryEn;
    this.emoji = emoji;
    this.iconUrl = iconUrl;
    this.path = path;
    this.packageId = packageId;
  }

  /** 展示名：display_name > label.zh > name */
  displayTitle(): string {
    if (this.displayName !== '') {
      return this.displayName;
    }
    if (this.labelZh !== '') {
      return this.labelZh;
    }
    return this.name;
  }

  /** 展示摘要：summary.zh > description */
  displaySummary(): string {
    if (this.summaryZh !== '') {
      return this.summaryZh;
    }
    return this.description;
  }

  static fromRecord(rec: Record<string, Object>): SkillSummaryModel {
    const label: Record<string, Object> | null = JsonHelper.getRecord(rec, 'label');
    const summary: Record<string, Object> | null = JsonHelper.getRecord(rec, 'summary');
    return new SkillSummaryModel(
      JsonHelper.getString(rec, 'slug', ''),
      JsonHelper.getString(rec, 'name', ''),
      JsonHelper.getString(rec, 'description', ''),
      JsonHelper.getBool(rec, 'enabled', true),
      JsonHelper.getString(rec, 'kind', 'workspace'),
      JsonHelper.getString(rec, 'display_name', ''),
      label === null ? '' : JsonHelper.getString(label, 'zh', ''),
      label === null ? '' : JsonHelper.getString(label, 'en', ''),
      summary === null ? '' : JsonHelper.getString(summary, 'zh', ''),
      summary === null ? '' : JsonHelper.getString(summary, 'en', ''),
      JsonHelper.getString(rec, 'emoji', ''),
      JsonHelper.getString(rec, 'icon_url', ''),
      JsonHelper.getString(rec, 'path', ''),
      JsonHelper.getString(rec, 'package_id', '')
    );
  }

  static parseList(text: string): Array<SkillSummaryModel> {
    const result: Array<SkillSummaryModel> = [];
    const arr = JsonHelper.parseArray(text);
    if (arr === null) {
      return result;
    }
    for (const rec of arr) {
      result.push(SkillSummaryModel.fromRecord(rec));
    }
    return result;
  }
}

/** 技能详情（GET /api/agents/{id}/skills/{name}） */
export class SkillDetailModel {
  readonly summary: SkillSummaryModel;
  readonly frontmatterJson: string;
  readonly body: string;
  readonly raw: string;

  constructor(summary: SkillSummaryModel, frontmatterJson: string, body: string, raw: string) {
    this.summary = summary;
    this.frontmatterJson = frontmatterJson;
    this.body = body;
    this.raw = raw;
  }

  static parse(text: string): SkillDetailModel {
    const rec = JsonHelper.parse(text);
    if (rec === null) {
      return new SkillDetailModel(SkillSummaryModel.fromRecord({}), '', '', '');
    }
    const frontmatter: Record<string, Object> | null = JsonHelper.getRecord(rec, 'frontmatter');
    return new SkillDetailModel(
      SkillSummaryModel.fromRecord(rec),
      frontmatter === null ? '{}' : JSON.stringify(frontmatter),
      JsonHelper.getString(rec, 'body', ''),
      JsonHelper.getString(rec, 'raw', '')
    );
  }
}

/** 技能包（skill_packages.py _row_public_dict + 列表扩展字段） */
export class SkillPackageModel {
  readonly id: string;
  readonly name: string;
  readonly description: string;
  readonly createdBy: string;
  readonly skillCount: number;
  readonly iconName: string;
  readonly iconUrl: string;
  readonly copyPolicy: string; // snapshot | lock | deny
  readonly allowDownload: boolean;
  readonly shared: boolean;
  readonly visibility: string; // all | groups | owner
  readonly creatorUsername: string;
  readonly creatorDisplayName: string;
  readonly createdAtMs: number;
  readonly updatedAtMs: number;
  readonly skills: Array<SkillSummaryModel>;
  readonly canWrite: boolean;
  readonly canCopy: boolean;
  readonly canDownload: boolean;

  constructor(id: string, name: string, description: string, createdBy: string, skillCount: number,
    iconName: string, iconUrl: string, copyPolicy: string, allowDownload: boolean, shared: boolean,
    visibility: string, creatorUsername: string, creatorDisplayName: string, createdAtMs: number,
    updatedAtMs: number, skills: Array<SkillSummaryModel>, canWrite: boolean, canCopy: boolean,
    canDownload: boolean) {
    this.id = id;
    this.name = name;
    this.description = description;
    this.createdBy = createdBy;
    this.skillCount = skillCount;
    this.iconName = iconName;
    this.iconUrl = iconUrl;
    this.copyPolicy = copyPolicy;
    this.allowDownload = allowDownload;
    this.shared = shared;
    this.visibility = visibility;
    this.creatorUsername = creatorUsername;
    this.creatorDisplayName = creatorDisplayName;
    this.createdAtMs = createdAtMs;
    this.updatedAtMs = updatedAtMs;
    this.skills = skills;
    this.canWrite = canWrite;
    this.canCopy = canCopy;
    this.canDownload = canDownload;
  }

  static fromRecord(rec: Record<string, Object>): SkillPackageModel {
    const skills: Array<SkillSummaryModel> = [];
    const skillRecords: Array<Record<string, Object>> = JsonHelper.getRecordArray(rec, 'skills');
    for (const skillRec of skillRecords) {
      skills.push(SkillSummaryModel.fromRecord(skillRec));
    }
    return new SkillPackageModel(
      JsonHelper.getString(rec, 'id', ''),
      JsonHelper.getString(rec, 'name', ''),
      JsonHelper.getString(rec, 'description', ''),
      JsonHelper.getString(rec, 'created_by', ''),
      JsonHelper.getNumber(rec, 'skill_count', 0),
      JsonHelper.getString(rec, 'icon_name', ''),
      JsonHelper.getString(rec, 'icon_url', ''),
      JsonHelper.getString(rec, 'copy_policy', 'snapshot'),
      JsonHelper.getBool(rec, 'allow_download', true),
      JsonHelper.getBool(rec, 'shared', false),
      JsonHelper.getString(rec, 'visibility', 'all'),
      JsonHelper.getString(rec, 'creator_username', ''),
      JsonHelper.getString(rec, 'creator_display_name', ''),
      JsonHelper.toMs(rec['created_at']),
      JsonHelper.toMs(rec['updated_at']),
      skills,
      JsonHelper.getBool(rec, 'can_write', true),
      JsonHelper.getBool(rec, 'can_copy', true),
      JsonHelper.getBool(rec, 'can_download', true)
    );
  }

  static parseList(text: string): Array<SkillPackageModel> {
    const result: Array<SkillPackageModel> = [];
    const arr = JsonHelper.parseArray(text);
    if (arr === null) {
      return result;
    }
    for (const rec of arr) {
      result.push(SkillPackageModel.fromRecord(rec));
    }
    return result;
  }
}

/** 子代理分区（GET /api/subagent-catalog/divisions） */
export class SubagentDivisionModel {
  readonly id: string;
  readonly label: string;
  readonly icon: string;
  readonly color: string;
  readonly count: number;
  readonly labelEn: string;
  readonly labelZh: string;

  constructor(id: string, label: string, icon: string, color: string, count: number,
    labelEn: string, labelZh: string) {
    this.id = id;
    this.label = label;
    this.icon = icon;
    this.color = color;
    this.count = count;
    this.labelEn = labelEn;
    this.labelZh = labelZh;
  }

  static fromRecord(rec: Record<string, Object>): SubagentDivisionModel {
    const labels: Record<string, Object> | null = JsonHelper.getRecord(rec, 'labels');
    return new SubagentDivisionModel(
      JsonHelper.getString(rec, 'id', ''),
      JsonHelper.getString(rec, 'label', ''),
      JsonHelper.getString(rec, 'icon', ''),
      JsonHelper.getString(rec, 'color', ''),
      JsonHelper.getNumber(rec, 'count', 0),
      labels === null ? '' : JsonHelper.getString(labels, 'en', ''),
      labels === null ? '' : JsonHelper.getString(labels, 'zh', '')
    );
  }

  static parseList(text: string): Array<SubagentDivisionModel> {
    const result: Array<SubagentDivisionModel> = [];
    const arr = JsonHelper.parseArray(text);
    if (arr === null) {
      return result;
    }
    for (const rec of arr) {
      result.push(SubagentDivisionModel.fromRecord(rec));
    }
    return result;
  }
}

/** 子代理目录项（GET /api/subagent-catalog；name/description 为 locale map） */
export class SubagentCatalogItemModel {
  readonly slug: string;
  readonly division: string;
  readonly nameZh: string;
  readonly nameEn: string;
  readonly descZh: string;
  readonly descEn: string;
  readonly emoji: string;
  readonly color: string;
  readonly availableLocales: Array<string>;
  readonly contentZh: string;
  readonly contentEn: string;

  constructor(slug: string, division: string, nameZh: string, nameEn: string, descZh: string,
    descEn: string, emoji: string, color: string, availableLocales: Array<string>,
    contentZh: string, contentEn: string) {
    this.slug = slug;
    this.division = division;
    this.nameZh = nameZh;
    this.nameEn = nameEn;
    this.descZh = descZh;
    this.descEn = descEn;
    this.emoji = emoji;
    this.color = color;
    this.availableLocales = availableLocales;
    this.contentZh = contentZh;
    this.contentEn = contentEn;
  }

  displayTitle(): string {
    return this.nameZh !== '' ? this.nameZh : this.nameEn;
  }

  displayDesc(): string {
    return this.descZh !== '' ? this.descZh : this.descEn;
  }

  /** markdown 正文（优先中文） */
  displayContent(): string {
    return this.contentZh !== '' ? this.contentZh : this.contentEn;
  }

  static fromRecord(rec: Record<string, Object>): SubagentCatalogItemModel {
    const name: Record<string, Object> | null = JsonHelper.getRecord(rec, 'name');
    const desc: Record<string, Object> | null = JsonHelper.getRecord(rec, 'description');
    const content: Record<string, Object> | null = JsonHelper.getRecord(rec, 'content');
    return new SubagentCatalogItemModel(
      JsonHelper.getString(rec, 'slug', ''),
      JsonHelper.getString(rec, 'division', ''),
      name === null ? '' : JsonHelper.getString(name, 'zh', ''),
      name === null ? '' : JsonHelper.getString(name, 'en', ''),
      desc === null ? '' : JsonHelper.getString(desc, 'zh', ''),
      desc === null ? '' : JsonHelper.getString(desc, 'en', ''),
      JsonHelper.getString(rec, 'emoji', ''),
      JsonHelper.getString(rec, 'color', ''),
      JsonHelper.getStringArray(rec, 'available_locales'),
      content === null ? '' : JsonHelper.getString(content, 'zh', ''),
      content === null ? '' : JsonHelper.getString(content, 'en', '')
    );
  }

  static parseList(text: string): Array<SubagentCatalogItemModel> {
    const result: Array<SubagentCatalogItemModel> = [];
    const arr = JsonHelper.parseArray(text);
    if (arr === null) {
      return result;
    }
    for (const rec of arr) {
      result.push(SubagentCatalogItemModel.fromRecord(rec));
    }
    return result;
  }
}

/** agent 已安装子代理（GET /api/agents/{id}/subagents） */
export class InstalledSubagentModel {
  readonly slug: string;
  readonly name: string;
  readonly description: string;
  readonly path: string;
  readonly color: string;

  constructor(slug: string, name: string, description: string, path: string, color: string) {
    this.slug = slug;
    this.name = name;
    this.description = description;
    this.path = path;
    this.color = color;
  }

  static fromRecord(rec: Record<string, Object>): InstalledSubagentModel {
    return new InstalledSubagentModel(
      JsonHelper.getString(rec, 'slug', ''),
      JsonHelper.getString(rec, 'name', ''),
      JsonHelper.getString(rec, 'description', ''),
      JsonHelper.getString(rec, 'path', ''),
      JsonHelper.getString(rec, 'color', '')
    );
  }

  static parseList(text: string): Array<InstalledSubagentModel> {
    const result: Array<InstalledSubagentModel> = [];
    const arr = JsonHelper.parseArray(text);
    if (arr === null) {
      return result;
    }
    for (const rec of arr) {
      result.push(InstalledSubagentModel.fromRecord(rec));
    }
    return result;
  }
}

/** agent 工具开关项（agent_tools.py ToolSettingsItem） */
export class ToolSettingItemModel {
  readonly name: string;
  readonly source: string; // builtin | plugin
  readonly category: string;
  readonly label: string;
  readonly description: string;
  readonly enabled: boolean;
  readonly disableable: boolean;
  readonly available: boolean;
  readonly pluginId: string;
  readonly pluginName: string;
  readonly pluginIcon: string;

  constructor(name: string, source: string, category: string, label: string, description: string,
    enabled: boolean, disableable: boolean, available: boolean, pluginId: string,
    pluginName: string, pluginIcon: string) {
    this.name = name;
    this.source = source;
    this.category = category;
    this.label = label;
    this.description = description;
    this.enabled = enabled;
    this.disableable = disableable;
    this.available = available;
    this.pluginId = pluginId;
    this.pluginName = pluginName;
    this.pluginIcon = pluginIcon;
  }

  static fromRecord(rec: Record<string, Object>): ToolSettingItemModel {
    return new ToolSettingItemModel(
      JsonHelper.getString(rec, 'name', ''),
      JsonHelper.getString(rec, 'source', 'builtin'),
      JsonHelper.getString(rec, 'category', ''),
      JsonHelper.getString(rec, 'label', ''),
      JsonHelper.getString(rec, 'description', ''),
      JsonHelper.getBool(rec, 'enabled', true),
      JsonHelper.getBool(rec, 'disableable', false),
      JsonHelper.getBool(rec, 'available', true),
      JsonHelper.getString(rec, 'plugin_id', ''),
      JsonHelper.getString(rec, 'plugin_name', ''),
      JsonHelper.getString(rec, 'plugin_icon', '')
    );
  }

  static parseList(text: string): Array<ToolSettingItemModel> {
    const result: Array<ToolSettingItemModel> = [];
    const rec = JsonHelper.parse(text);
    if (rec === null) {
      return result;
    }
    const items: Array<Record<string, Object>> = JsonHelper.getRecordArray(rec, 'tools');
    for (const item of items) {
      result.push(ToolSettingItemModel.fromRecord(item));
    }
    return result;
  }
}

/** SkillHub 搜索结果项（{slug, name, description, version} + 原始字段） */
export class HubSkillModel {
  readonly slug: string;
  readonly name: string;
  readonly description: string;
  readonly version: string;
  readonly iconUrl: string;

  constructor(slug: string, name: string, description: string, version: string, iconUrl: string) {
    this.slug = slug;
    this.name = name;
    this.description = description;
    this.version = version;
    this.iconUrl = iconUrl;
  }

  static fromRecord(rec: Record<string, Object>): HubSkillModel {
    // 图标键名两态兼容：rankings/showcase 响应为 'iconUrl'（驼峰），search 响应为 'icon_url'（下划线）
    let iconUrl: string = JsonHelper.getString(rec, 'iconUrl', '');
    if (iconUrl === '') {
      iconUrl = JsonHelper.getString(rec, 'icon_url', '');
    }
    return new HubSkillModel(
      JsonHelper.getString(rec, 'slug', ''),
      JsonHelper.getString(rec, 'name', ''),
      JsonHelper.getString(rec, 'description', ''),
      JsonHelper.getString(rec, 'version', ''),
      iconUrl
    );
  }

  static parseList(text: string): Array<HubSkillModel> {
    const result: Array<HubSkillModel> = [];
    const arr = JsonHelper.parseArray(text);
    if (arr === null) {
      return result;
    }
    for (const rec of arr) {
      result.push(HubSkillModel.fromRecord(rec));
    }
    return result;
  }
}

/** SkillHub 榜单分区（type=all 时 rankings map 的元素） */
export class HubRankingSectionModel {
  readonly section: string;
  readonly skills: Array<HubSkillModel>;
  readonly total: number;

  constructor(section: string, skills: Array<HubSkillModel>, total: number) {
    this.section = section;
    this.skills = skills;
    this.total = total;
  }

  static parseSections(text: string): Array<HubRankingSectionModel> {
    const result: Array<HubRankingSectionModel> = [];
    const rec = JsonHelper.parse(text);
    if (rec === null) {
      return result;
    }
    const rankings: Record<string, Object> | null = JsonHelper.getRecord(rec, 'rankings');
    if (rankings === null) {
      // type=具体榜单时顶层即分区对象
      const section: HubRankingSectionModel | null = HubRankingSectionModel.trySection('', rec);
      if (section !== null) {
        result.push(section);
      }
      return result;
    }
    const keys: Array<string> = Object.keys(rankings);
    for (const key of keys) {
      const sectionRec: Record<string, Object> | null = JsonHelper.getRecord(rankings, key);
      if (sectionRec === null) {
        continue;
      }
      const section: HubRankingSectionModel | null =
        HubRankingSectionModel.trySection(key, sectionRec);
      if (section !== null) {
        result.push(section);
      }
    }
    return result;
  }

  private static trySection(key: string,
    rec: Record<string, Object>): HubRankingSectionModel | null {
    const skills: Array<HubSkillModel> = [];
    const skillRecords: Array<Record<string, Object>> = JsonHelper.getRecordArray(rec, 'skills');
    for (const skillRec of skillRecords) {
      skills.push(HubSkillModel.fromRecord(skillRec));
    }
    const section: string = key !== '' ? key : JsonHelper.getString(rec, 'section', '');
    return new HubRankingSectionModel(section, skills, JsonHelper.getNumber(rec, 'total', 0));
  }
}
