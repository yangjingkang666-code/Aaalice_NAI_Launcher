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
| 双本地反推 | 反推面板「JoyTag + WD EVA02」 | 两个用户导入的 ONNX 模型顺序执行；每个模型的成功/失败、设备标签和候选词均保留为审计证据，再交给云端图片模型 |
| 结构化图片反推 | 反推面板 | 云端结果解析为正向/负向 Prompt、中文总结、语义证据和警告；结果先进入可编辑草稿，用户确认后才写入生成器 |
| 反推阶段审计 | 反推面板「阶段审计」 | 记录阶段状态、路由/模型、耗时和有界输出预览；失败阶段可以单独重试，Provider 错误原文可展开查看 |

## 运行规则

1. 队列任务保存完整的 `GenerationSnapshot`，包含 Prompt、角色和参考输入；历史任务缺少结构化语义时会兼容回退到本地分类/其他。
2. AI 批量计划禁止 `request:*` 参数和身份类别。批量计划只创建队列任务，不调用生成引擎；队列仍由既有串行 Scheduler 执行。
3. JoyTag 与 WD EVA02 不随安装包捆绑，也不会在反推入口静默下载。用户在设置中导入模型文件后，服务通过文件名（`joytag`、`eva02`/`wd14`）识别角色；缺少任一模型时原有云端直反推仍可用。
4. 本地 tagger 失败不会清除另一模型或已有云端证据；两个模型都失败时才停止双本地阶段，并显示可读错误。
5. Token、图片字节和二进制参考不会进入 AI 批量规划请求；图片反推只在用户明确点击后上传当前选中的图片，多图不会悄悄只取第一张。
6. 结构化反推如果遇到不支持 JSON 的 Provider，会保留纯文本结果并显示降级警告，不伪造语义或负面 Prompt 字段。

## 验证命令

```powershell
flutter analyze --no-pub
flutter test --no-pub test/data/models/recipe/modification_seed_strategy_test.dart test/presentation/providers/replication_queue_provider_test.dart test/data/services/ai_batch_plan_service_test.dart test/data/services/dual_local_onnx_tagger_service_test.dart test/data/services/prompt_semantic_entry_builder_test.dart test/data/services/prompt_semantic_organization_service_test.dart test/presentation/providers/generation/generation_result_lifecycle_service_test.dart test/data/services/prompt_patch_service_test.dart
flutter build windows --release --no-pub
```
