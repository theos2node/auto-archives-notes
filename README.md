# Auto Archives Notes

Auto Archives Notes is a small, opinionated notes app built as a proof of concept for turning raw, messy inputs into a structured personal system.

This is an **ongoing project** and a **clear proof of concept**:
- The product is still evolving and UX details will change.
- The on-device model path is intentionally conservative and may fall back to local heuristics depending on OS availability.
- Data formats and “Notion-like” properties may change as the app matures.

## What It Does

The app is designed around a simple loop:
1. Capture a thought quickly (typing or voice).
2. Submit.
3. Forget.
4. Come back to notes that have been cleaned up and enriched.

When you submit a note, the app attempts to:
- Rewrite/correct the note (without changing meaning).
- Generate a short title.
- Add lightweight “Notion-like” properties: kind, status, priority, area, project, people, due date.
- Extract a one-sentence summary and action items.
- Add a small set of tags.

## Key Features

- Fast “composer” for capturing notes.
- Voice recording + transcription.
- Background enhancement (so capture stays fast).
- Simple inbox-style list with search and filters.
- Export all notes as a single JSON file.

## How Enhancement Works

There are two enhancement paths:
- **Apple on-device foundation models (preferred, when available)**: uses `FoundationModels` to rewrite and extract structured fields.
- **Local heuristic fallback**: uses deterministic/NL-based heuristics to generate usable titles, tags, and fields when the model is unavailable.

To avoid concurrency issues with on-device APIs, model calls are run through a single serial queue.

## Export Notes

From the main menu, use `Export` to save a JSON snapshot of the entire database.

Export includes:
- Metadata (`exportedAt`, `count`)
- For each note: ids, timestamps, raw/enhanced text, properties, summary, action items, tags, people, links

## Project Status

This repo is a working prototype. Areas that are intentionally still in-progress:
- UX polish and interaction design
- Better retrieval and “chat with notes” exploration
- More reliable classification, especially around due dates and projects
- Settings, privacy controls, and better conflict/edge-case handling
- Export/import compatibility guarantees

## Development

- Open `Auto archives notes.xcodeproj` in Xcode
- Build and run the `Auto archives notes` scheme

## Website

This repo includes a GitHub Pages site in `docs/`.
