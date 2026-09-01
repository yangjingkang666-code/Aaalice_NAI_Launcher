# Aaalice NAI Launcher 项目介绍与交接报告

更新时间：2026-09-01（Asia/Shanghai）
适用分支：`feat/novelai-cn-migration`
项目类型：Flutter 跨平台 NovelAI 客户端 + 可选本地 Agent 控制桥接

> 这份文档是给下一次对话、维护者或接手 Agent 的“事实基线”。先读完本文件，再检查工作区和运行状态；不要根据旧对话中的中间结论判断功能是否存在。报告不包含任何 bearer token、NovelAI token、账号数据或日志内容。

## 1. 项目定位

Aaalice NAI Launcher 是一个面向 NovelAI 图像工作流的桌面/移动客户端。它把生成、提示词管理、反推、画廊、队列、项目资料和本地模型能力统一到 Flutter UI 中，并保留 NovelAI 原有的权限、计费和审计边界。

当前 fork 的主要目标是：

- 在保留上游可用功能的基础上，补齐中文工作流和 AI 辅助能力。
- 让翻译、提示词优化、角色替换、结构化反推和随机画师串都产生可审查结果。
- 让项目、图库、Prompt Recipe、知识库和队列能够复现、迁移和审计。
- 通过可选的 loopback Agent API，让 DeepSeek Harness 在用户说“生图”时懒路由到 Aaalice，同时不绕过 Aaalice 的审批或 Anlas 检查。

## 2. 仓库与版本基线

本机仓库：

`C:\Users\blykt\Desktop\AI绘图\Aaalice_NAI_Launcher`

远程仓库：

- `origin`：`https://github.com/yangjingkang666-code/Aaalice_NAI_Launcher.git`（用户的 fork）
- `upstream`：`https://github.com/Aaalice233/Aaalice_NAI_Launcher.git`（原项目）

当前 Git 状态（本报告提交后）：

- 分支：`feat/novelai-cn-migration`
- 基线提交：`1781cda4 feat(agent): connect desktop Harness lazy image bridge`
- 报告提交会在该基线之上追加，不应覆盖现有用户改动。
- 工作区应保持干净；开始新任务前先执行 `git status --short`。
- 相对 `upstream/main` 当前约 `38` 个提交落后、`23` 个提交领先。发布前应先审查上游变更，再做有计划的 rebase/merge；不要在没有备份和测试的情况下强行同步。

最近的重要提交：

| 提交 | 内容 |
| --- | --- |
| `1781cda4` | Harness 插件懒发现 Aaalice 描述文件并接通懒人模式 |
| `ca6c15dd` | 修复画廊动作、设置导航和移动端更多面板；隐藏主导航 Discord/GitHub |
| `baa951c5` | 编辑器销毁时取消 Prompt Assistant 工作 |
| `ef0f1090` | 完成画廊/设置响应式审查收尾 |
| `4c5a4de8` | 增加本地 Agent 控制 API 和 DeepSeek 插件骨架 |
| `c3dc7a7e` | 增加随机画师串与画风实验室 |
| `3e8ca4e7` | 完成项目工作区与 Knowledge/RAG 检索 |
| `449933ec` | 增加可取消的反推链 |
| `0d797f0e` | 增加可审查的结构化反推结果 |
| `1a5719d7` | 完成 Prompt 优化迁移 |

## 3. 代码结构

```text
lib/core/                 网络、存储、Agent、权限、审计、平台能力
lib/data/                 API 数据源、模型、仓库、领域服务
lib/presentation/         页面、组件、Riverpod provider、路由、主题
lib/l10n/                 中/英/日/繁中文案与生成代码
plugins/deepseek-harness/ DeepSeek Harness TypeScript 插件及编译产物
assets/                   数据库、随机词库、随包资源
test/                     与 lib 分层对应的 Dart 测试
scripts/                  测试、构建、NuGet、发布和诊断脚本
windows/, android/, macos/平台 Runner 工程
docs/                     功能对照、设计与本交接报告
```

