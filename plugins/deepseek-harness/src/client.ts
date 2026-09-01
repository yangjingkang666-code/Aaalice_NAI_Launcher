import { randomUUID } from 'node:crypto'
import { readFile } from 'node:fs/promises'
import { isIP } from 'node:net'
import { homedir } from 'node:os'
import { join } from 'node:path'

export const AGENT_CONTROL_PROTOCOL = 'aaalice-agent-control'
export const AGENT_CONTROL_VERSION = '1'

export type JsonPrimitive = string | number | boolean | null
export type JsonValue = JsonPrimitive | JsonValue[] | { [key: string]: JsonValue }
export type JsonObject = { [key: string]: JsonValue }

export interface AgentControlClientOptions {
  /** Path written by Aaalice's optional local control service. */
  descriptorPath?: string
  /**
   * Try the standard Aaalice support-directory locations when no descriptor
   * path or URL/token pair was supplied. Enabled by default so a desktop
   * Harness can work without a copied token or an environment variable.
   */
  autoDiscoverDescriptor?: boolean
  /** Override the deterministic discovery candidates in host-side tests. */
  descriptorSearchPaths?: readonly string[]
  /** Explicit loopback URL; takes precedence over descriptorPath. */
  baseUrl?: string
  /** Explicit bearer token; must be paired with baseUrl. */
  token?: string
  /** Descriptor cache lifetime. Set to 0 to reload on every call. */
  descriptorTtlMs?: number
  /** Injectable fetch implementation for host-side tests. */
  fetchImpl?: typeof fetch
}

export interface AgentControlCallOptions {
  signal?: AbortSignal
  idempotencyKey?: string
}

interface AgentControlDescriptor {
  protocol: string
  version: string
  baseUrl: string
  token: string
}

export class AgentControlRemoteError extends Error {
  constructor(
    readonly code: string,
    message: string,
    readonly details?: JsonObject,
  ) {
    super(message)
    this.name = 'AgentControlRemoteError'
  }
}

export class AaaliceAgentControlClient {
  private readonly descriptorPath: string | undefined
  private readonly autoDiscoverDescriptor: boolean
  private readonly descriptorSearchPaths: readonly string[] | undefined
  private readonly explicitBaseUrl: string | undefined
  private readonly explicitToken: string | undefined
  private readonly descriptorTtlMs: number
  private readonly fetchImpl: typeof fetch
  private cachedDescriptor: AgentControlDescriptor | undefined
  private cachedAt = 0

  constructor(options: AgentControlClientOptions = {}) {
    this.descriptorPath =
      options.descriptorPath ?? process.env.AAALICE_AGENT_CONTROL_DESCRIPTOR
    this.autoDiscoverDescriptor = options.autoDiscoverDescriptor ?? true
    this.descriptorSearchPaths = options.descriptorSearchPaths
    this.explicitBaseUrl =
      options.baseUrl ?? process.env.AAALICE_AGENT_CONTROL_URL
    this.explicitToken =
      options.token ?? process.env.AAALICE_AGENT_CONTROL_TOKEN
    this.descriptorTtlMs = options.descriptorTtlMs ?? 5_000
    this.fetchImpl = options.fetchImpl ?? globalThis.fetch
    if (typeof this.fetchImpl !== 'function') {
      throw new Error('DeepSeek Harness requires a host with global fetch.')
    }
  }

