# swiftui+pwa项目

## 启动流程
> [pwa项目](https://github.com/ruanjiayou/web-novel) 
- 请求接口获取最新版本
- 版本相同就直接跳过,没有就下载并解压到文档目录
- 启动静态文件服务(遍历查找可用端口)
- webview 访问本地端口


