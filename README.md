# Battlebox Generator

Battlebox Generator is a Flutter/Riverpod–based editor for Wikipedia-style “battleboxes” (the **Infobox military conflict** template). It lets you edit an infobox visually while keeping a live wikitext representation in sync.

## Features

- **Visual battlebox editor**
    - Editable title, media, single-field rows, list fields, and multi-column sections (combatants, commanders, units, strength, casualties).
    - Add/remove list items and belligerent columns.
    - Undo and redo visual edits (up to 100 steps).

- **Wikitext import/export**
    - Two-way conversion between a `BattleBoxDoc` model and wikitext via a pluggable `BattleboxSerializer`.
    - Inline editor panel for pasting/importing/exporting raw wikitext.
    - Visual edits update the panel unless it contains unimported manual edits. If both versions change, Copy asks which version to use; Export asks before overwriting a manual draft.
    - Invalid imports leave the document unchanged. Successful imports include a field-by-field report for partially supported templates and markup. Review this report before exporting: conversion is best-effort for some wiki templates.
    - Wikitext imports are limited to 1 MiB and 32 belligerent columns to prevent accidental resource exhaustion.

- **Local recovery**
    - The web editor autosaves both the current visual document and any unapplied raw-wikitext draft in browser `localStorage`, restoring them after a reload.
    - Drafts remain on the current browser/device and may disappear if site storage is cleared or private browsing ends. For long-term backup, use Copy or export.

- **Wiki-style inline rendering**
    - Parses and renders inline wikitext:
        - `{{flagicon|...}}` macros
        - `[[Wiki links]]`, `[https:// external links]`, and bare URLs
    - Uses MediaWiki APIs to resolve:
        - Flag icons (`WikiIconGateway`)
        - Page URLs and existence (blue vs. red links via `WikiLinkGateway`)
        - Image filenames such as `File:Battle.jpg` to thumbnail URLs for previews (`WikiImageGateway`)
    - Supports clickable links via an `ExternalLinkOpener` port.

- **Cross-platform image export**
    - Renders the battlebox card to a PNG and exports it through an `ImageExporter`:
        - Web: triggers a browser download.
        - IO (desktop/mobile): writes to a temporary file and returns its path.
    - Pre-caches flag icons and media images before capture. A failed image is omitted from the PNG instead of blocking export, and the export notice reports missing images.

- **Testable core**
    - Pure domain model and services (`BattleBoxDoc`, sections, `BattleboxEditor`).
    - Abstractions for time (`Clock`) and IDs (`IdGenerator`) to support deterministic testing.
    - Small utilities like `IterableExt.firstOrNull` for ergonomics.
