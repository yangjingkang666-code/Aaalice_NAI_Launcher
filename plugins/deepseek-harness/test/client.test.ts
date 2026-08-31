import assert from 'node:assert/strict'
import { test } from 'node:test'

import {
  AaaliceAgentControlClient,
  AgentControlRemoteError,
} from '../src/client.js'

const token = '0123456789abcdef0123456789abcdef'

test('posts a versioned command with bearer auth and idempotency', async () => {
  let requestUrl = ''
  let requestInit: RequestInit | undefined
  const client = new AaaliceAgentControlClient({
    baseUrl: 'http://127.0.0.1:43127/',
    token,
    fetchImpl: async (input, init) => {
      requestUrl = String(input)
      requestInit = init
      return new Response(
        JSON.stringify({
          protocol: 'aaalice-agent-control',
          version: '1',
          request_id: 'server-request-id',
          ok: true,
          result: { accepted: true, charged: false },
        }),
        { status: 200, headers: { 'content-type': 'application/json' } },
      )
    },
  })

  const result = await client.call(
    'style_lab.plan',
    { pair_count: 2 },
    { idempotencyKey: 'dsh-test-1' },
  )

  assert.deepEqual(result, { accepted: true, charged: false })
  assert.equal(requestUrl, 'http://127.0.0.1:43127/v1/commands')
  assert.equal(new Headers(requestInit?.headers).get('authorization'), `Bearer ${token}`)
  const body = JSON.parse(String(requestInit?.body)) as Record<string, unknown>
  assert.equal(body.protocol, 'aaalice-agent-control')
  assert.equal(body.version, '1')
  assert.equal(body.method, 'style_lab.plan')
  assert.equal(body.idempotency_key, 'dsh-test-1')
})

test('rejects non-loopback URLs before sending a token', async () => {
  let called = false
  const client = new AaaliceAgentControlClient({
    baseUrl: 'http://example.invalid',
    token,
    fetchImpl: async () => {
      called = true
      return new Response('{}')
    },
  })

  await assert.rejects(
    client.call('agent.status'),
    (error: unknown) =>
      error instanceof AgentControlRemoteError &&
      error.code === 'configuration' &&
      error.message.includes('loopback'),
  )
  assert.equal(called, false)
})

test('surfaces the server error code and details', async () => {
  const client = new AaaliceAgentControlClient({
    baseUrl: 'http://localhost:43127',
    token,
    fetchImpl: async () =>
      new Response(
        JSON.stringify({
          protocol: 'aaalice-agent-control',
          version: '1',
          request_id: 'request-id',
          ok: false,
          error: {
            code: 'busy',
            message: 'run is busy',
            details: { retry_after_ms: 500 },
          },
        }),
        { status: 409 },
      ),
  })

  await assert.rejects(
    client.call('agent.send', { text: 'hello' }),
    (error: unknown) =>
      error instanceof AgentControlRemoteError &&
      error.code === 'busy' &&
      error.message === 'run is busy' &&
      error.details?.retry_after_ms === 500,
  )
})
