# Photo Collage Creator (Hockney Joiners) — Architecture & Implementation Reference

**Purpose**: This document is a reference architecture and set of implementation directives for an LLM coding assistant. It captures all design decisions for consistent implementation across sessions. The user will specify what to build in each stage; this plan provides the principles and constraints.

---

### 1. Technology Stack

- **Language**: Swift (latest stable)
- **UI Framework**: Hybrid — SwiftUI for app chrome (sidebar, inspector, toolbars, menus, settings), AppKit (`NSViewRepresentable`) for the collage canvas
- **Build System**: Swift Package Manager (SPM) — single package, Xcode project generated from `Package.swift`
- **Rendering Engine**: Core Image (`CIImage`, `CIFilter`, `CIContext`) for both interactive preview and final export
- **macOS Deployment Target**: 14.0 (Sonoma)
- **Third-Party Dependencies**: None — use Apple SDK exclusively

### 2. App Architecture

- **Structure**: Single SPM target, organized into folders that map to logical seams:
  - `App/` — `@main` entry point, `AppDelegate` adaptor, window management, menu bar, settings
  - `Model/` — Data types, JSON coding, validation
  - `Canvas/` — AppKit `NSView` canvas, hit-testing, gesture handling, transform handles, layer compositing
  - `Rendering/` — Core Image export pipeline, thumbnail generation, image loading
  - `Collections/` — Collection scanning, file watching, thumbnail caching, sort logic
  - `Undo/` — Command-pattern undo stack
  - `Views/` — SwiftUI views (sidebar, inspector, toolbars, sheets, settings)
  - `Utilities/` — Extensions, helpers, constants
- **Window Model**: Single unified window using `NavigationSplitView` (three-column: sidebar | canvas | inspector)

### 3. Data Model

All persistence is file-based. No database.

#### 3.1 Collage Project File (`.collage.json`)

```swift
struct CollageProject: Codable {
    var version: Int           // schema version for future migration
    var canvasWidth: CGFloat   // current auto-sized canvas width in points
    var canvasHeight: CGFloat  // current auto-sized canvas height in points
    var backgroundColor: CGColor  // defaults to white, supports transparency
    var layers: [PhotoLayer]
    var createdAt: Date
    var modifiedAt: Date
}

struct PhotoLayer: Codable, Identifiable {
    var id: UUID
    var photoPath: String      // absolute path to source image file
    var position: CGPoint      // center point on canvas
    var size: CGSize           // display size on canvas (not source resolution)
    var rotation: CGFloat      // radians
    var zOrder: Int            // layer depth (higher = on top)
    var opacity: Double        // 0.0–1.0, defaults to 1.0
    var cropRect: CGRect?      // optional crop within the photo, normalized to source image (0–1)
    var featherRadius: CGFloat? // optional soft edge radius (v2), in canvas points
    var blendMode: String?     // optional blend mode name (v2), e.g. "normal", "multiply"
    var sourceResolution: CGSize // original pixel dimensions of the source photo, stored for export
}
```

#### 3.2 Collection File (`.collection.json`)

```swift
struct PhotoCollection: Codable {
    var name: String
    var photos: [CollectionPhoto]
    var createdAt: Date
    var modifiedAt: Date
}

struct CollectionPhoto: Codable, Identifiable {
    var id: UUID
    var path: String           // absolute path to photo on disk
    var addedAt: Date
    var tags: [String]         // optional user tags (v2)
    var rating: Int?           // optional user rating (v2)
}
```

Sidecar `.collection.json` lives in the collection folder alongside the photos.

#### 3.3 Source Resolution Model

- Photos carry their original pixel dimensions in `sourceResolution`
- Canvas editing operates at display/point scale (photos auto-scaled to fit viewport on placement)
- Export offers two modes: render at viewport scale, or render at source resolution using the stored transforms
- Source images are never modified; the project file references them read-only

### 4. Canvas Behavior

#### 4.1 Canvas Sizing

- **Auto-sizing**: Canvas starts at a default size (e.g., 2000×1500 points). As photos are added and moved beyond current bounds, the canvas expands automatically to contain all layers with padding.
- Canvas size is persisted in the project file's `canvasWidth`/`canvasHeight`
- User can manually resize canvas via a dialog (with anchor point selection) at any time

#### 4.2 Photo Placement

- Drag from collection browser onto canvas: photo appears at drop point, auto-scaled so its largest dimension is ~25-30% of the smaller viewport dimension
- Multi-select + batch drop supported: photos cascade with slight offset from drop point
- Each new photo becomes the topmost layer (highest z-order assigned)

#### 4.3 Interaction Model

- **Selection**: Click a photo to select it (deselect previous). Shift-click to add to selection. Click canvas background to deselect all
- **Transform handles**: Selected photos show corner handles (scale proportionally), edge handles (scale non-proportionally), rotation handle above center, and a border
- **Move**: Click and drag inside the selected photo to translate
- **Scale**: Drag corner/edge handles
- **Rotate**: Drag the rotation handle
- **Layer ordering**: Context menu or keyboard shortcuts for "Bring Forward", "Send Backward", "Bring to Front", "Send to Back"
- **Delete**: Delete key removes selected photos
- **Opacity**: Adjust via inspector slider for selected photo(s)
- **Canvas viewport**: Scroll to pan, pinch to zoom the view (not the content). Trackpad/mouse wheel to zoom

