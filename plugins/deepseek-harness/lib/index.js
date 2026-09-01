// Aaalice_NAI_Launcher/plugins/deepseek-harness/src/index.ts
import { defineTool } from "@deepseek-ai/dsh-tools";

// Aaalice_NAI_Launcher/plugins/deepseek-harness/src/client.ts
import { randomUUID } from "node:crypto";
import { readFile } from "node:fs/promises";
import { isIP } from "node:net";
import { homedir } from "node:os";
import { join } from "node:path";
var AGENT_CONTROL_PROTOCOL = "aaalice-agent-control";
var AGENT_CONTROL_VERSION = "1";
var AgentControlRemoteError = class extends Error {
  constructor(code, message, details) {
    super(message);
    this.code = code;
    this.details = details;
    this.name = "AgentControlRemoteError";
  }
};
var AaaliceAgentControlClient = class {
  descriptorPath;
  autoDiscoverDescriptor;
  descriptorSearchPaths;
  explicitBaseUrl;
  explicitToken;
  descriptorTtlMs;
  fetchImpl;
  cachedDescriptor;
  cachedAt = 0;
  constructor(options = {}) {
    this.descriptorPath = options.descriptorPath ?? process.env.AAALICE_AGENT_CONTROL_DESCRIPTOR;
    this.autoDiscoverDescriptor = options.autoDiscoverDescriptor ?? true;
    this.descriptorSearchPaths = options.descriptorSearchPaths;
    this.explicitBaseUrl = options.baseUrl ?? process.env.AAALICE_AGENT_CONTROL_URL;
    this.explicitToken = options.token ?? process.env.AAALICE_AGENT_CONTROL_TOKEN;
    this.descriptorTtlMs = options.descriptorTtlMs ?? 5e3;
    this.fetchImpl = options.fetchImpl ?? globalThis.fetch;
    if (typeof this.fetchImpl !== "function") {
      throw new Error("DeepSeek Harness requires a host with global fetch.");
    }
  }
  async call(method, params = {}, options = {}) {
    const descriptor = await this.resolveDescriptor();
    const body = {
      protocol: AGENT_CONTROL_PROTOCOL,
      version: AGENT_CONTROL_VERSION,
      request_id: randomUUID(),
      method,
      params
    };
    if (options.idempotencyKey !== void 0) {
      body.idempotency_key = options.idempotencyKey;
    }
    let response;
    try {
      response = await this.fetchImpl(`${descriptor.baseUrl}/v1/commands`, {
        method: "POST",
        headers: {
          accept: "application/json",
          authorization: `Bearer ${descriptor.token}`,
          "content-type": "application/json"
        },
        body: JSON.stringify(body),
        signal: options.signal
      });
    } catch (error) {
      if (options.signal?.aborted) throw error;
      throw new AgentControlRemoteError(
        "transport",
        `Unable to reach Aaalice Agent control API: ${error instanceof Error ? error.message : String(error)}`
      );
    }
    const raw = await response.text();
    if (raw.length > 4 * 1024 * 1024) {
      throw new AgentControlRemoteError(
        "protocol",
        "Aaalice Agent control response exceeded the 4 MiB safety limit."
      );
    }
    let payload;
    try {
      payload = JSON.parse(raw);
    } catch {
      throw new AgentControlRemoteError(
        "protocol",
        `Aaalice Agent control returned non-JSON data (HTTP ${response.status}).`
      );
    }
    if (!isJsonObject(payload)) {
      throw new AgentControlRemoteError(
        "protocol",
        "Aaalice Agent control returned an invalid response object."
      );
    }
    if (payload.protocol !== AGENT_CONTROL_PROTOCOL || payload.version !== AGENT_CONTROL_VERSION) {
      throw new AgentControlRemoteError(
        "protocol",
        "Aaalice Agent control protocol version is not supported."
      );
    }
    if (payload.ok !== true || !response.ok) {
      const error = isJsonObject(payload.error) ? payload.error : {};
      throw new AgentControlRemoteError(
        stringOr(error.code, `http_${response.status}`),
        stringOr(error.message, `Aaalice Agent control failed (HTTP ${response.status}).`),
        isJsonObject(error.details) ? error.details : void 0
      );
    }
    if (!isJsonObject(payload.result)) {
      throw new AgentControlRemoteError(
        "protocol",
        "Aaalice Agent control response did not contain an object result."
      );
    }
    return payload.result;
  }
  async resolveDescriptor() {
    const now = Date.now();
    if (this.cachedDescriptor !== void 0 && this.descriptorTtlMs > 0 && now - this.cachedAt < this.descriptorTtlMs) {
      return this.cachedDescriptor;
    }
    let descriptor;
    if (this.explicitBaseUrl !== void 0 || this.explicitToken !== void 0) {
      if (!this.explicitBaseUrl || !this.explicitToken) {
        throw new AgentControlRemoteError(
          "configuration",
          "AAALICE_AGENT_CONTROL_URL and AAALICE_AGENT_CONTROL_TOKEN must be provided together."
        );
      }
      descriptor = {
        protocol: AGENT_CONTROL_PROTOCOL,
        version: AGENT_CONTROL_VERSION,
        baseUrl: this.explicitBaseUrl,
        token: this.explicitToken
      };
    } else {
      const descriptorPath = await this.resolveDescriptorPath();
      let parsed;
      try {
        parsed = JSON.parse(await readFile(descriptorPath, "utf8"));
      } catch (error) {
        throw new AgentControlRemoteError(
          "configuration",
          `Unable to read Aaalice Agent descriptor: ${error instanceof Error ? error.message : String(error)}`
        );
      }
      if (!isJsonObject(parsed)) {
        throw new AgentControlRemoteError(
          "configuration",
          "Aaalice Agent descriptor must be a JSON object."
        );
      }
      descriptor = {
        protocol: stringOr(parsed.protocol, ""),
        version: stringOr(parsed.version, ""),
        baseUrl: stringOr(parsed.base_url, ""),
        token: stringOr(parsed.token, "")
      };
    }
    if (descriptor.protocol !== AGENT_CONTROL_PROTOCOL || descriptor.version !== AGENT_CONTROL_VERSION) {
      throw new AgentControlRemoteError(
        "configuration",
        "Aaalice Agent descriptor uses an unsupported protocol version."
      );
    }
    const baseUrl = normalizeLoopbackUrl(descriptor.baseUrl);
    if (descriptor.token.trim().length < 16) {
      throw new AgentControlRemoteError(
        "configuration",
        "Aaalice Agent descriptor contains an invalid bearer token."
      );
    }
    this.cachedDescriptor = {
      ...descriptor,
      baseUrl,
      token: descriptor.token.trim()
    };
    this.cachedAt = now;
    return this.cachedDescriptor;
  }
  /**
   * Resolve the descriptor lazily on every cache miss. Aaalice creates and
   * removes the file with its process, so discovery must happen at call time
   * rather than when the Harness plugin is mounted.
   */
  async resolveDescriptorPath() {
    if (this.descriptorPath !== void 0 && this.descriptorPath.trim() !== "") {
      return this.descriptorPath;
    }
    if (!this.autoDiscoverDescriptor) {
      throw new AgentControlRemoteError(
        "configuration",
        "Set AAALICE_AGENT_CONTROL_DESCRIPTOR to the Aaalice agent-control-v1.json path, or provide the URL and token explicitly."
      );
    }
    const candidates = this.descriptorSearchPaths ?? defaultDescriptorSearchPaths();
    let lastError;
    for (const candidate of candidates) {
      try {
        await readFile(candidate, "utf8");
        return candidate;
      } catch (error) {
        lastError = error;
        if (!isMissingFile(error)) throw new AgentControlRemoteError(
          "configuration",
          `Unable to read Aaalice Agent descriptor: ${error instanceof Error ? error.message : String(error)}`
        );
      }
    }
    const first = candidates[0];
    const location = first === void 0 ? "the standard Aaalice support directory" : candidates.length === 1 ? first : `${first} (and ${candidates.length - 1} fallback location${candidates.length === 2 ? "" : "s"})`;
    const detail = lastError instanceof Error ? ` (${lastError.message})` : "";
    throw new AgentControlRemoteError(
      "configuration",
      `Aaalice Agent descriptor was not found at ${location}${detail}. Start Aaalice with ENABLE_AGENT_CONTROL=true, or set AAALICE_AGENT_CONTROL_DESCRIPTOR / AAALICE_AGENT_CONTROL_URL + AAALICE_AGENT_CONTROL_TOKEN.`
    );
  }
};
function defaultDescriptorSearchPaths() {
  const paths = [];
  const add = (root, ...parts) => {
    if (!root || root.trim() === "") return;
    const candidate = join(root, ...parts);
    if (!paths.includes(candidate)) paths.push(candidate);
  };
  const relative = ["com.example", "nai_launcher", "agent", "agent-control-v1.json"];
  add(process.env.APPDATA, ...relative);
  add(process.env.LOCALAPPDATA, ...relative);
  add(join(homedir(), "AppData", "Roaming"), ...relative);
  add(join(homedir(), "AppData", "Local"), ...relative);
  return paths;
}
function isMissingFile(error) {
  return typeof error === "object" && error !== null && "code" in error && error.code === "ENOENT";
}
function normalizeLoopbackUrl(value) {
  let url;
  try {
    url = new URL(value);
  } catch {
    throw new AgentControlRemoteError(
      "configuration",
      "Aaalice Agent control URL is not a valid URL."
    );
  }
  const hostname = url.hostname.replace(/^\[|\]$/g, "").toLowerCase();
  const isLoopback = hostname === "localhost" || hostname === "::1" || isIP(hostname) === 4 && hostname.startsWith("127.");
  if (url.protocol !== "http:" || !isLoopback || url.username !== "" || url.password !== "" || url.pathname !== "" && url.pathname !== "/") {
    throw new AgentControlRemoteError(
      "configuration",
      "Aaalice Agent control must use an http loopback URL."
    );
  }
  url.pathname = url.pathname.replace(/\/+$/, "");
  url.search = "";
  url.hash = "";
  return url.toString().replace(/\/$/, "");
}
function isJsonObject(value) {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}
function stringOr(value, fallback) {
  return typeof value === "string" ? value : fallback;
}

