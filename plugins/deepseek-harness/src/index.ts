import type { Context } from '@deepseek-ai/cordis'
import type { ContentBlock } from '@deepseek-ai/dsh-llm'
import { defineTool } from '@deepseek-ai/dsh-tools'

import {
  AaaliceAgentControlClient,
  type JsonObject,
  type JsonValue,
} from './client.js'

export const name = 'aaalice-agent-control'
export const inject = ['tools']

const jsonObjectOutput = {
  type: 'object',
  additionalProperties: true,
} as const

/** Register the optional Aaalice control tools without changing the Harness loop. */
export function apply(ctx: Context): void {
  const client = new AaaliceAgentControlClient()

  ctx.tools.register(defineTool({
    name: 'aaalice_agent_status',
    description:
      'Read the current Aaalice Agent status, work phase, queue and approval metadata. It does not expose the full transcript.',
    parameters: {},
    output: {
      schema: jsonObjectOutput,
      render: renderJson,
    },
    timeoutMs: 30_000,
    async execute(_args, exec) {
      return client.call('agent.status', {}, { signal: exec.signal })
    },
  }))

  ctx.tools.register(defineTool({
    name: 'aaalice_agent_send',
    description:
      'Send a prompt to the Aaalice Agent. This may consume Anlas only when the Aaalice UI permission and approval flow allows it; do not assume generation was approved.',
    parameters: {
      text: {
        type: 'string',
        required: true,
        description: 'Prompt text to send to Aaalice.',
      },
      follow_up: {
        type: 'boolean',
        description: 'Queue the prompt while another Aaalice run is active.',
      },
    },
    output: {
      schema: jsonObjectOutput,
      render: renderJson,
    },
    timeoutMs: 900_000,
    async execute(args, exec) {
      const params: JsonObject = { text: args.text }
      if (args.follow_up !== undefined) params.follow_up = args.follow_up
      return client.call('agent.send', params, {
        signal: exec.signal,
        idempotencyKey: `dsh-${exec.callId}`,
      })
    },
  }))

  ctx.tools.register(defineTool({
    name: 'aaalice_agent_abort',
    description: 'Abort the active Aaalice Agent run if one is running.',
    parameters: {},
    output: {
      schema: jsonObjectOutput,
      render: renderJson,
    },
    timeoutMs: 30_000,
    async execute(_args, exec) {
      return client.call('agent.abort', {}, {
        signal: exec.signal,
        idempotencyKey: `dsh-${exec.callId}`,
      })
    },
  }))

  ctx.tools.register(defineTool({
    name: 'aaalice_style_lab_plan',
    description:
      'Create reproducible random artist-chain style-lab A/B prompt pairs offline. This never calls NovelAI and never consumes Anlas.',
    parameters: {
      base_prompt: {
        type: 'string',
        description: 'Base subject prompt.',
      },
      auxiliary_prompt: {
        type: 'string',
        description: 'Optional additional prompt text.',
      },
      artist_pool: {
        type: 'string',
        description: 'Optional newline/comma-separated artist pool.',
      },
      style_pool: {
        type: 'string',
        description: 'Optional style mutation pool.',
      },
      pair_count: {
        type: 'integer',
        description: 'Number of A/B pairs, from 1 to 12.',
      },
      min_artists: {
        type: 'integer',
        description: 'Minimum artists per chain.',
      },
      max_artists: {
        type: 'integer',
        description: 'Maximum artists per chain.',
      },
      artist_weight_min: {
        type: 'number',
        description: 'Minimum artist weight, from 0.1 to 2.',
      },
      artist_weight_max: {
        type: 'number',
        description: 'Maximum artist weight, from 0.1 to 2.',
      },
      min_style_tokens: {
        type: 'integer',
        description: 'Minimum style mutation tokens.',
      },
      max_style_tokens: {
        type: 'integer',
        description: 'Maximum style mutation tokens.',
      },
      mutate_styles: {
        type: 'boolean',
        description: 'Whether the mutated side receives style tokens.',
      },
      seed_mode: {
        type: 'string',
        enum: ['randomPerPair', 'fixed'],
        description: 'Use a new seed per pair or one fixed seed.',
      },
      fixed_seed: {
        type: 'integer',
        description: 'Seed used when seed_mode is fixed.',
      },
      draw_seed: {
        type: 'integer',
        description: 'Seed for the artist/style sampler.',
      },
    },
    output: {
      schema: jsonObjectOutput,
      render: renderJson,
    },
    timeoutMs: 30_000,
    async execute(args, exec) {
      return client.call('style_lab.plan', compactJson(args), {
        signal: exec.signal,
      })
    },
  }))
}

function compactJson(args: Record<string, JsonValue | undefined>): JsonObject {
  const result: JsonObject = {}
  for (const [key, value] of Object.entries(args)) {
    if (value !== undefined) result[key] = value
  }
  return result
}

function renderJson(_args: unknown, value: JsonValue): ContentBlock[] {
  return [{ type: 'text', text: JSON.stringify(value) }]
}
