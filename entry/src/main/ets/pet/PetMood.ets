/** 宠物心情（聊天页头部吉祥物）：全部由会话状态派生，宠物自身零业务状态（学自 nanoMuse AgentMood） */
export enum PetMood {
  /** 待机：摇头轻摆 + 呼吸 */
  Idle = 0,
  /** 会话流式回复中 / 工具调用中 */
  Working = 1,
  /** HITL 等用户确认 */
  Waiting = 2,
  /** 一轮流式回复正常结束的余晖 */
  Happy = 3,
  /** 回复出错 / 连接异常的余晖 */
  Error = 4
}

/** Happy 余晖时长（毫秒） */
export const PET_AFTERGLOW_HAPPY_MS = 3000;
/** Error 余晖时长（毫秒） */
export const PET_AFTERGLOW_ERROR_MS = 4000;