  async call(
    method: string,
    params: JsonObject = {},
    options: AgentControlCallOptions = {},
  ): Promise<JsonObject> {
    const descriptor = await this.resolveDescriptor()
    const body: JsonObject = {
      protocol: AGENT_CONTROL_PROTOCOL,
      version: AGENT_CONTROL_VERSION,
      request_id: randomUUID(),
      method,
      params,
    }
    if (options.idempotencyKey !== undefined) {
      body.idempotency_key = options.idempotencyKey
    }

    let response: Response
    try {
      response = await this.fetchImpl(`${descriptor.baseUrl}/v1/commands`, {
        method: 'POST',
        headers: {
          accept: 'application/json',
          authorization: `Bearer ${descriptor.token}`,
          'content-type': 'application/json',
        },
        body: JSON.stringify(body),
        signal: options.signal,
      })
    } catch (error) {
      if (options.signal?.aborted) throw error
      throw new AgentControlRemoteError(
        'transport',
        `Unable to reach Aaalice Agent control API: ${error instanceof Error ? error.message : String(error)}`,
      )
    }

    const raw = await response.text()
    if (raw.length > 4 * 1024 * 1024) {
      throw new AgentControlRemoteError(
        'protocol',
        'Aaalice Agent control response exceeded the 4 MiB safety limit.',
      )
    }
    let payload: unknown
    try {
      payload = JSON.parse(raw)
    } catch {
      throw new AgentControlRemoteError(
        'protocol',
        `Aaalice Agent control returned non-JSON data (HTTP ${response.status}).`,
      )
    }
    if (!isJsonObject(payload)) {
      throw new AgentControlRemoteError(
        'protocol',
        'Aaalice Agent control returned an invalid response object.',
      )
    }
    if (
      payload.protocol !== AGENT_CONTROL_PROTOCOL ||
      payload.version !== AGENT_CONTROL_VERSION
    ) {
      throw new AgentControlRemoteError(
        'protocol',
        'Aaalice Agent control protocol version is not supported.',
      )
    }
    if (payload.ok !== true || !response.ok) {
      const error = isJsonObject(payload.error) ? payload.error : {}
      throw new AgentControlRemoteError(
        stringOr(error.code, `http_${response.status}`),
        stringOr(error.message, `Aaalice Agent control failed (HTTP ${response.status}).`),
        isJsonObject(error.details) ? error.details : undefined,
      )
    }
    if (!isJsonObject(payload.result)) {
      throw new AgentControlRemoteError(
        'protocol',
        'Aaalice Agent control response did not contain an object result.',
      )
    }
    return payload.result
  }

  private async resolveDescriptor(): Promise<AgentControlDescriptor> {
    const now = Date.now()
    if (
      this.cachedDescriptor !== undefined &&
      this.descriptorTtlMs > 0 &&
      now - this.cachedAt < this.descriptorTtlMs
    ) {
      return this.cachedDescriptor
    }

    let descriptor: AgentControlDescriptor
    if (this.explicitBaseUrl !== undefined || this.explicitToken !== undefined) {
      if (!this.explicitBaseUrl || !this.explicitToken) {
        throw new AgentControlRemoteError(
          'configuration',
          'AAALICE_AGENT_CONTROL_URL and AAALICE_AGENT_CONTROL_TOKEN must be provided together.',
        )
      }
      descriptor = {
        protocol: AGENT_CONTROL_PROTOCOL,
        version: AGENT_CONTROL_VERSION,
        baseUrl: this.explicitBaseUrl,
        token: this.explicitToken,
      }
    } else {
      const descriptorPath = await this.resolveDescriptorPath()
      let parsed: unknown
      try {
        parsed = JSON.parse(await readFile(descriptorPath, 'utf8'))
      } catch (error) {
        throw new AgentControlRemoteError(
          'configuration',
          `Unable to read Aaalice Agent descriptor: ${error instanceof Error ? error.message : String(error)}`,
        )
      }
      if (!isJsonObject(parsed)) {
        throw new AgentControlRemoteError(
          'configuration',
          'Aaalice Agent descriptor must be a JSON object.',
        )
      }
      descriptor = {
        protocol: stringOr(parsed.protocol, ''),
        version: stringOr(parsed.version, ''),
        baseUrl: stringOr(parsed.base_url, ''),
        token: stringOr(parsed.token, ''),
      }
    }

    if (
      descriptor.protocol !== AGENT_CONTROL_PROTOCOL ||
      descriptor.version !== AGENT_CONTROL_VERSION
    ) {
      throw new AgentControlRemoteError(
        'configuration',
        'Aaalice Agent descriptor uses an unsupported protocol version.',
      )
    }
    const baseUrl = normalizeLoopbackUrl(descriptor.baseUrl)
    if (descriptor.token.trim().length < 16) {
      throw new AgentControlRemoteError(
        'configuration',
        'Aaalice Agent descriptor contains an invalid bearer token.',
      )
    }
    this.cachedDescriptor = {
      ...descriptor,
      baseUrl,
      token: descriptor.token.trim(),
    }
    this.cachedAt = now
    return this.cachedDescriptor
  }