关键边界：页面只组装布局和事件；业务逻辑放在 service/provider；生成权限、Anlas 估算、审计和实际执行仍由 Aaalice 内部链路负责；外部桥接只是命令转发器。

## 4. 已完成的用户功能

### 4.1 生成与 Prompt 工作流

- 文生图、图生图、参数编辑、正/负 Prompt、固定词、角色 0/1/多角色、历史和队列。
- Prompt Assistant：中文阅读翻译、提示词优化、角色替换；流式响应具有运行代次和取消保护，迟到片段不会覆盖新内容。
- Prompt Recipe：保存原文、分类、来源、本地 Tag 命中、置信度和稳定 ID。
- Prompt Patch：锁定身份、核心特征、风格、参数和二进制参考；修改结果建立子 Recipe；Seed 支持沿用、随机或指定。
- AI 批量规划：只提出可审查的文本 Patch，用户逐项编辑/启用/删除/排序后才加入既有串行队列，不自动开始生成。

### 4.2 AI 反推

- 结构化云端图片反推：输出正向/负向 Prompt、中文总结、语义证据和警告。
- 结果先进入可编辑草稿，用户确认后才写回生成器。
- 反推阶段审计：记录阶段、路由/模型、耗时和有界输出预览；失败阶段可单独重试。
- 双本地反推：JoyTag + WD EVA02 ONNX 顺序执行，成功/失败、设备和候选词作为证据保留，再交给云端图片模型。
- Windows 优先 DirectML，初始化/算子/推理失败自动回退 CPU，并把实际 provider 写入审计。
- 反推支持取消、代次隔离和过期结果丢弃；本地模型不随安装包捆绑、不静默下载。

关键实现：

- `lib/presentation/agent_chat/services/generation_interrogation_service.dart`
- `lib/data/services/dual_local_onnx_tagger_service.dart`
- `lib/presentation/screens/...` 下的反推面板和草稿 UI
- `docs/flutter-fork-optimization-parity.md` 中的模型文件命名和冒烟命令

### 4.3 画风实验室与随机画师串

实现目录：

- `lib/data/models/style_lab/style_lab_models.dart`
- `lib/data/services/style_lab_service.dart`
- `lib/data/services/style_lab_batch_runner.dart`
- `lib/data/services/style_lab_storage_service.dart`
- `lib/presentation/screens/style_lab/`

能力：可配置画师池/风格池、画师数量和权重、风格突变 token 数、随机或固定 Seed、同 Seed A/B 变体、结果持久化和批量运行。`normalizeArtistTag` 已修复带括号别名（例如 `ask_(artist)`）被错误截断的问题，并有回归测试。

画风实验室的“计划”本身是离线操作，不调用 NovelAI、不消耗 Anlas；真正生成需要显式进入 Aaalice 生成流程并遵守审批。

### 4.4 项目、知识库、图库与队列

- 项目工作区：图片、sidecar 元数据、Prompt Recipe 和知识库按项目目录隔离；旧图库/配方可非破坏导入。
- Knowledge/RAG：项目知识库优先，其次内置 Tag catalog/中文词典，最后才使用远端搜索端点；检索证据写入 Recipe，用户确认后才进入草稿。
- 在线画廊：Danbooru、Safebooru、Gelbooru、AI TAG、NovelAI QuickTagCloud/法典；支持来源筛选、黑名单、输出过滤、随机、刷新、多选和详情。
- 在线画廊详情：发送到文生图、加入队列、复制、下载、发送反推均从可用标签/Prompt 内容判定，不再因来源缺少结构化 Prompt 而无故禁用。
- 本地图库、收藏/集合、统计、Vibe/Precise Reference 库、Krita/ComfyUI 桥接、GitHub/WebDAV/Google Drive/OneDrive 云同步。
- 队列保存完整 `GenerationSnapshot`，支持 Seed 复现、暂停/恢复、排序和失败处理。

### 4.5 UI 修复状态

