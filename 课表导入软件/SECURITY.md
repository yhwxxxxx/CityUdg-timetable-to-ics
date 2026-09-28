# 安全与 Windows 告警说明

## 为什么旧版容易被误报

旧版 exe 会把内嵌的 PowerShell 脚本写入临时目录，然后以隐藏窗口和 `ExecutionPolicy Bypass` 启动。这些行为和常见恶意程序的“释放并执行载荷”特征相似，可能触发启发式检测。

1.1 版启动器已移除上述行为：

- 不向临时目录释放脚本。
- 不创建或隐藏外部 `powershell.exe` 进程。
- 不使用 `ExecutionPolicy Bypass`。
- 不请求管理员权限，不修改 Windows 安全设置。
- 发布包附带 SHA-256 校验值。

## “病毒检测”和“未知发布者”不是一回事

- 如果安全软件显示了具体的威胁名称，请不要关闭防护或添加排除项。请保留检测名称并提交样本复核。
- 如果只是 SmartScreen 显示“Windows 已保护你的电脑”或“未知发布者”，这表示该文件或签名证书还没有足够的下载信誉，不是具体的恶意软件检测结果。

## 正式发布建议

1. 使用固定的、可信 CA 签发的代码签名证书签名每一版 exe。构建脚本支持通过 `TIMETABLE_IMPORTER_SIGNING_THUMBPRINT` 传入证书指纹并添加时间戳。
2. 不要在签名后修改 exe，各版本应持续使用同一发布者身份。
3. 考虑通过 Microsoft Store 分发，这是避免 SmartScreen 下载警告最稳定的方式。
4. 如果 Microsoft Defender 给出了具体的误报名称，使用官方样本提交页面选择 **Software developer** 并申报 false positive。

## 官方参考

- SmartScreen 信誉：<https://learn.microsoft.com/windows/apps/package-and-deploy/smartscreen-reputation>
- Windows 代码签名选项：<https://learn.microsoft.com/windows/apps/package-and-deploy/code-signing-options>
- Microsoft 恶意软件样本/误报提交：<https://www.microsoft.com/wdsi/filesubmission>
