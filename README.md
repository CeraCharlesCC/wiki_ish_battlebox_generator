# Battlebox Generator

Battlebox Generator is a Flutter/Riverpod–based editor for Wikipedia-style “battleboxes” (the **Infobox military conflict** template). It lets you edit an infobox visually while keeping a live wikitext representation in sync.

## Features

- **Visual battlebox editor**
    - Editable title, media, single-field rows, list fields, and multi-column sections (combatants, commanders, units, strength, casualties).
    - Add/remove list items and belligerent columns.

- **Wikitext import/export**
    - Two-way conversion between a `BattleBoxDoc` model and wikitext via a pluggable `BattleboxSerializer`.
    - Inline editor panel for pasting/importing/exporting raw wikitext.

- **Wiki-style inline rendering**
    - Parses and renders inline wikitext:
        - `{{flagicon|...}}` macros
        - `[[Wiki links]]`, `[https:// external links]`, and bare URLs
    - Uses MediaWiki APIs to resolve:
        - Flag icons (`WikiIconGateway`)
        - Page URLs and existence (blue vs. red links via `WikiLinkGateway`)
    - Supports clickable links via an `ExternalLinkOpener` port.

- **Cross-platform image export**
    - Renders the battlebox card to a PNG and exports it through an `ImageExporter`:
        - Web: triggers a browser download.
        - IO (desktop/mobile): writes to a temporary file and returns its path.
    - Pre-caches flag icons and media images before capture for reliable output.

- **Testable core**
    - Pure domain model and services (`BattleBoxDoc`, sections, `BattleboxEditor`).
    - Abstractions for time (`Clock`) and IDs (`IdGenerator`) to support deterministic testing.
    - Small utilities like `IterableExt.firstOrNull` for ergonomics.
