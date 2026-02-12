# Core Flows (High‑Level)

This document outlines end‑to‑end flows without implementation details.

## Text Interaction Flow
- Trigger: user enters text in app UI.
- Compose context: base rules + workspace memory + agent persona/memory + (optional) personal memory + recent summaries.
- Send to LLM with streaming; render partials; allow cancel.
- If tool calls are returned, execute allowed tools, stream snippets, merge results into response.
- Persist conversation entry and optional summary; update memories if instructed.

Acceptance (Given–When–Then)
- Given valid model and keys, When user sends text, Then first partial appears within Target.Latency.text_first_partial and full answer within Target.Latency.text_full.
- Given tool call needed, When tools are permitted, Then tool result is included or error surfaced with remediation.
- Given network loss mid‑stream, When retry budget remains, Then resume or degrade to local response with notice.

## Voice Interaction Flow
- Trigger: wake word or UI toggle → STT session.
- Capture utterance until silence timeout; optional continuous mode.
- Same context composition as text; LLM streaming.
- Convert final response to speech; play via audio engine; allow barge‑in/cancel.

Acceptance
- Given wake word enabled, When user speaks the wake word within typical noise, Then detection rate meets Target.WakeWord.FRR/FAR bands.
- Given STT is active, When silence exceeds timeout, Then input closes and response TTS starts within Target.Latency.tts_first_audio.
- Given user interrupts, When barge‑in occurs, Then current TTS stops and new input is accepted.

## Telegram Interaction Flow
- Trigger: DM received.
- Resolve applicable workspace and agent; apply conservative permissions.
- Same LLM/tool path; stream progress snippets; send final text (and images if any).

Acceptance
- Given mapped workspace, When DM arrives, Then assistant replies and progress snippets stream without exposing sensitive operations.
- Given risky tool is requested, When from remote interface, Then confirmation is required or action is declined with rationale.

## Tool Invocation Flow
- LLM returns one or more tool calls with arguments.
- Validate: availability, permissions, required inputs.
- Execute; capture structured result or error; return result to LLM for follow‑up.

Acceptance
- Given valid inputs and allowed category, When tool runs, Then result is returned in human‑readable form with minimal details.
- Given missing/invalid inputs, When validation fails, Then clear error with guidance is returned without side effects.

## Memory Update Flow
- Detect salient facts from conversation (automatic) or explicit user command.
- Write to appropriate scope: workspace vs personal vs agent.
- Optional compression/roll‑up to keep within size targets.

Acceptance
- Given a salient fact, When user consents or policy allows, Then fact is appended to the correct scope within size limits.
- Given memory exceeds cap, When compression runs, Then meaning is preserved and old entries remain inspectable.

## Sync & Device Selection Flow
- Local device acts independently; cloud used for synchronization only.
- When remote interfaces (e.g., Telegram) are used, route execution to suitable online device.
- Avoid conflicts via lightweight leadership/locking; fail‑open if cloud is unavailable.

Acceptance
- Given multiple devices online, When a task originates remotely, Then a single leader executes and others stay idle.
- Given cloud is unavailable, When user requests an action, Then local behavior continues and sync resumes later.

## Failure Handling (Generic)
- Network/API errors: surface to user, retry where safe, provide fallback behavior.
- Tool failures: display reason and minimal repro context, suggest corrective action.
- Audio/STT/TTS issues: degrade gracefully to text.