// Aaalice_NAI_Launcher/plugins/deepseek-harness/src/index.ts
var name = "aaalice-agent-control";
var inject = ["tools", "systemPrompt"];
var LAZY_ROUTING_PROMPT = `Aaalice image bridge (\u61D2\u4EBA\u6A21\u5F0F):
When the user asks to generate, draw, render, or edit an image \u2014 including \u751F\u56FE\u3001\u7ED8\u56FE\u3001\u6587\u751F\u56FE\u3001\u56FE\u751F\u56FE\u3001\u63D0\u793A\u8BCD\u8F6C\u6362\u3001AI \u53CD\u63A8\u3001\u53CD\u63A8\u63D0\u793A\u8BCD\u3001\u968F\u673A\u753B\u5E08\u4E32\u3001\u753B\u98CE\u5B9E\u9A8C\u5BA4 \u2014 route the request to Aaalice instead of merely explaining how to do it.
1. Call aaalice_agent_send with one concise natural-language instruction that preserves the user's subject, style, composition, model, size, seed, and other constraints. The Aaalice Agent owns prompt conversion, reverse interrogation, artist-chain style planning, NovelAI generation, queueing, and its in-app approval flow.
2. If the user only asks for an offline random artist-chain/style-lab plan (no rendering), call aaalice_style_lab_plan instead; it is local and does not spend Anlas.
3. Use aaalice_agent_status for status questions and aaalice_agent_abort only when the user asks to stop. If the bridge is unavailable or a call is denied, report that honestly and do not claim an image was generated.
4. Do not ask the user to manually copy a prompt into Aaalice when the bridge is available. Generation charges and confirmation remain controlled by Aaalice; never bypass or invent approval.`;
var jsonObjectOutput = {
  type: "object",
  additionalProperties: true
};
function apply(ctx) {
  const client = new AaaliceAgentControlClient();
  ctx.systemPrompt.section({
    name: "aaalice-agent-control:lazy-routing",
    // Tool guidance occupies 100–199 in DSH. Keep this near the front so the
    // model sees the routing rule before the individual tool descriptions.
    order: 96,
    text: LAZY_ROUTING_PROMPT
  });
  ctx.tools.register(defineTool({
    name: "aaalice_agent_status",
    description: "Read the current Aaalice Agent status, work phase, queue and approval metadata. It does not expose the full transcript.",
    parameters: {},
    output: {
      schema: jsonObjectOutput,
      render: renderJson
    },
    timeoutMs: 3e4,
    async execute(_args, exec) {
      return client.call("agent.status", {}, { signal: exec.signal });
    }
  }));
  ctx.tools.register(defineTool({
    name: "aaalice_agent_send",
    description: "Default bridge for any image task: send the user's request to the Aaalice Agent for \u751F\u56FE/\u7ED8\u56FE/\u6587\u751F\u56FE/\u56FE\u751F\u56FE, prompt conversion, AI reverse prompting, random artist-chain or style-lab work. Call this tool instead of merely explaining the steps. It may consume Anlas only when the Aaalice UI permission and approval flow allows it; do not assume generation was approved.",
    parameters: {
      text: {
        type: "string",
        required: true,
        description: "Prompt text to send to Aaalice."
      },
      follow_up: {
        type: "boolean",
        description: "Queue the prompt while another Aaalice run is active."
      }
    },
    output: {
      schema: jsonObjectOutput,
      render: renderJson
    },
    timeoutMs: 9e5,
    async execute(args, exec) {
      const params = { text: args.text };
      if (args.follow_up !== void 0) params.follow_up = args.follow_up;
      return client.call("agent.send", params, {
        signal: exec.signal,
        idempotencyKey: `dsh-${exec.callId}`
      });
    }
  }));
  ctx.tools.register(defineTool({
    name: "aaalice_agent_abort",
    description: "Abort the active Aaalice Agent run if one is running.",
    parameters: {},
    output: {
      schema: jsonObjectOutput,
      render: renderJson
    },
    timeoutMs: 3e4,
    async execute(_args, exec) {
      return client.call("agent.abort", {}, {
        signal: exec.signal,
        idempotencyKey: `dsh-${exec.callId}`
      });
    }
  }));
  ctx.tools.register(defineTool({
    name: "aaalice_style_lab_plan",
    description: "Create reproducible random artist-chain style-lab A/B prompt pairs offline. This never calls NovelAI and never consumes Anlas.",
    parameters: {
      base_prompt: {
        type: "string",
        description: "Base subject prompt."
      },
      auxiliary_prompt: {
        type: "string",
        description: "Optional additional prompt text."
      },
      artist_pool: {
        type: "string",
        description: "Optional newline/comma-separated artist pool."
      },
      style_pool: {
        type: "string",
        description: "Optional style mutation pool."
      },
      pair_count: {
        type: "integer",
        description: "Number of A/B pairs, from 1 to 12."
      },
      min_artists: {
        type: "integer",
        description: "Minimum artists per chain."
      },
      max_artists: {
        type: "integer",
        description: "Maximum artists per chain."
      },
      artist_weight_min: {
        type: "number",
        description: "Minimum artist weight, from 0.1 to 2."
      },
      artist_weight_max: {
        type: "number",
        description: "Maximum artist weight, from 0.1 to 2."
      },
      min_style_tokens: {
        type: "integer",
        description: "Minimum style mutation tokens."
      },
      max_style_tokens: {
        type: "integer",
        description: "Maximum style mutation tokens."
      },
      mutate_styles: {
        type: "boolean",
        description: "Whether the mutated side receives style tokens."
      },
      seed_mode: {
        type: "string",
        enum: ["randomPerPair", "fixed"],
        description: "Use a new seed per pair or one fixed seed."
      },
      fixed_seed: {
        type: "integer",
        description: "Seed used when seed_mode is fixed."
      },
      draw_seed: {
        type: "integer",
        description: "Seed for the artist/style sampler."
      }
    },
    output: {
      schema: jsonObjectOutput,
      render: renderJson
    },
    timeoutMs: 3e4,
    async execute(args, exec) {
      return client.call("style_lab.plan", compactJson(args), {
        signal: exec.signal
      });
    }
  }));
}
function compactJson(args) {
  const result = {};
  for (const [key, value] of Object.entries(args)) {
    if (value !== void 0) result[key] = value;
  }
  return result;
}
function renderJson(_args, value) {
  return [{ type: "text", text: JSON.stringify(value) }];
}
export {
  apply,
  inject,
  name
};
//# sourceMappingURL=index.js.map