#### 4.4 Compositing

- **v1**: Hard edges only. Each photo is an opaque rectangle (or optionally cropped). Overlap determined solely by z-order.
- **Opacity**: Supported in v1. Core Image alpha compositing based on `opacity` property.
- **v2 roadmap**: Soft-edge feathering (`featherRadius`), blend modes (`blendMode`)

### 5. Rendering Pipeline (Core Image)

#### 5.1 Interactive Preview

- Each photo layer produces a `CIImage` via `CIImage(contentsOf: URL)`
- Apply transforms: `CGAffineTransform` for translate + scale + rotate, composited with `CISourceOverCompositing` (or equivalent) in z-order
- Opacity applied via `CIColorMatrix` or alpha adjustment on the source image before compositing
- Background rect filled with `backgroundColor`
- Render to the canvas `NSView` via `CIContext` backed by Metal (automatic with Core Image on macOS 14)
- Debounce continuous gestures: only commit to undo stack on gesture-end

#### 5.2 Export

- Build the same `CIImage` filter graph at the chosen resolution (viewport scale or source resolution)
- If source-resolution export: each layer's transform is mapped from canvas-scale to source-scale using the ratio of `sourceResolution` to `size`
- Render via `CIContext` to `CGImage`, then encode as PNG or JPEG using `CGImageDestination`
- JPEG: quality 0.0–1.0 slider in export dialog
- Scale multiplier: additional uniform scale applied to final render dimensions (0.25×, 0.5×, 1×, 2×, custom)

### 6. Undo/Redo System

#### 6.1 Architecture

- **Command pattern**: Every canvas mutation is encapsulated as a reversible command
- `UndoManager` class maintains two stacks: `undoStack: [Command]` and `redoStack: [Command]`
- Maximum undo depth: configurable (default 100)
- Redo stack is cleared on new action

#### 6.2 Command Protocol

```swift
protocol Command: Codable {
    var timestamp: Date { get }
    var description: String { get }  // human-readable for future undo history UI
    func execute(on project: inout CollageProject)
    func undo(on project: inout CollageProject)
}
```

#### 6.3 Undoable Actions (v1)

| Action | Command stores |
|---|---|
| Add photo(s) | Layer ID(s) added |
| Remove photo(s) | Full layer state(s) + z-order index before removal |
| Move (translate) | Layer ID, old position, new position |
| Resize (scale) | Layer ID, old size, new size |
| Rotate | Layer ID, old rotation, new rotation |
| Change z-order | Layer ID, old zOrder, new zOrder |
| Change opacity | Layer ID, old opacity, new opacity |
| Crop/mask photo | Layer ID, old cropRect, new cropRect |
| Change canvas background | Old color, new color |

#### 6.4 Non-Undoable Actions

- Selection changes (non-destructive)
- Canvas viewport zoom/pan
- Window resize/layout

#### 6.5 Gesture Debouncing

- During a drag/rotate/scale gesture: update canvas display each frame for visual feedback
- On gesture-end: commit ONE command with the final state to the undo stack
- The intermediate frames are never undoable — only the net change is recorded

### 7. Collection Management

#### 7.1 Import Sources

- **Drag-and-drop from Finder**: Accept `NSImage`, file URLs, and folder URLs. Extract all supported image files recursively.
- **File → Import menu**: `NSOpenPanel` configured for image files and folders.
- Supported formats: JPEG, PNG, TIFF, HEIC, BMP, GIF (via `NSImage` / `CGImageSource`)

#### 7.2 Collection Browser UI

- SwiftUI `NavigationSplitView` sidebar: list of collections with name, photo count
- Sort options: by name, date created, date modified (persisted per-collection in UserDefaults)
- Main area: `LazyVGrid` thumbnail grid for selected collection
- Thumbnails: cached as JPEG in `~/Library/Caches/com.collage/thumbnails/` keyed by file path hash
- Drag source: thumbnails are draggable (single or multiple) onto the canvas

#### 7.3 File Watching

- Collections are backed by folders on disk
- On app launch: scan collection folders for added/removed photos
- Optional: `FSEvents` file watching for live updates while app is running (v2)

#### 7.4 File Resilience

- **v1**: Absolute paths stored. If a photo is missing at load time, show a red placeholder rectangle on canvas with the filename. Offer "Locate Photo…" context menu item.
- **v2 roadmap**: Optional "Copy files into collection folder on import" toggle. Relative path resolution fallback.

### 8. Window Layout

Single unified window with three columns:

