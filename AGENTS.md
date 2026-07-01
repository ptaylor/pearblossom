# AGENTS.md — LLM Coding Assistant Instructions

This file provides instructions and conventions for LLM coding assistants working on this project. Read it before generating any code.

## Project

A macOS desktop app for creating photo collages in the style of David Hockney's "Joiners" — overlapping, misaligned photographs that form a composite image. Working title: **Pearblossom**.

## Architecture Reference

**Read `ARCHITECTURE.md` before writing any code.** It is the authoritative source for all design decisions, data models, and implementation constraints. This file covers day-to-day coding conventions.

## Stack & Constraints

- **Language**: Swift (latest stable)
- **Platform**: macOS 14+ (Sonoma), native only
- **UI**: SwiftUI hybrid with AppKit canvas via `NSViewRepresentable`
- **Build**: Swift Package Manager (`Package.swift`)
- **Rendering**: Core Image (Metal-backed)
- **Storage**: File-based JSON (`.collage.json`, `.collection.json`)
- **Dependencies**: NONE — Apple SDK only
- **macOS deployment target**: 14.0

## How We Build

- Build: `swift build`
- Run: `swift run` (CLI mode, if applicable) or open in Xcode via `open Package.swift`
- No third-party package dependencies — ever

## Git Commits

Every commit must include attribution to the LLM coding assistant and model that generated the code. Use `git commit --trailer` or append the following trailers to every commit message:

```
Co-authored-by: GitHub Copilot <copilot@github.com>
Model: DeepSeek V4 Pro
```

When using `git commit -m`, include the trailers in the message body. When using an editor, add them after the commit description. This applies to ALL commits — code, documentation, configuration, and generated assets.

Example:

```
Add canvas hit-testing for photo layer selection

Implement point-in-rect hit testing with rotation transform,
handle z-order priority for overlapping layers.

Co-authored-by: GitHub Copilot <copilot@github.com>
Model: DeepSeek V4 Pro
```

## Coding Conventions

### Swift Style

- Use `struct` for value types (model data, configurations)
- Use `class` for reference types (view controllers, managers, the undo stack)
- Use `guard` for early exits; `throws` for recoverable errors (e.g., missing photo file)
- `fatalError` only for programmer errors, never for runtime data issues
- All dates use `Date` with ISO 8601 encoding in JSON
- File paths use `URL` internally; serialized as absolute path strings in JSON

### Threading

- Image processing on `DispatchQueue.global(qos: .userInitiated)`
- UI updates strictly on `DispatchQueue.main`
- Core Image operations on a shared background `CIContext`

### Naming & Organization

- No prefixes on types; use descriptive names
- Extensions on system types should be in `Utilities/` folder
- Each logical seam has its own folder: `App/`, `Model/`, `Canvas/`, `Rendering/`, `Collections/`, `Undo/`, `Views/`, `Utilities/`

## Key Patterns

### Auto-Save

The project file saves continuously. On every undoable command commit (debounced to 2 seconds), serialize the full `CollageProject` to `.collage.json` via `JSONEncoder` with pretty-printing.

### Undo/Redo

Command-pattern. Every canvas mutation is a `Command` with `execute(on:)` and `undo(on:)`. During continuous gestures (drag, rotate, scale), update the canvas display every frame but commit exactly one command on gesture-end. The intermediate frames are never undoable.

### Drag & Drop

- Finder → app: Accept file URLs and `NSImage` via `Transferable`
- Collection browser → canvas: Draggable thumbnails with the photo path as transfer data
- Canvas drop: Create a `PhotoLayer` at the drop point, auto-scaled to ~25-30% of viewport

### Source Resolution

- Photos always store their original pixel dimensions in `sourceResolution`
- Editing is done at display/point scale
- Export can render at viewport resolution or full source resolution

## What NOT to Build (v1)

Do not implement any of these even if the model properties exist:
- Soft-edge feathering UI (`featherRadius`)
- Blend mode picker (`blendMode`)
- Photos.app integration
- Multi-window support
- Export DPI metadata
- Crop UI (property exists in model but no UI yet)
- Trackpad pinch/rotate gestures on canvas
- Live file watching (`FSEvents`)
- Copy-on-import
- Undo history timeline panel
- WebP/HEIC export
- Printing
- Localization

## When in Doubt

1. Re-read `ARCHITECTURE.md`
2. Prefer the simplest Apple SDK approach — no clever workarounds
3. No new dependencies
4. Ask the user if a design decision isn't covered by the plan

## Before Making Changes

When asked to implement a non-trivial feature or change — or to create a plan for one — do not jump straight into code (or the plan). Always:

1. **Ask clarifying questions** — identify ambiguities, edge cases, and unstated assumptions before writing anything
2. **Present options with recommendations** — lay out the viable approaches, trade-offs, and recommend the best fit given the architecture
3. **Resolve dependencies first** — if the change touches multiple concerns (data model, UI, persistence), walk through the implications before implementing
4. **Confirm the approach** — get explicit agreement before writing code

## Logging

All non-trivial events must be logged using the `Logger` utility (`Utilities/Logger.swift`):

- **`Logger.debug("message")`** — for diagnostic events (app startup/shutdown, collection operations, import/export, state changes). Respects the debug logging setting.
- **`Logger.warn("message")`** — for unexpected but handled conditions (missing files, recoverable errors).
- **`Logger.error("message")`** — for actual failures (file I/O errors, decode failures).

Rule of thumb: if the event would help someone diagnose a problem later, log it. Log at minimum: app lifecycle, collection CRUD, import/export, and any file I/O operation that could fail.