- AI 助手设置入口：设置跳转现在会关闭 Agent 抽屉并带上 `section=agent`，避免抽屉覆盖设置导致“点击无反应”。
- 画廊详情动作：补齐有效标签内容判定，发送到文生图/加入队列按钮在有标签的来源上可用。
- 主导航：Discord 社区和 GitHub 仓库按钮已从桌面导航 rail 和移动端“更多”面板移除。Discord 分享服务、关于页链接和 GitHub 云同步实现仍保留在各自业务页面；本次变更不是删除这些后端能力。
- 响应式布局：桌面、窄屏和移动导航的设置/画廊入口已补回，相关 widget 测试已更新。

## 5. DeepSeek Harness 外部桥接

### 5.1 设计边界

桥接是可选的本机 HTTP loopback 服务，协议名为 `aaalice-agent-control`，版本 `v1`。默认构建关闭；只有使用 `--dart-define=ENABLE_AGENT_CONTROL=true` 构建时才在首帧后启动。

服务端实现：

- `lib/core/agent/external/agent_control_protocol.dart`
- `lib/core/agent/external/agent_control_server.dart`
- `lib/presentation/agent_chat/services/agent_external_control_service.dart`
- `lib/presentation/agent_chat/providers/agent_external_control_provider.dart`

安全和一致性约束：

- 只绑定 `127.0.0.1`，每个请求都要求 bearer token。
- 描述文件只写到应用支持目录，包含动态端口和 token；不要提交、复制到聊天或打印日志。
- 请求体上限 1 MiB，命令最长 15 分钟，幂等缓存最多 128 条。
- 长命令串行；状态、离线画风规划、中止和明确的 follow-up 可并发。
- `agent.send` 只调用现有 `AgentChatNotifier`，不会直接调用生成 provider，不会绕过权限、Anlas 估算或审计。

当前方法：

| 方法 | 作用 | 是否可能消耗 Anlas |
| --- | --- | --- |
| `agent.status` | 返回初始化、运行阶段、队列、活动工具和审批元数据 | 否 |
| `agent.send` | 将 Harness 的自然语言请求发送到 Aaalice Agent；`follow_up=true` 可排队 | 取决于 Aaalice UI 审批 |
| `agent.abort` | 中止当前 Agent 运行 | 否 |
| `style_lab.plan` | 离线生成随机画师串 A/B Prompt 对 | 否 |

### 5.2 “懒人模式”路由

插件在 system prompt 中加入中英文规则：用户提到“生图、绘图、文生图、图生图、提示词转换、AI 反推、反推提示词、随机画师串、画风实验室”等意图时，Harness 应调用 `aaalice_agent_send`，而不是只解释步骤。仅当用户明确只要离线随机画师串计划时，才调用 `aaalice_style_lab_plan`。桥接不可用或被拒绝时必须如实报告，不能声称图片已经生成。

插件目录：`plugins/deepseek-harness`

- TypeScript 源码：`src/index.ts`、`src/client.ts`
- 编译入口：`scripts/build.mjs`
- 已提交运行时：`lib/index.js`、`lib/client.js`
- DSH patch：`cordis.patch.yml`
- 包名：`@aaalice/deepseek-harness-agent-control`，版本 `0.1.0`

插件客户端默认懒发现以下 Windows 路径（按环境变量和用户目录组合尝试）：

`%APPDATA%\com.example\nai_launcher\agent\agent-control-v1.json`

也支持 `AAALICE_AGENT_CONTROL_DESCRIPTOR`，或成对设置 `AAALICE_AGENT_CONTROL_URL` 与 `AAALICE_AGENT_CONTROL_TOKEN`。客户端拒绝非 HTTP loopback URL。

## 6. 本机 DSH/Aaalice 配置

DeepSeek Harness 桌面工程：

`C:\Users\blykt\Desktop\DSH-Phrolova-Desktop-v1`

桌面快捷方式：

`C:\Users\blykt\Desktop\DeepSeek Harness - Phrolova Edition.lnk`

快捷方式目标是该工程 `dist_v4` 下的 exe。实际 DSH 包目录：

