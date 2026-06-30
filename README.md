# Pearblossom

A native macOS desktop app for creating photo collages inspired by David Hockney's "Joiners" — composite images made from overlapping, freeform-arranged photographs. Named after Hockney's iconic photomontage *Pearblossom Highway*.

## Tech Stack

- Swift (latest stable), macOS 14+
- SwiftUI + AppKit hybrid UI
- Core Image rendering (Metal-backed)
- Swift Package Manager
- Zero third-party dependencies

## Architecture

See [`ARCHITECTURE.md`](ARCHITECTURE.md) for the full architecture reference — data models, rendering pipeline, undo system, canvas behavior, file formats, and implementation constraints.

See [`AGENTS.md`](AGENTS.md) for LLM coding assistant conventions and instructions.

## Viewing Logs

Pearblossom uses Apple's unified logging system. Debug logging is enabled by default (toggle in Settings → General → Developer).

**In Terminal:**
```bash
log stream --predicate 'subsystem == "com.pearblossom"' --level debug
```

**In Console.app** (`/Applications/Utilities/Console`): filter by `subsystem:com.pearblossom`.

## Status

Early design phase. Implementation will proceed in stages.
