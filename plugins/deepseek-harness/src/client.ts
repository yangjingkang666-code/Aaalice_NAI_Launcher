import { randomUUID } from 'node:crypto'
import { readFile } from 'node:fs/promises'
import { isIP } from 'node:net'

export const AGENT_CONTROL_PROTOCOL = 'aaalice-agent-control'
export const AGENT_CONTROL_VERSION = '1'

export type JsonPrimitive = string | number | boolean | null
export type JsonValue = JsonPrimitive | JsonValue[] | { [key: string]: JsonValue }
export type JsonObject = { [key: string]: JsonValue }

export interface AgentControlClientOptions {
  /** Path written by Aaalice's optional local control service. */
  descriptorPath?: string
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
  private readonly explicitBaseUrl: string | undefined
  private readonly explicitToken: string | undefined
  private readonly descriptorTtlMs: number
  private readonly fetchImpl: typeof fetch
  private cachedDescriptor: AgentControlDescriptor | undefined
  private cachedAt = 0

  constructor(options: AgentControlClientOptions = {}) {
    this.descriptorPath =
      options.descriptorPath ?? process.env.AAALICE_AGENT_CONTROL_DESCRIPTOR
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
      if (!this.descriptorPath) {
        throw new AgentControlRemoteError(
          'configuration',
          'Set AAALICE_AGENT_CONTROL_DESCRIPTOR to the Aaalice agent-control-v1.json path, or provide the URL and token explicitly.',
        )
      }
      let parsed: unknown
      try {
        parsed = JSON.parse(await readFile(this.descriptorPath, 'utf8'))
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
