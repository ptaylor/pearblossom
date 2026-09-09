# Pearblossom File Formats

## Directory Layout

```
~/Pictures/Pearblossom/
├── Collections/                  # Photo collections
│   └── <collection-name>/
│       ├── .collection.json      # Collection metadata
│       ├── .thumbnails/          # Cached thumbnails (auto-generated)
│       └── <photos>              # Copied or referenced photos
└── Collages/                     # Collage projects
    └── <collage-name>.collage.json
```

---

## `.collection.json` — Collection Metadata

Stored as `.collection.json` inside each collection folder under `Collections/`. Filename configurable in Settings (default `.collection.json`).

### Top-Level Fields

| Field | Type | Required | Default | Description |
|---|---|---|---|---|
| `id` | UUID string | Yes | auto | Stable identifier, survives renames |
| `name` | String | Yes | — | Collection display name |
| `description` | String | No | `""` | Optional description |
| `folderPath` | String | No | null | Absolute path to collection folder |
| `photos` | Array of `Photo` | Yes | `[]` | Photos in the collection |
| `importMode` | String | No | `"reference"` | `"copy"` or `"reference"`. Immutable after creation |
| `createdAt` | ISO 8601 date | Yes | now | Creation timestamp |
| `modifiedAt` | ISO 8601 date | Yes | now | Last modification timestamp |

### Photo Object

| Field | Type | Required | Description |
|---|---|---|---|
| `id` | UUID string | Yes | Stable photo identifier |
| `path` | String | Yes | Absolute path (reference mode) or filename (copy mode) |
| `thumbnailPath` | String | No | Path to cached thumbnail, relative to collection folder |
| `addedAt` | ISO 8601 date | Yes | When the photo was added |

### Example

```json
{
  "id": "A1B2C3D4-...",
  "name": "Summer Vacation",
  "description": "Beach photos from July 2026",
  "folderPath": "/Users/paul/Pictures/Pearblossom/Collections/Summer Vacation",
  "photos": [
    {
      "id": "F1E2D3C4-...",
      "path": "DSC_0001.jpg",
      "thumbnailPath": ".thumbnails/DSC_0001_thumb.jpg",
      "addedAt": "2026-07-03T12:00:00Z"
    }
  ],
  "importMode": "reference",
  "createdAt": "2026-07-01T10:00:00Z",
  "modifiedAt": "2026-07-03T12:30:00Z"
}
```

---

## `.collage.json` — Collage Project

Stored as `<name>.collage.json` in the `Collages/` directory.

### Top-Level Fields

| Field | Type | Required | Default | Description |
|---|---|---|---|---|
| `id` | UUID string | Yes | auto | Stable project identifier |
| `version` | Int | No | `1` | Schema version for future migrations |
| `name` | String | Yes | — | Collage display name |
| `description` | String | No | `""` | Optional description |
| `filePath` | String | No | null | Absolute path to this `.collage.json` file |
| `canvasWidth` | Number | No | `2000` | Canvas width in points |
| `canvasHeight` | Number | No | `1500` | Canvas height in points |
| `backgroundColor` | Color object | No | white | Canvas background color (RGBA) |
| `layers` | Array of Layer | Yes | `[]` | Photo layers on the canvas |
| `boundingBoxMode` | String | No | `"definedBorder"` | `"definedBorder"` or `"manual"` |
| `borderMargin` | Number | No | `40` | Margin in points for defined-border mode |
| `manualBoundingBox` | Rect | No | null | User-defined bounding box (manual mode only) |
| `showBoundingBox` | Bool | No | `true` | Whether the bounding box guide is visible |
| `isMultiExposure` | Bool | No | `false` | Whether photos blend as a multi-exposure composite (1/N opacity over black). Immutable after creation |
| `tone` | Tone object | No | identity | Whole-collage levels/saturation adjustment (see Tone Object) |
| `createdAt` | ISO 8601 date | Yes | now | Creation timestamp |
| `modifiedAt` | ISO 8601 date | Yes | now | Last modification timestamp |

