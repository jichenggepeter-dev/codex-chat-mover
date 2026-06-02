# Codex Chat Mover

中文 | [English](README.md)

把 Codex 的 Chats 移动到正确的 Projects 里。

Codex Chat Mover 是一个轻量级 macOS 应用，用来整理本地 Codex Desktop
对话。它会读取你本机的 Codex 元数据，展示真实项目和可移动的 chats，并支持把
chat 拖拽到 project 中，同时提供备份和撤回能力。

> 实验性本地工具。Codex 的本地元数据格式不是公开 API，所以迁移前请关闭
> Codex Desktop，并保留备份。

## 为什么做这个

Codex Desktop 里有两种常见工作形态：

- **Chats**：适合临时规划、研究、灵感探索、快速提问。
- **Projects**：适合绑定本地文件夹、Git diff、终端和沙盒权限的工程工作。

很多时候，一个对话一开始只是研究，后来会变成明确的项目上下文。Codex Desktop
目前没有原生的“把 chat 拖进 project”功能。这个 app 就是一个小型伴侣工具，用来补上这个工作流。

## 功能

- 原生 SwiftUI macOS 应用。
- 从 `~/.codex` 读取本地 Codex 状态。
- 过滤 subagent、guardian 和内部 delegation 对话。
- 从项目侧边栏里隐藏一次性生成的 Codex 工作目录。
- 展示真实用户项目和可移动 chats。
- 新建项目默认放在 `~/Documents/Codex/<date>/projects`。
- 支持把 chat 拖到项目或右侧 drop 区域。
- 写入元数据前要求 Codex Desktop 关闭。
- 移动前自动创建备份。
- 支持 `Undo Last Move`。
- 会把 Markdown 和 JSON 副本写入目标项目。
- 包含 smoke tests 和 scanner diagnostics 命令。

## 安全模型

Codex Chat Mover 使用保守的迁移事务：

1. 确认 Codex Desktop 没有运行。
2. 备份本地 Codex 状态文件。
3. 更新 sqlite 元数据里的 thread 项目路径。
4. 更新 session JSONL 里的 `cwd` 字段。
5. 更新 Codex Desktop 侧边栏项目状态。
6. 在目标项目写入导入副本。
7. 重新扫描并验证 chat 已出现在目标项目下。
8. 如果验证失败，从备份恢复。

备份位置：

```text
~/Library/Application Support/Codex Chat Mover/Backups
```

导入副本位置：

```text
.codex/imported-chats/
```

## 从源码安装

要求：

- macOS 14 或更新版本
- Swift 6 toolchain
- 已安装 Codex Desktop，并且本地有 threads

克隆并运行：

```bash
git clone https://github.com/jichenggepeter-dev/codex-chat-mover.git
cd codex-chat-mover
swift run CodexChatMover
```

构建本地 `.app`：

```bash
sh scripts/package-app.sh
open "outputs/Codex Chat Mover.app"
```

## 使用方法

1. 退出 Codex Desktop。
2. 打开 Codex Chat Mover。
3. 在左侧选择目标项目。
4. 从中间列表把 chat 拖到右侧 drop 区域。
5. 确认移动。
6. 重新打开 Codex Desktop，让侧边栏刷新。

如果移动结果不符合预期，可以使用 `Undo Last Move` 恢复。

## 常用命令

运行 app：

```bash
swift run CodexChatMover
```

运行 smoke tests：

```bash
swift run ScannerSmokeTests
```

查看 scanner 当前能识别到什么：

```bash
swift run ScannerDiagnostics
```

构建：

```bash
swift build
```

## 项目结构

```text
Sources/
  CodexChatMoverApp/       SwiftUI 应用和交互状态
  CodexChatMoverCore/      scanner、模型、备份和迁移事务
Tests/
  ScannerSmokeTests/       轻量可执行测试
  ScannerDiagnostics/      只读真实元数据诊断
docs/
  PRD.md
  ARCHITECTURE.md
  NEXT_STEPS.md
scripts/
  package-app.sh
```

## 路线图

- 增加独立 onboarding 页面。
- 增加更清晰的 scanner 状态面板。
- 增加手动 project allow/block lists。
- 增加 dry-run move preview。
- 增加签名 release build。
- 增加 GitHub Actions build check。

## 局限

- 仅支持 macOS。
- 仅支持本地 Codex Desktop。
- 不迁移云端 threads。
- 不是官方 Codex Desktop UI 扩展。
- 依赖 Codex 当前的本地元数据结构。

## 开发说明

这个项目刻意把有写入能力的代码集中在 `SafeThreadMover`。扫描逻辑在
`LiveCodexStoreScanner` 中；SwiftUI views 不应该直接解析或修改 Codex 元数据。

修改迁移逻辑前，建议运行：

```bash
swift run ScannerSmokeTests
swift build
```

## License

MIT