  /**
   * Resolve the descriptor lazily on every cache miss. Aaalice creates and
   * removes the file with its process, so discovery must happen at call time
   * rather than when the Harness plugin is mounted.
   */
  private async resolveDescriptorPath(): Promise<string> {
    if (this.descriptorPath !== undefined && this.descriptorPath.trim() !== '') {
      return this.descriptorPath
    }
    if (!this.autoDiscoverDescriptor) {
      throw new AgentControlRemoteError(
        'configuration',
        'Set AAALICE_AGENT_CONTROL_DESCRIPTOR to the Aaalice agent-control-v1.json path, or provide the URL and token explicitly.',
      )
    }

    const candidates = this.descriptorSearchPaths ?? defaultDescriptorSearchPaths()
    let lastError: unknown
    for (const candidate of candidates) {
      try {
        // Reading is intentionally the existence check: it avoids a TOCTOU
        // race while Aaalice is rotating the descriptor during startup.
        await readFile(candidate, 'utf8')
        return candidate
      } catch (error) {
        lastError = error
        if (!isMissingFile(error)) throw new AgentControlRemoteError(
          'configuration',
          `Unable to read Aaalice Agent descriptor: ${error instanceof Error ? error.message : String(error)}`,
        )
      }
    }

    const first = candidates[0]
    const location = first === undefined
      ? 'the standard Aaalice support directory'
      : candidates.length === 1
        ? first
        : `${first} (and ${candidates.length - 1} fallback location${candidates.length === 2 ? '' : 's'})`
    const detail = lastError instanceof Error ? ` (${lastError.message})` : ''
    throw new AgentControlRemoteError(
      'configuration',
      `Aaalice Agent descriptor was not found at ${location}${detail}. Start Aaalice with ENABLE_AGENT_CONTROL=true, or set AAALICE_AGENT_CONTROL_DESCRIPTOR / AAALICE_AGENT_CONTROL_URL + AAALICE_AGENT_CONTROL_TOKEN.`,
    )
  }
}

function defaultDescriptorSearchPaths(): string[] {
  const paths: string[] = []
  const add = (root: string | undefined, ...parts: string[]) => {
    if (!root || root.trim() === '') return
    const candidate = join(root, ...parts)
    if (!paths.includes(candidate)) paths.push(candidate)
  }
  const relative = ['com.example', 'nai_launcher', 'agent', 'agent-control-v1.json']
  add(process.env.APPDATA, ...relative)
  add(process.env.LOCALAPPDATA, ...relative)
  add(join(homedir(), 'AppData', 'Roaming'), ...relative)
  add(join(homedir(), 'AppData', 'Local'), ...relative)
  return paths
}

function isMissingFile(error: unknown): boolean {
  return typeof error === 'object' && error !== null &&
    'code' in error && (error as { code?: unknown }).code === 'ENOENT'
}

function normalizeLoopbackUrl(value: string): string {
  let url: URL
  try {
    url = new URL(value)
  } catch {
    throw new AgentControlRemoteError(
      'configuration',
      'Aaalice Agent control URL is not a valid URL.',
    )
  }
  const hostname = url.hostname.replace(/^\[|\]$/g, '').toLowerCase()
  const isLoopback =
    hostname === 'localhost' ||
    hostname === '::1' ||
    (isIP(hostname) === 4 && hostname.startsWith('127.'))
  if (
    url.protocol !== 'http:' ||
    !isLoopback ||
    url.username !== '' ||
    url.password !== '' ||
    (url.pathname !== '' && url.pathname !== '/')
  ) {
    throw new AgentControlRemoteError(
      'configuration',
      'Aaalice Agent control must use an http loopback URL.',
    )
  }
  url.pathname = url.pathname.replace(/\/+$/, '')
  url.search = ''
  url.hash = ''
  return url.toString().replace(/\/$/, '')
}

function isJsonObject(value: unknown): value is JsonObject {
  return (
    typeof value === 'object' &&
    value !== null &&
    !Array.isArray(value)
  )
}

function stringOr(value: JsonValue | undefined, fallback: string): string {
  return typeof value === 'string' ? value : fallback
}
