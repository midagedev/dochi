# LLM Requirements (Provider‑Agnostic)

This document sets provider‑agnostic constraints and behaviors for LLM usage.

## Capabilities
- Streaming text responses with partial tokens; ability to cancel mid‑stream.
- Function/tool calling: model emits tool name and JSON arguments; multiple sequential calls supported.
- Image inputs (optional): messages may include image URLs for vision models.

## Context Composition
- Layers combined in order: base rules → agent persona → workspace memory → agent memory → personal memory → recent summaries.
- Target context size: bounded by configurable limit; apply summarization/compression when exceeding.
- Initial target cap: 80k characters (review with model tokenization) and 30 recent messages max.

## Prompting & System Behavior
- Default language: Korean, unless user indicates otherwise.
- Safety and guardrails: avoid executing high‑risk actions without explicit confirmation.

## Token & Usage
- Track input/output/total tokens per exchange for diagnostics and cost awareness.
- Model routing (future): pick lightweight vs advanced models by task; define fallback chain if primary fails.
  - Initial policy: default model for chat; advanced for coding/analysis; manual override allowed.

## Errors & Retries
- Transient failures: limited retries with backoff.
- Provider errors: surface concise message; suggest switching model if persistent.
  - Retry policy: up to 2 retries with 250/750ms backoff; never retry non‑idempotent tool effects.

## Time & Persona Awareness
- Include current local time in context for time‑sensitive replies.
- Respect active agent’s role/tone/permissions when generating responses.

## Cancellation & Timeouts
- User cancellation stops streaming and any pending tool execution where possible.
- Timeouts: provider request timeout 20s for first byte; total exchange soft limit 60s, with graceful abort.
