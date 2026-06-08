# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Overview

Transtype (project/scheme name `opentranstype`) is a macOS menu-bar utility that watches the user's
active text field via the Accessibility (AX) APIs and translates its contents on-device using Apple's
Translation framework. Results appear in a floating overlay; pressing `↓` replaces the original text.
It also offers local (offline) voice dictation via whisper.cpp. Distributed on the App Store with a
StoreKit-gated Pro tier. Requires a very recent macOS (deployment target `26.x`).

## Build & Run

```sh
# Build + relaunch (kills any running instance first). Pass --verify to wait for the new process.
./script/build_and_run.sh

# Plain build
xcodebuild -project opentranstype.xcodeproj -scheme opentranstype -configuration Debug build
```

- Build output goes to `./.derivedData` (gitignored), not the default DerivedData location.
- There is **no test target**; verification is manual (build, run, observe the overlay).
- Diagnostics are written to `~/Library/Logs/Transtype/diagnostics.log` (`DiagnosticLog` in
  `AppCoordinator.swift`). `tail -f` this file — it is the primary debugging tool since most logic
  runs in response to system AX/keyboard events that can't be stepped through easily.
- The app needs **Accessibility permission** (System Settings → Privacy & Security → Accessibility)
  to read/replace text and install the keyboard event tap. Without it, translation services silently
  defer. Voice input additionally needs Microphone permission.

## Architecture

The app is AppKit-driven (`@NSApplicationDelegateAdaptor`); SwiftUI is used only for view content
hosted in `NSWindow`/`NSPanel`. The `Settings { EmptyView() }` scene in `opentranstypeApp.swift` is a
placeholder — there is no real SwiftUI scene.

**`AppCoordinator`** (`Controllers/AppCoordinator.swift`) is the hub. It owns every service and window
controller, wires their callbacks, manages the status-bar menu, and contains the global input-handling
logic. Key responsibilities:
- Single-instance enforcement (`claimSingleRunningInstance`).
- A **CGEvent tap** (`installKeyEventTap`) intercepting `keyDown`/`flagsChanged` system-wide:
  - Typing schedules a debounced re-read of the focused field.
  - `↓` (keycode 125) is *consumed* to apply the translation when one is ready.
  - `Cmd+A` triggers a read of the user's manual selection.
  - **Double-tap Command** toggles local voice dictation.
- A polling `Timer` + `NSWorkspace` observer that track the frontmost app and re-point the AX observer.

**`AccessibilityTextController`** (`Services/`) is the entire AX layer. It installs `AXObserver`s on the
frontmost app, walks the element tree (`findTextTargetElement` searches descendants then ancestors) to
locate an editable text element, reads text (via `AXValue`, selected text, or parameterized
`AXStringForRange`), and replaces text — **preferring clipboard paste (`Cmd+A`/`Cmd+V`)** over
`AXValueAttribute`, restoring the previous pasteboard afterward. When AX reads fail (custom-rendered
inputs like some chat apps), it falls back to copying via synthetic `Cmd+C`. This file is the most
fragile part of the app; per-app AX quirks live here.

**`TranslatorModel`** (`ViewModels/`) is the `ObservableObject` driving the overlay. Translation flow:
1. `updateSourceText` / `forceTranslation` set source text and call `requestTranslation`.
2. A debounced task (`translationDebounce` ~550ms) detects the source language (`NLLanguageRecognizer`,
   with a Han-script fast path → `zh-Hans`), skips same-language input, checks Apple
   `LanguageAvailability`, then runs a `TranslationSession`.
3. Every request carries a monotonically increasing `requestID`; all completion handlers bail if their
   id is stale. This is the concurrency-cancellation pattern used throughout — preserve it when editing.
4. Status strings (all `String(localized:)`) communicate state to the overlay; there is no separate
   state enum.

**Monetization** is split across three services:
- `ProManager` (singleton) — reads StoreKit `Transaction.currentEntitlements`, ranks
  month/year/lifetime products, caches `isPro` in `UserDefaults`. `AppCoordinator` also runs a
  `Transaction.updates` listener.
- `FreeQuotaStore` — `monthlyLimit` (100) free translations/month, keyed by `yyyy-MM` in `UserDefaults`,
  reset on month rollover. Usage is recorded **only when a translation is applied**
  (`recordAppliedTranslation`), not on every translation.
- `AppCoordinator.ensureTranslationAccess` is the single gate: Pro → allow; else check quota, and on
  exhaustion call `model.markUpgradeRequired()` and show the paywall.

**Local voice** (`LocalSpeechTranscriptionService` + `WhisperContext` + `AudioRecorder` +
`WaveFileDecoder`) wraps the prebuilt **`whisper.xcframework`** (vendored at repo root, gitignored).
`LocalSpeechModelManager` downloads ggml whisper models from Hugging Face into Application Support and
tracks the selected one. Recording is a temp WAV decoded to float samples, then transcribed offline.

**Windows** are managed by dedicated controllers: `OverlayWindowController` (the floating `NSPanel` —
contains nontrivial multi-screen positioning/scoring logic to place the overlay near the focused field
without covering it), `DashboardWindowController`, `OnboardingWindowController`, and an inline paywall
`NSWindow` built in `AppCoordinator.showPaywall`.

## Conventions & Gotchas

- **Concurrency:** UI/service classes are `@MainActor`. The CGEvent tap callback and AX observer
  callbacks are `nonisolated` C callbacks that hop back via `Task { @MainActor }` or
  `MainActor.assumeIsolated`; `runOnMainActorSynchronously` is used where the tap must return a
  consume/pass decision synchronously (the `↓` key). Don't make these `async` without preserving the
  synchronous return path.
- **Stale-result guarding:** the `requestID` pattern in `TranslatorModel` is load-bearing. Any new
  async completion that mutates model state must check `requestID == self.requestID` first.
- **Localization:** all user-facing strings use `String(localized:)` backed by `Localizable.xcstrings`.
  Status comparisons in code sometimes compare against `String(localized:)` values (e.g.
  `resetIfStillTranslating`) — keep these in sync if you rename a status string.
- **Sandboxed:** entitlements enable App Sandbox + audio input + network client + user-selected
  read-only files. New capabilities need entitlement changes.
- **Bundle ID inconsistency to be aware of:** the app's bundle id is `com.curisaas.www.opentranstype`
  (project + build script), but the diagnostics log dir and speech-models Application Support path use
  `com.curisaas.opentranstype` / `com.curisaas.www.opentranstype` paths — check the relevant file
  before assuming a path.
- **StoreKit testing:** `opentranstype/TranstypePro.storekit` defines the local StoreKit configuration
  for the month/year/lifetime products (ids in `ProManager.ProductID`).
- App is a menu-bar agent: `applicationShouldTerminateAfterLastWindowClosed` returns `false`; closing
  windows does not quit. Activation policy switches to `.regular` once the translation experience starts.

## Localization tooling

`script/generate_xcloc_localizations.py` generates `.xcloc` bundles from `Localizable.xcstrings`.
App Store metadata and legal copy live under `docs/`.
