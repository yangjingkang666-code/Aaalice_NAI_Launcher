# Fork 优化功能对照

本文件记录从 `Aaalice_NAI` 工作流迁移到 Flutter fork 的稳定边界。所有 AI 能力都先产生可审查结果；客户端不会因为收到 AI 输出而静默修改 Prompt、挂载参考图或调用 NovelAI。

## 已接通

| 能力 | 入口 | 持久化/安全边界 |
| --- | --- | --- |
| 结构化 Prompt | 生成完成、生成页「AI 整理 Prompt」 | Recipe 保存稳定 ID、原文、分类、来源、命中本地 Tag 与置信度；NovelAI 仍收到原始字符串 |
| 本地 Tag 权威 | 生成保存、语义工作台 | 本地 catalog 分类覆盖 AI；`manual` 分类不会被 AI 改回 |
| AI 整理 | 生成页 Prompt 助手设置 | 一次请求同时返回分类与中文阅读翻译；单项坏数据只降级该项 |
| Prompt Patch | 历史图片/Recipe 操作 | 严格锁定身份、Core、Locked Traits、风格、参数和二进制引用；应用结果创建子 Recipe |
| 修改 Seed 策略 | Prompt Patch 工作台 | 默认沿用基础图，也可随机或指定；随机值在队列入队时只解析一次 |
| AI 批量规划 | Prompt Patch 工作台 → AI 批量规划 | 只接受限定类别的文本 Patch；逐项启用、编辑、删除、排序后才加入现有串行队列，不自动开始生成 |
| AI 助手翻译/优化/角色替换 | 统一 Prompt 输入框助手 | 三类操作共用会话状态与运行代次；取消或重新触发后，迟到的流式片段不会覆盖当前编辑内容，历史记录只收录真正应用的结果 |
| 双本地反推 | 反推面板「JoyTag + WD EVA02」 | 两个用户导入的 ONNX 模型顺序执行；每个模型的成功/失败、设备标签和候选词均保留为审计证据，再交给云端图片模型 |
| 本地模型管理与设备策略 | 设置 → 数据与存储 → 本地反推模型管理 | 扫描并校验 JoyTag/WD EVA02 的 ONNX 与标签伴随文件；Windows 优先尝试 DirectML，会话创建或推理失败自动回退 CPU；偏好持久化且不会静默下载模型 |
| 结构化图片反推 | 反推面板 | 云端结果解析为正向/负向 Prompt、中文总结、语义证据和警告；结果先进入可编辑草稿，用户确认后才写入生成器 |
| 反推阶段审计 | 反推面板「阶段审计」 | 记录阶段状态、路由/模型、耗时和有界输出预览；失败阶段可以单独重试，Provider 错误原文可展开查看 |
| 反推取消与过期结果防护 | 反推面板主操作按钮 | 处理中可立即取消；云端请求执行尽力取消，本地 ONNX/迟到响应按运行代次丢弃，不会覆盖取消后的状态或新一轮结果 |
| 项目工作区 | 设置 → 数据与存储 → 项目目录 | 可选项目目录隔离图片、图片元数据 sidecar、Prompt Recipe 与项目知识库；旧图库/配方可在项目内非破坏导入，切换项目会清理缓存并触发按路径重建索引 |
| Knowledge / Prompt RAG | Prompt 语义工作台 → 搜索 | 项目知识库优先，随后使用内置 Tag catalog/中文词典，最后才降级到 DanbooruSearch HF/ModelScope 端点；用户逐条确认后才写入草稿，并把所有检索证据保存到 Recipe |

## 本轮明确延期

- TIPO 发散 Provider：不接入当前 fork，避免增加一套不可审查的 Prompt 改写路由。
- 自动评图与自主迭代：暂不自动调用评图或再次生成，保留现有人工确认流程。
- 外部 Agent 控制：当前项目尚未开始该设计；后续会单独定义权限、沙箱、确认和审计协议后再实现。

## 运行规则

1. 队列任务保存完整的 `GenerationSnapshot`，包含 Prompt、角色和参考输入；历史任务缺少结构化语义时会兼容回退到本地分类/其他。
2. AI 批量计划禁止 `request:*` 参数和身份类别。批量计划只创建队列任务，不调用生成引擎；队列仍由既有串行 Scheduler 执行。
3. JoyTag 与 WD EVA02 不随安装包捆绑，也不会在反推入口静默下载。用户在设置中导入模型文件后，服务通过文件名或伴随词表识别角色：JoyTag 使用 `joytag*.onnx` + `top_tags.txt`，WD EVA02 使用 `wd/eva02/wd14*.onnx` + `selected_tags.csv`；缺少任一模型时原有云端直反推仍可用。
4. 设置页会在推理前检查模型文件与标签文件是否存在且可解析；模型管理器不联网、不自动下载，未识别的文件会明确标记。
5. Windows 本地推理按设置优先尝试 DirectML；驱动、算子、运行库初始化或推理失败时重建 CPU 会话，并把实际 provider 写入双模型审计证据。
6. 本地 tagger 失败不会清除另一模型或已有云端证据；两个模型都失败时才停止双本地阶段，并显示可读错误。
7. Token、图片字节和二进制参考不会进入 AI 批量规划请求；图片反推只在用户明确点击后上传当前选中的图片，多图不会悄悄只取第一张。
8. 结构化反推如果遇到不支持 JSON 的 Provider，会保留纯文本结果并显示降级警告，不伪造语义或负面 Prompt 字段。
9. 反推链每次运行都有独立代次；取消或重新开始后，旧阶段即使在后台完成也不能发布到当前状态。
10. Prompt Assistant 的翻译、优化和角色替换共享会话代次；只有当前代次的流式结果才允许写入编辑器、状态和历史栈。

## 真实模型冒烟

模型不随仓库或安装包提交。发布前可把用户自己下载的模型放在临时目录，并运行手动测试验证真实 ONNX 推理、标签词表解析和实际执行 provider：

```powershell
$env:NAI_ONNX_TAGGER_SMOKE = '1'
$env:NAI_JOYTAG_MODEL = 'C:\models\joytag.onnx'
$env:NAI_JOYTAG_LABELS = 'C:\models\top_tags.txt'
$env:NAI_WD_EVA02_MODEL = 'C:\models\wd-eva02-large-tagger-v3.onnx'
$env:NAI_WD_EVA02_LABELS = 'C:\models\selected_tags.csv'
$env:NAI_ONNX_IMAGE = 'C:\models\sample.png'
flutter test --no-pub test/manual/local_onnx_tagger_smoke_test.dart
```

`NAI_ONNX_TAGGER_PREFERENCE=cpu` 可强制 CPU；不设置时 Windows 优先尝试 DirectML，并在输出中打印实际 provider 和耗时。

## 验证命令

```powershell
flutter analyze --no-pub
flutter test --no-pub test/data/models/recipe/modification_seed_strategy_test.dart test/presentation/providers/replication_queue_provider_test.dart test/data/services/ai_batch_plan_service_test.dart test/data/services/dual_local_onnx_tagger_service_test.dart test/data/services/prompt_semantic_entry_builder_test.dart test/data/services/prompt_semantic_organization_service_test.dart test/presentation/providers/generation/generation_result_lifecycle_service_test.dart test/data/services/prompt_patch_service_test.dart
flutter build windows --release --no-pub
```
