/**
 * write_todos 工具清单解析器（桌面 dashboard parseWriteTodos.ts 的 ArkTS 移植，语义唯一权威参照）：
 * - 工具名带命名空间前缀（如 deepagents/write_todos）按 '/' 后缀匹配；
 * - payload 键兼容 todos/items/tasks，数组项兼容字符串与对象（content/text/title/description 取内容、id/key 取 id）；
 * - 状态归一化：done/complete→completed、running/active→in_progress，未知值回退 pending；
 * - 截断 argsText 部分解析：逐字符扫描完整 `{...}` 对象逐个 try/parse，失败静默跳过（不崩、不显示半截）；
 * - 按 id 合并（后写覆盖）+ 数字 id 升序排序（计划序 "2" 在 "10" 前），非数字 id 保持稳定序。
 * 纯函数（文件级函数、无 this、无副作用）；数据源恒为 ToolCallModel.argsText
 * （规避 tool_result resultText 的 500 字符截断与多工具并发错位风险）。
 */
import { JsonHelper } from './JsonHelper';

/** 清单项状态（ArkTS 不支持字面量联合类型标注，用枚举承载四个已知值） */
export enum TodoItemStatus {
  PENDING = 'pending',
  IN_PROGRESS = 'in_progress',
  COMPLETED = 'completed',
  CANCELLED = 'cancelled'
}

/** write_todos 清单项（id 为合并键，status 为归一化后的状态） */
export class TodoListItem {
  readonly id: string;
  readonly content: string;
  readonly status: TodoItemStatus;

  constructor(id: string, content: string, status: TodoItemStatus) {
    this.id = id;
    this.content = content;
    this.status = status;
  }
}

/** 工具名是否为 write_todos（'/' 后缀等于 write_todos 命中，如 deepagents/write_todos） */
export function isWriteTodosToolName(name: string): boolean {
  const trimmed: string = name.trim();
  const slash: number = trimmed.lastIndexOf('/');
  return (slash >= 0 ? trimmed.substring(slash + 1) : trimmed) === 'write_todos';
}

/** 状态归一化：done/complete→completed、running/active→in_progress，未知值回退 pending */
function normalizeStatus(raw: string): TodoItemStatus {
  const value: string = raw.trim().toLowerCase();
  if (value === TodoItemStatus.PENDING) {
    return TodoItemStatus.PENDING;
  }
  if (value === TodoItemStatus.IN_PROGRESS) {
    return TodoItemStatus.IN_PROGRESS;
  }
  if (value === TodoItemStatus.COMPLETED) {
    return TodoItemStatus.COMPLETED;
  }
  if (value === TodoItemStatus.CANCELLED) {
    return TodoItemStatus.CANCELLED;
  }
  if (value === 'done' || value === 'complete') {
    return TodoItemStatus.COMPLETED;
  }
  if (value === 'running' || value === 'active') {
    return TodoItemStatus.IN_PROGRESS;
  }
  return TodoItemStatus.PENDING;
}

/** 单项归一化：字符串项 → 序号 id + pending；对象项 → content/text/title/description 取内容、id/key 取 id */
function normalizeTodo(raw: Object, index: number): TodoListItem | null {
  if (typeof raw === 'string') {
    const content: string = (raw as string).trim();
    if (content === '') {
      return null;
    }
    return new TodoListItem(`${index + 1}`, content, TodoItemStatus.PENDING);
  }
  const row: Record<string, Object> | null = JsonHelper.toRecord(raw);
  if (row === null) {
    return null;
  }
  let content: string = JsonHelper.getString(row, 'content', '');
  if (content === '') {
    content = JsonHelper.getString(row, 'text', '');
  }
  if (content === '') {
    content = JsonHelper.getString(row, 'title', '');
  }
  if (content === '') {
    content = JsonHelper.getString(row, 'description', '');
  }
  const trimmedContent: string = content.trim();
  if (trimmedContent === '') {
    return null;
  }
  let id: string = JsonHelper.getString(row, 'id', '');
  if (id === '') {
    id = JsonHelper.getString(row, 'key', '');
  }
  if (id === '') {
    id = `${index + 1}`;
  }
  return new TodoListItem(id, trimmedContent, normalizeStatus(JsonHelper.getString(row, 'status', '')));
}

