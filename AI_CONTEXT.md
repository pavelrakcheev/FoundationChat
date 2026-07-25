# Foundation Chat — engineering context

## Purpose

Foundation Chat is a macOS 27 research playground exclusively for Apple
Foundation Models and Private Cloud Compute. It deliberately excludes custom,
open-source and third-party model providers.

## Runtime

- macOS 27 / Xcode 27 beta
- Swift 6.4 language mode
- SwiftUI + Observation
- FoundationModels framework 2.x

## Session invariants

1. A `LanguageModelSession` belongs to exactly one `Conversation.ID`.
2. A cached session is reusable only when model type and system instructions
   still match.
3. When a session is rebuilt, `ModelService` reconstructs a `Transcript` from
   persisted user/assistant messages and excludes UI error messages.
4. Streaming updates target an explicit conversation and message ID, never
   whichever conversation happens to be selected.
5. Cancellation and failed requests invalidate the corresponding cached
   session so UI history and framework transcript cannot silently diverge.

These invariants fix the original cross-chat context leak and stale system
prompt bug.

## Model backends

### SystemLanguageModel

- uses `SystemLanguageModel.default`;
- availability, locale and `contextSize` are queried at runtime;
- no managed reasoning level is exposed.

### PrivateCloudComputeLanguageModel

- requires the managed
  `com.apple.developer.private-cloud-compute` entitlement;
- availability, locale, quota and async `contextSize` are queried;
- requests pass `ContextOptions.reasoningLevel`;
- typed PCC network/quota/service errors are presented separately.

## State and persistence

`ChatViewModel` is `@MainActor @Observable`. Codable conversations, selection,
model and generation settings are stored in `UserDefaults` through
`AppStateStore`. Framework session objects are intentionally process-local and
are reconstructed from persisted messages after launch.

## Token accounting

Before the first model response, the UI shows an explicit estimate. During
streaming it switches to exact Foundation Models 2.x usage:

- input total;
- input cached;
- output total;
- reasoning tokens.

Context limits come from Apple APIs when available, not from the old 8K/32K
constants.

## Markdown contract

The model returns a string; Markdown is not a guaranteed model capability.
Default instructions request GitHub Flavored Markdown. `RichMarkdownView`
interprets the returned string and falls back to plain text semantics when the
model does not emit markup.

## PCC signing

The default build script ad-hoc signs the app for a normal local GUI launch and
therefore intentionally reports PCC as requiring setup. A developer with
Apple-assigned entitlement can provide:

- `FOUNDATIONCHAT_SIGNING_IDENTITY`
- `FOUNDATIONCHAT_PROVISIONING_PROFILE`

The build then embeds the profile and signs with
`Resources/FoundationChat.entitlements`.

## UI structure

- `NavigationSplitView` with a native source-list sidebar;
- standard macOS toolbar and model menu;
- separate SwiftUI `Settings` scene;
- centered readable message column;
- custom composer is the only prominent app-specific Liquid Glass surface;
- all root/sidebar backgrounds remain system-managed.

## Build and validation

Use `./script/build_and_run.sh` as the single entry point:

- default: kill, build, stage `.app`, sign, launch;
- `--verify`: additionally check the process;
- `--logs`, `--telemetry`, `--debug`: diagnostics.

The Icon Composer source is `Resources/AppIcon.icon`; the script uses Xcode's
`ictool` and `iconutil` to generate the `.icns` fallback for the manually staged
SwiftPM app bundle.

## Near-term roadmap

Vision prompt attachments, OCR/Barcode tools, Spotlight RAG, Dynamic Profiles,
guided generation lab, Evaluations, Instruments exports, App Intents/App
Entities for Siri AI, and transcript exchange with the `fm` CLI / Python SDK.

Core AI and MLX are intentionally out of scope because they run custom or
open-source models rather than Apple-provided models.

## Authorship

Created collaboratively by Pavel Rakcheev, DeepSeek v4 Flash (Max Reasoning) in
OpenCode Desktop, and GPT‑5.6 Sol High in ChatGPT Codex.