`C:\Users\blykt\AppData\Local\npm-cache\_npx\1e7f6d9597241db0\node_modules\@deepseek-ai\dsh`

DSH profile：

- `C:\Users\blykt\.dsh\profiles\web\package.json`
- `C:\Users\blykt\.dsh\profiles\web\cordis.patch.yml`
- 已安装包：`C:\Users\blykt\.dsh\profiles\web\node_modules\@aaalice\deepseek-harness-agent-control`
- 日志目录：`C:\Users\blykt\AppData\Local\DSH-Phrolova\logs`

插件已通过 `file:` 安装并写入 profile bundle；`link:` 方式在 Windows peer/路径解析上失败，因此不要把旧的 link 配置恢复回来。需要重新安装时使用（路径按实际仓库调整）：

```powershell
$dsh = 'C:\Users\blykt\AppData\Local\npm-cache\_npx\1e7f6d9597241db0\node_modules\@deepseek-ai\dsh'
$plugin = 'C:/Users/blykt/Desktop/AI绘图/Aaalice_NAI_Launcher/plugins/deepseek-harness'
node "$dsh\lib\bin.js" plugin --profile web add "file:$plugin" --save-exact
```

验证 profile 是否载入插件：

```powershell
node "$dsh\lib\bin.js" web --dump-config
node "$dsh\lib\bin.js" web --no-open --port 3081
```

第二条会启动本地 DSH 服务；测试后要正常结束该进程。最近一次实际 `pluginInventory/list` 返回 `include:aaalice-agent-control`，状态为 enabled/active。

Aaalice 的发现文件位置（只读路径和非敏感字段）：

`C:\Users\blykt\AppData\Roaming\com.example\nai_launcher\agent\agent-control-v1.json`

端口是动态的，重启 Aaalice 后不要假设仍是旧端口。当前发布 exe 位于：

`C:\Users\blykt\Desktop\AI绘图\Aaalice_NAI_Launcher\build\windows\x64\runner\Release\nai_launcher.exe`

## 7. 构建、测试和运行

工具链：

- Flutter：`C:\Users\blykt\AppData\Local\Programs\Flutter\3.44.2\flutter\bin\flutter.bat`
- Node：`C:\Program Files\nodejs\node.exe`（当前 v22.22.2）
- NuGet：`C:\Users\blykt\AppData\Local\NuGet\nuget.exe`（不一定在全局 PATH）

Windows 构建建议先把 NuGet 目录放到当前进程 PATH：

```powershell
$env:Path = 'C:\Users\blykt\AppData\Local\NuGet;' + $env:Path
flutter build windows --release --no-pub
```

启用桥接的发布构建：

```powershell
$env:Path = 'C:\Users\blykt\AppData\Local\NuGet;' + $env:Path
flutter build windows --release --dart-define=ENABLE_AGENT_CONTROL=true --no-pub
```

仓库路径含中文时，CMake/原生插件偶尔会遇到编码问题。已有 ASCII junction `C:\AI_NAI_Launcher` 和 `X:` subst 工作流；遇到原生构建异常时，从 ASCII 路径进入同一仓库再构建，不要复制出第二份代码。

推荐验证命令：

```powershell
flutter analyze --no-pub
pwsh -NoProfile -ExecutionPolicy Bypass -File scripts/test_affected.ps1
pwsh -NoProfile -ExecutionPolicy Bypass -File scripts/run_flutter_tests.ps1
flutter build windows --release --no-pub
```

本轮已验证的证据：

- `flutter test test/data/services/style_lab_service_test.dart`：5 个测试全部通过。
- Aaalice Release 构建（含 `ENABLE_AGENT_CONTROL=true`）：成功。
- 编译后的 Harness client：成功读取当前描述文件并调用 `agent.status`。
- 编译后的 `style_lab.plan`：成功返回 A/B 对，`ask_(artist)` 等括号别名保持完整，`charged=false`。
- DSH 临时启动和 `pluginInventory/list`：插件真实挂载且 active。

本轮没有做的验证（不要误报为已完成）：