/** 数组项逐一归一化，剔除无效项 */
function normalizeTodoList(rawList: Object[]): Array<TodoListItem> {
  const result: Array<TodoListItem> = [];
  for (let i = 0; i < rawList.length; i++) {
    const item: TodoListItem | null = normalizeTodo(rawList[i], i);
    if (item !== null) {
      result.push(item);
    }
  }
  return result;
}

/** payload 提取：顶层为数组直接归一化；对象则依次取 todos/items/tasks 数组键（首个命中） */
function parseTodoPayload(raw: Object): Array<TodoListItem> {
  if (Array.isArray(raw)) {
    return normalizeTodoList(raw as Object[]);
  }
  const row: Record<string, Object> | null = JsonHelper.toRecord(raw);
  if (row === null) {
    return [];
  }
  const keys: string[] = ['todos', 'items', 'tasks'];
  for (const key of keys) {
    const value: Object | undefined = row[key];
    if (value !== undefined && value !== null && Array.isArray(value)) {
      return normalizeTodoList(value as Object[]);
    }
  }
  return [];
}

/** 完整解析 argsText（payload 键兼容 todos/items/tasks、字符串项兼容、状态归一化）；解析失败返回空数组 */
export function collectTodoItems(argsText: string): Array<TodoListItem> {
  const trimmed: string = argsText.trim();
  if (trimmed === '') {
    return [];
  }
  try {
    const parsed: Object | null = JSON.parse(trimmed);
    if (parsed === null) {
      return [];
    }
    return parseTodoPayload(parsed);
  } catch (e) {
    return [];
  }
}

/** 截断 argsText 部分解析：逐字符扫描提取完整 `{...}` 对象逐个解析，失败项静默跳过（不崩、不显示半截） */
export function parsePartialTodoItems(argsText: string): Array<TodoListItem> {
  const trimmed: string = argsText.trim();
  if (trimmed === '') {
    return [];
  }
  const byId: Map<string, TodoListItem> = new Map<string, TodoListItem>();
  const stack: Array<number> = [];
  for (let i = 0; i < trimmed.length; i++) {
    const ch: string = trimmed.charAt(i);
    if (ch === '{') {
      stack.push(i);
    } else if (ch === '}' && stack.length > 0) {
      const start: number = stack.pop() ?? -1;
      if (start < 0) {
        continue;
      }
      const slice: string = trimmed.substring(start, i + 1);
      try {
        const parsed: Object | null = JSON.parse(slice);
        if (parsed === null) {
          continue;
        }
        const item: TodoListItem | null = normalizeTodo(parsed, byId.size);
        if (item !== null) {
          byId.set(item.id, item);
        }
      } catch (e) {
        // 静默跳过不完整对象
      }
    }
  }
  const result: Array<TodoListItem> = [];
  for (const item of byId.values()) {
    result.push(item);
  }
  return result;
}

/** 数字 id 判定与取值（计划序排序用："2" 排在 "10" 前）；非纯数字返回 -1 */
function numericIdValue(id: string): number {
  if (id.length === 0) {
    return -1;
  }
  for (let i = 0; i < id.length; i++) {
    const c: string = id.charAt(i);
    if (c < '0' || c > '9') {
      return -1;
    }
  }
  return parseInt(id, 10);
}

/** 排序：数字 id 升序在前（计划序），非数字 id 保持稳定序在后 */
export function sortTodoItems(items: Array<TodoListItem>): Array<TodoListItem> {
  const numericOnes: Array<TodoListItem> = [];
  const others: Array<TodoListItem> = [];
  for (const item of items) {
    if (numericIdValue(item.id) >= 0) {
      numericOnes.push(item);
    } else {
      others.push(item);
    }
  }
  numericOnes.sort((a: TodoListItem, b: TodoListItem): number => numericIdValue(a.id) - numericIdValue(b.id));
  const result: Array<TodoListItem> = [];
  for (const item of numericOnes) {
    result.push(item);
  }
  for (const item of others) {
    result.push(item);
  }
  return result;
}

/** 合并两组清单：按 id 后写覆盖，输出按计划序（数字 id 升序）排序 */
export function mergeTodoItems(prev: Array<TodoListItem>, next: Array<TodoListItem>): Array<TodoListItem> {
  const byId: Map<string, TodoListItem> = new Map<string, TodoListItem>();
  for (const item of prev) {
    byId.set(item.id, item);
  }
  for (const item of next) {
    byId.set(item.id, item);
  }
  const merged: Array<TodoListItem> = [];
  for (const item of byId.values()) {
    merged.push(item);
  }
  return sortTodoItems(merged);
}