```
┌──────────────────────────────────────────────────────┐
│ Menu Bar                                             │
├──────────┬────────────────────────┬─────────────────┤
│ Sidebar  │ Canvas                  │ Inspector       │
│          │                         │                 │
│ Collections│ ← Auto-sizing canvas → │ Selected photo: │
│ - List   │                         │ - Position x,y │
│ - Sort   │ Photos placed           │ - Size w,h     │
│ - +/-    │ freeform with handles   │ - Rotation °   │
│          │                         │ - Opacity %    │
│ Photo    │ Zoom/pan viewport        │ - Z-order      │
│ grid     │                         │ - Crop (v2)    │
│          │                         │                 │
│ Drag→    │ ← Drop                  │ Canvas:         │
│          │                         │ - Background    │
│          │                         │ - Size          │
├──────────┴────────────────────────┴─────────────────┤
│ Status Bar (photo count, canvas size, zoom level)    │
└──────────────────────────────────────────────────────┘
```

- Sidebar: ~250pt, collapsible
- Inspector: ~280pt, collapsible
- Canvas: fills remaining space, scrollable, zoomable

### 9. File Operations

#### 9.1 New Collage

- Default canvas: 2000×1500 points, white background
- User prompted for save location immediately (not "untitled" model)
- Creates `.collage.json` file at chosen path

#### 9.2 Open Collage

- `NSOpenPanel` filtered for `.collage.json`
- Load and deserialize via `JSONDecoder`
- On missing photos: show warning dialog listing missing files, placeholders on canvas

#### 9.3 Save

- Auto-save: on every undoable action commit (debounced to once per 2 seconds), serialize current state to the project file via `JSONEncoder`
- Format: pretty-printed JSON for readability
- No explicit "Save" needed; save is continuous

#### 9.4 Save As / Duplicate

- Save As: serialize to a new `.collage.json` path
- Duplicate: save a copy with incremented filename

#### 9.5 Export

- Export dialog: choose format (PNG/JPEG), scale multiplier, JPEG quality (if JPEG)
- Render via export pipeline (see §5.2)
- Save via `NSSavePanel`

### 10. Key Technologies & APIs Used

| Purpose | Apple Framework / API |
|---|---|
| App entry, window scene | SwiftUI `@main`, `WindowGroup`, `MenuBarExtra` |
| Sidebar + split view | `NavigationSplitView` |
| Thumbnail grid | `LazyVGrid`, `GridItem` |
| Canvas view | `NSViewRepresentable`, custom `NSView` subclass |
| Canvas rendering | `CIContext`, `CIImage`, `CIFilter`, Metal-backed |
| Image loading | `NSImage`, `CGImageSource` |
| File dialogs | `NSOpenPanel`, `NSSavePanel` |
| Drag and drop | `Transferable`, `DropDelegate`, `NSDraggingDestination` |
| JSON coding | `Codable`, `JSONEncoder`, `JSONDecoder` |
| Undo | Custom command-pattern `UndoManager` |
| Keyboard events | SwiftUI `keyboardShortcut`, AppKit `NSEvent` for canvas |
| Gestures | `NSGestureRecognizer` (pan, pinch, rotate) on canvas NSView |
| File watching | `FSEvents` (v2) |
| User defaults | `@AppStorage`, `UserDefaults` |
| Thumbnail caching | `FileManager` + `CGImageDestination` for JPEG thumbnails |

### 11. Architectural Principles

1. **No third-party dependencies** — rely exclusively on Apple SDK
2. **File-based storage** — everything is JSON on disk, human-readable, diffable, portable
3. **Canvas is the heart** — prioritize canvas performance and UX; everything else serves the canvas
4. **Hybrid UI** — SwiftUI for structured views, AppKit for freeform canvas interactions
5. **Source fidelity** — never modify source photos; always read-only references
6. **Anticipate extensions** — model properties exist for v2 features (feathering, blend modes) even if unused in v1
7. **Continuous save** — the project file is always up to date; no explicit "Save" required
8. **Command-pattern undo** — granular, serializable, extensible to undo history UI

### 12. Implementation Conventions

- Use `struct` for value types (model data), `class` for reference types (view controllers, managers, undo stack)
- Prefix custom extensions with the app's module name or use descriptive method names to avoid conflicts
- Use `guard` for early exits, `throws` for recoverable errors (missing photos), `fatalError` only for programmer errors
- Image processing on background queues (`DispatchQueue.global(qos: .userInitiated)`); UI updates on `.main`
- Canvas view uses `draw(_:)` with Core Image for rendering, `layout()` for handle positioning
- All dates use `Date` with ISO 8601 encoding in JSON
- File paths use `URL` internally, encoded as absolute path strings in JSON

### 13. Excluded from v1 Scope (Roadmap)

The following are explicitly out of scope for initial implementation but are architecturally anticipated:
- Soft-edge feathering and blend modes (properties exist in model)
- Photos.app integration (`PHAsset`)
- Multi-window support
- Export DPI metadata
- Crop/mask UI on canvas (property exists in model)
- Trackpad gesture transforms (pinch, rotate via gestures)
- Collection file watching (live updates)
- Copy-on-import toggle
- Undo history timeline UI
- WebP/HEIC export
- Printing support
- Localization
