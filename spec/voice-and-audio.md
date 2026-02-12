# Voice & Audio

## Wake Word Matching
- Algorithm: Hangul Jamo decomposition + Levenshtein distance over sliding window.
- Window: length = wakeWord.syllables ± 1; whitespace removed before matching.
- Threshold: if not provided, `auto = max(2, jamo_count / 4)`.
- API: `JamoMatcher.isMatch(transcript:String, wakeWord:String, threshold:Int?) -> Bool`.
- Settings: `wakeWordEnabled: Bool`, `wakeWord: String`.

## STT
- Provider: Apple Speech (on‑device/Apple API, per OS settings).
- Silence timeout: `settings.sttSilenceTimeout: Double` seconds.
- Interaction modes: `voiceAndText | textOnly` via `settings.interactionMode`.

## TTS (Supertonic ONNX)
- Voices: `SupertonicVoice = {F1..F5, M1..M5}`.
- Config sourced from model assets: `SupertonicConfig { ae.sample_rate, ae.base_chunk_size, ttl.chunk_compress_factor, ttl.latent_dim }`.
- Controls: `settings.ttsSpeed: Float`, `settings.ttsDiffusionSteps: Int`.
- Pipeline (high level):
  - Text preprocess (emoji removal, punctuation/quote normalization)
  - Unicode indexing → text IDs/mask
  - Duration inference → latent sampling (chunking)
  - Diffusion steps → waveform
  - Audio engine playback; queue managed with `enqueueSentence` and `processQueue`.
- Languages supported (model): `en, ko, es, pt, fr`.

## UX Signals
- Sound effects: `SoundService.playInputComplete()`, `playWakeWordDetected()`.
- Streaming: sentence chunking for incremental TTS playback.

## Open Items
- Default sample rate and assets path to be pinned in spec (read from `SupertonicConfig`).
- Wake word false positive/negative target rates; threshold tuning guidance.