### Color Object

```json
{
  "red": 1.0,
  "green": 1.0,
  "blue": 1.0,
  "alpha": 1.0
}
```

Values are 0.0–1.0. Presets: 0%, 5%, 10%, 20%, 40%, 60%, 80%, 100% greyscale.

### Tone Object

```json
{
  "blacks": 0.0,
  "mids": 1.0,
  "whites": 1.0,
  "saturation": 1.0
}
```

A whole-collage tonal adjustment applied to the final composite (both canvas preview and export):

| Field | Type | Description |
|---|---|---|
| `blacks` | Number | 0.0–0.5; input level mapped to pure black (default 0) |
| `mids` | Number | 0.5–2.0; midtone gamma (default 1) |
| `whites` | Number | 0.5–1.0; input level mapped to pure white (default 1) |
| `saturation` | Number | 0.0–2.0; color saturation (default 1) |

### Layer Object

| Field | Type | Required | Description |
|---|---|---|---|
| `id` | UUID string | Yes | Stable layer identifier |
| `collectionID` | UUID string or null | No | UUID of the source collection, or null for Finder drops |
| `photoID` | UUID string or null | No | UUID of the photo within the collection, or null |
| `position` | `[x, y]` | Yes | Center position on canvas in points |
| `size` | `[width, height]` | Yes | Display size on canvas in points |
| `rotation` | Number (radians) | Yes | Rotation angle |
| `zOrder` | Int | Yes | Stacking order (0 = back, higher = front) |
| `opacity` | Number | Yes | 0.0–1.0 |
| `sourceResolution` | `[width, height]` | Yes | Original photo pixel dimensions (for export) |

**Fields reserved for v2 (not yet in use):**

| Field | Type | Description |
|---|---|---|
| `cropRect` | Rect or null | Crop region |
| `featherRadius` | Number or null | Soft-edge feathering |
| `blendMode` | String or null | Compositing blend mode |

### Photo Resolution

`photoPath` is **not stored** in the JSON. Paths are resolved at runtime:

1. If `collectionID` + `photoID` are set → look up the collection on disk, find the photo by ID, resolve its path via `CollectionPhoto.resolvedPath(relativeTo:)`
2. If only `photoID` is set → fall back to a runtime-only path (Finder drops, not persisted)

### Rect (CGRect)

Serialized as `[x, y, width, height]` (origin + size). Used for `manualBoundingBox`.

### Example

```json
{
  "id": "B2C3D4E5-...",
  "version": 1,
  "name": "My Collage",
  "description": "A test collage",
  "canvasWidth": 2000,
  "canvasHeight": 1500,
  "backgroundColor": { "red": 1, "green": 1, "blue": 1, "alpha": 1 },
  "layers": [
    {
      "id": "C3D4E5F6-...",
      "collectionID": "A1B2C3D4-...",
      "photoID": "F1E2D3C4-...",
      "position": [500, 400],
      "size": [600, 450],
      "rotation": 0.1,
      "zOrder": 0,
      "opacity": 1.0,
      "sourceResolution": [4032, 3024]
    }
  ],
  "boundingBoxMode": "definedBorder",
  "borderMargin": 40,
  "showBoundingBox": true,
  "isMultiExposure": false,
  "tone": { "blacks": 0, "mids": 1, "whites": 1, "saturation": 1 },
  "createdAt": "2026-07-03T14:00:00Z",
  "modifiedAt": "2026-07-03T14:05:00Z"
}
```

---

## Image References

- Photos referenced by `collectionID` + `photoID` are resolved at load time. The photo files themselves are **not stored** in the collage JSON.
- If a referenced collection or photo is deleted, the layer is skipped with a warning.
- Finder-dropped photos that have no collection reference store their path at runtime only (in-memory, not persisted).
