# Shortcut Metadata Workflow

This document describes the implemented shortcut-based metadata flow used by the iPad app.

## Summary

- Trigger point: sparkles button in the sidebar, next to the `+` new-note button.
- Scope: all eligible untitled notes in a batch queue.
- Eligibility:
  - Title is `Untitled` (or empty).
  - Body contains at least one non-whitespace character.
- Model path: Apple Shortcuts configured to use Apple Intelligence -> ChatGPT.
- Result contract: strict JSON with `title` and optional `summary`.

## UX Behavior

### Sparkles Button

- Disabled while a batch is in progress.
- Shows a red dot only when there are eligible untitled notes and no active batch.

### Batch Processing

- Notes are captured into a fixed queue at button tap time.
- The app processes one note at a time.
- Each note is removed from the queue after success, error, or timeout handling.
- This queue behavior prevents re-adding the same note repeatedly.

## App -> Shortcut Contract

The app runs:

- Scheme: `shortcuts://x-callback-url/run-shortcut`
- Shortcut name: `Notes, Meta Data Workflow201`
- Input type: text
- Input payload:
  - System prompt owned by app
  - Followed by note body

Required callback scheme registered by app:

- `autoarchivesnotes://title-callback`

Supported callback statuses:

- `success`
- `cancel`
- `error`

## Expected Shortcut Output

Use strict JSON output:

```json
{"title":"3-5 word title","summary":"one sentence summary"}
```

Rules expected by app:

- `title` should be 3-5 words, specific, without trailing punctuation.
- `summary` is optional, but if present and valid it is appended to note body as:
  - `Summary: ...`

## Required Shortcut Configuration

In the Apple Shortcut:

1. Receive `Shortcut Input` as text (do not use "Ask Each Time").
2. Send that input to Apple Intelligence configured for ChatGPT.
3. Ensure generated output is strict JSON text (no markdown).
4. Add `Copy to Clipboard` action with the JSON output.
5. Add `Stop and Output` action with the same JSON output.
6. Enable "Allow Running from URL" in shortcut details.

Why both `Stop and Output` and clipboard:

- Primary path: callback `result` query value.
- Fallback path: clipboard read when app returns active.

## Install and Missing Shortcut Handling

If shortcut launch fails or callback indicates missing shortcut:

- App displays an install alert.
- Alert includes install action opening:
  - `https://www.icloud.com/shortcuts/00826f09550d431998ceef65e08381e1`

## Timeout and Recovery

- Timeout window: 15 seconds per note.
- On timeout:
  - Note attempt is closed.
  - Batch continues to next note.
  - Alert explains that shortcut must output JSON and copy to clipboard.

## Known Platform Behavior

- Returning to Shortcuts is normal for URL-based shortcut execution.
- Fully background execution is not guaranteed in this mode.
- Clipboard fallback is intentionally included for cases where callback arrives without usable `result`.

## Implementation Notes

Main logic lives in:

- `Auto archives notes/Auto archives notes/ContentView.swift`

Key responsibilities implemented there:

- Eligibility detection and red-dot indicator
- Batch queueing and loop prevention
- Shortcut URL construction and launch
- Callback parsing and JSON decoding
- Clipboard fallback on app foreground transition
- Install prompt and timeout handling
