/**
 * 问题反馈页面使用的跳转参数
 */
export class feedBackParamClass {
  errorTypeIndex: number
  errorMessage: string

  constructor(errorTypeIndex: number, errorMessage: string) {
    this.errorTypeIndex = errorTypeIndex;
    this.errorMessage = errorMessage
  }
}


