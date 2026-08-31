# Aaalice Agent Control · DeepSeek Harness plugin

This directory contains a small DeepSeek Harness plugin for the optional,
loopback-only Agent control API in Aaalice NAI Launcher. The plugin registers
tools and forwards commands; it does not replace the Harness agent loop or
duplicate Aaalice's permission and Anlas checks.

## 中文说明

### 1. 启用 Aaalice 接口

接口默认关闭。开发运行 Launcher 时显式启用：

```powershell
flutter run -d windows --dart-define=ENABLE_AGENT_CONTROL=true
```

Launcher 会在应用支持目录的 `agent/agent-control-v1.json` 写入一次性发现
信息。该文件含 bearer token，只应授予 DeepSeek Harness 进程读取权限；不要
提交到 Git、聊天记录或日志中。也可以直接提供下面两项环境变量，不使用发现文件：

```powershell
$env:AAALICE_AGENT_CONTROL_URL = 'http://127.0.0.1:PORT'
$env:AAALICE_AGENT_CONTROL_TOKEN = '从发现文件取得的令牌'
```

使用发现文件时设置：

```powershell
$env:AAALICE_AGENT_CONTROL_DESCRIPTOR = 'C:\path\to\agent-control-v1.json'
```

接口只绑定 `127.0.0.1`，每个请求都要求 bearer token；生成相关命令仍由
Aaalice 现有 Agent 权限确认与 Anlas 审计链处理。

### 2. 在 Harness 中加载插件

DeepSeek Harness 的本地插件路径必须是绝对路径。创建一个 overlay，例如
`scratch-plugin/cordis.yml`：

```yaml
- insert:
    - id: aaalice-agent-control
      name: 'C:/path/to/Aaalice_NAI_Launcher/plugins/deepseek-harness/src/index.ts'
```

从 DeepSeek Harness 仓库根目录启动 Web UI：

```sh
pnpm dsh web --patch ./scratch-plugin/cordis.yml
```

### 3. 可用工具

- `aaalice_agent_status`：读取运行状态、队列和审批元数据，不返回完整会话记录。
- `aaalice_agent_send`：向 Aaalice Agent 发送提示词，可选择排队；可能触发生成，
  但不会绕过应用内授权。
- `aaalice_agent_abort`：中止当前运行。
- `aaalice_style_lab_plan`：离线生成随机画师串 A/B 提示词对，不访问 NovelAI，
  不消耗 Anlas。

### 协议边界

当前版本是 `aaalice-agent-control/v1` 的 HTTP loopback 协议。请求包含
`request_id`、`method`、`params`，写操作可带 `idempotency_key`。服务端串行执行
长命令，状态、离线规划、中止和明确的 follow-up 可在长任务期间并行，并缓存
有限的幂等结果；后续若需要流式事件或更细的任务句柄，应扩展版本化协议，不让
插件自行猜测 Agent 状态。

## English

This plugin registers DeepSeek Harness tools for Aaalice's optional local Agent
control API. It is intentionally a protocol adapter: the Harness loop, Aaalice
permission flow, Anlas approval, and audit trail remain authoritative. Long
commands are serialized, while status, offline planning, abort, and explicit
follow-ups can run without waiting behind a generation request.

Enable the API explicitly with
`flutter run -d windows --dart-define=ENABLE_AGENT_CONTROL=true`. Point the
plugin at the generated `agent/agent-control-v1.json` through
`AAALICE_AGENT_CONTROL_DESCRIPTOR`, or set
`AAALICE_AGENT_CONTROL_URL` and `AAALICE_AGENT_CONTROL_TOKEN` together. Keep
the descriptor private because it contains the bearer token. The client rejects
non-loopback URLs.

Load the absolute `src/index.ts` path through a Harness `cordis.yml` overlay and
start `pnpm dsh web --patch ./scratch-plugin/cordis.yml`. The registered tools
are `aaalice_agent_status`, `aaalice_agent_send`, `aaalice_agent_abort`, and
`aaalice_style_lab_plan`.
