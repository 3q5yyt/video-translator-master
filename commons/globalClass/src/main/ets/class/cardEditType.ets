/**
 * 卡片的编辑类型（用于区分用户从哪个入口进入编辑页）
 */
export enum cardEditType {
  "normalEdit" = 0, //普通用户第一次加桌某张卡片
  "secondEdit", //普通用户二次编辑某张卡片
  "designerEdit", //设计师设计卡片
  "testEdit", //测试人员打开某张卡片
  "shareEdit", //从分享逻辑打开某张卡片
}