- 没有发起真实 NovelAI 生图或任何会消耗 Anlas 的请求。
- 尚未完成全量 `flutter analyze`、全量测试脚本和逐页面 Windows/Android 视觉验收。
- 尚未验证用户当前桌面 DSH 窗口重启后的完整对话链；profile 已安装，仍需用户在自己的账号/模型设置下做一次无计费或明确批准的实际测试。

## 8. 新对话的接手顺序

1. 阅读本文件和 `docs/flutter-fork-optimization-parity.md`。
2. 执行 `git status --short`、`git log -5 --oneline`，确认没有未授权改动。
3. 检查 Aaalice 是否运行；若要验证桥接，读取描述文件的协议/端口字段，绝不要输出 token。
4. 先调用 `agent.status` 或 Harness 的 `aaalice_agent_status`，确认服务可达，再考虑发送请求。
5. 做 UI 验证时优先复现用户反馈：Agent 设置入口、在线画廊详情的“发送到文生图/加入队列”、主导航是否仍显示 Discord/GitHub。
6. 运行受影响测试；需要全量测试时使用仓库脚本并遵守 600 秒总时限，不要直接无界运行 `flutter test`。
7. 修改 Flutter/原生代码后按 AGENTS.md 判断使用 reload、restart 还是完整重建；不要启动第二个 `flutter run`。
8. 每次提交使用 Conventional Commit；生成的日志、token、模型和 `tool/.tmp` 产物不得提交。

可直接复制给下一次对话的开场语句：

> 请先阅读 `C:\Users\blykt\Desktop\AI绘图\Aaalice_NAI_Launcher\docs\PROJECT_HANDOFF.md` 和 `AGENTS.md`，在 `feat/novelai-cn-migration` 分支上继续。先检查 Git 状态、Aaalice Agent bridge 状态和 Harness profile，不要重复实现已经完成的翻译、AI 辅助、反推、随机画师串、画廊动作或懒人模式；如果要测试生图，先说明是否会触发 Anlas，并等待我确认。

## 9. 明确延期与后续优先级

暂不做：

- TIPO 发散 Provider。
- 自动评图和自主迭代。
- 跨主机/沙箱控制、事件流、细粒度能力授权、自动启动 Aaalice、更强的 Agent 身份与审计设计。

建议下一阶段按以下顺序收尾：

1. 用户重启桌面 Aaalice 与 DSH，验证一次 `status`、一次离线 `style_lab.plan`，再验证一次由用户明确批准的实际任务。
2. 按 UI 覆盖矩阵完成 Windows/Android 的页面、抽屉、弹窗、窄屏和键盘态验收，记录截图和日志后删除临时产物。
3. 运行 `flutter analyze --no-pub`、受影响测试和全量测试脚本，修复剩余静态分析或异步泄漏问题。
4. 在发布前审查 upstream 领先/落后提交，解决冲突后重新跑验证。
5. 如需对外分发，再为 Harness 插件增加版本化发布包/安装说明；不要在此之前扩大桥接权限或让外部 Agent 直接接触生成 provider。

## 10. 常见误区

- Windows 弹出“选择应用打开 esbuild”时，不需要选择 7-Zip、Visual Studio 或其他应用；这是把无扩展名脚本当普通文件打开了。使用项目的 `node scripts/build.mjs` 或已编译的 `lib/*.js` 即可。
- DSH 搜索不到插件时，先完全重启桌面 Harness；检查的是 profile bundle，不是 GitHub 插件商店。
- 描述文件端口每次 Aaalice 启动可能变化；不要硬编码旧端口，也不要把 token 写进环境变量持久配置或报告。
- `style_lab.plan` 返回计划不等于图片已生成；只有 Aaalice Agent 在 UI 权限流程中实际批准并完成，才可以向用户报告生成结果。
- “隐藏 GitHub/Discord 按钮”只针对主导航入口；关于页 GitHub 链接、云同步 GitHub 后端和 Discord 分享业务不应被误删，除非用户另行要求。
