# SPEC: EXIF Display & Export Metadata

**Status**: Planned (not yet implemented)
**Created**: 2026-07-07
**Scope**: Collection photo EXIF viewer + custom metadata embedding on export

---

## Overview

Two complementary features:

1. **EXIF Display** — Show essential camera metadata (camera, aperture, ISO, shutter, focal length, date) in the collection photo info panel. Read on-the-fly, cached in memory, no model changes.

2. **Export Metadata** — Embed a list of source images and Pearblossom info into exported collage files via XMP (JPEG) or PNG text chunks. Optional toggle in export dialog.

---

## Feature 1: EXIF Display in Collections

### UX

In `CollectionsListView`, when a single photo is selected, the info panel (`photoInfoRow`) currently shows:
- Resolved file path
- Pixel dimensions (e.g., `4032 × 3024 px`)
- Collection name

**After this feature**, an EXIF section appears below the pixel dimensions:

```
📷 EXIF
Camera     Apple iPhone 15 Pro
Aperture   f/1.8
ISO        400
Shutter    1/125s
Focal      50mm
Date       Jul 4, 2026 at 3:42 PM
```

- Fields with unavailable data are omitted (not shown as "—").
- If no EXIF at all (e.g., a downloaded image stripped of metadata), the entire EXIF section is hidden.
- While loading, a subtle "Loading…" placeholder or spinner is shown.

### Data Model

**`EXIFData` struct** — `Sources/Pearblossom/Utilities/EXIFReader.swift`

```swift
struct EXIFData {
    var cameraMake: String?       // e.g. "Apple"
    var cameraModel: String?      // e.g. "iPhone 15 Pro"
    var aperture: String?         // e.g. "f/1.8"
    var iso: Int?                 // e.g. 400
    var shutterSpeed: String?     // e.g. "1/125"
    var focalLength: String?      // e.g. "50mm"
    var dateTaken: Date?          // original capture date
    var pixelWidth: CGFloat?
    var pixelHeight: CGFloat?
}
```

All fields optional — populate what's available from the source file.

### EXIF Reader

**`EXIFReader`** — static utility, same file.

```swift
enum EXIFReader {
    static func read(from path: String) -> EXIFData?
}
```

Implementation:
- Open file via `CGImageSourceCreateWithURL`
- Call `CGImageSourceCopyPropertiesAtIndex(src, 0, nil)` → `[CFString: Any]`
- Extract from `kCGImagePropertyTIFFDictionary`: `kCGImagePropertyTIFFMake`, `kCGImagePropertyTIFFModel`
- Extract from `kCGImagePropertyExifDictionary`: `kCGImagePropertyExifFNumber`, `kCGImagePropertyExifISOSpeedRatings`, `kCGImagePropertyExifExposureTime`, `kCGImagePropertyExifFocalLength`, `kCGImagePropertyExifDateTimeOriginal`
- Format aperture from `fNumber` (e.g., `2.2` → `"f/2.2"`)
- Format shutter from `exposureTime` (e.g., `0.008` → `"1/125"`)
- Format focal length from `focalLength` (e.g., `50.0` → `"50mm"`)
- Parse date string `"2026:07:04 15:42:00"` → `Date`
- Read pixel dimensions from `kCGImagePropertyPixelWidth` / `kCGImagePropertyPixelHeight`
- Run on `DispatchQueue.global(qos: .utility)` — file I/O, not main thread
- Return `nil` if file can't be opened or has no properties

### In-Memory Cache

In `CollectionsListView`:

```swift
@State private var exifCache: [UUID: EXIFData] = [:]
```

- Keyed by `CollectionPhoto.id` (UUID)
- On photo selection (`selectedPhotoID` changes → calls `loadEXIF(for:)`)
- If `exifCache[id] != nil`, display immediately
- If not cached, dispatch background read, store result on main queue
- Cache cleared when collection changes (`selectedCollectionID` changes) or on manual refresh
- No persistence — fresh reads each app launch

### UI Modifications

**File**: `Sources/Pearblossom/Views/CollectionsListView.swift`

- Add `@State private var exifData: EXIFData?` for the currently selected photo
- Add `@State private var isLoadingEXIF: Bool = false`
- Add `loadEXIF(for photoID: UUID, at path: String)` method (async, dispatches to utility queue)
- In `photoInfoRow`, after the existing pixel dimensions section:

```swift
if let exif = exifData, hasAnyEXIF(exif) {
    Divider()
        .padding(.vertical, 2)
    Text("EXIF")
        .font(.caption)
        .fontWeight(.semibold)
        .foregroundColor(.secondary)
    if let camera = exifCameraString(exif) {
        infoRow(label: "Camera", value: camera)
    }
    if let aperture = exif.aperture {
        infoRow(label: "Aperture", value: aperture)
    }
    if let iso = exif.iso {
        infoRow(label: "ISO", value: "\(iso)")
    }
    if let shutter = exif.shutterSpeed {
        infoRow(label: "Shutter", value: shutter)
    }
    if let focal = exif.focalLength {
        infoRow(label: "Focal", value: focal)
    }
    if let date = exif.dateTaken {
        infoRow(label: "Date", value: date.formatted(date: .abbreviated, time: .shortened))
    }
} else if isLoadingEXIF {
    HStack {
        ProgressView().scaleEffect(0.5).controlSize(.small)
        Text("Reading metadata…").font(.caption).foregroundColor(.secondary)
    }
}
```

- Helper `hasAnyEXIF(_:)` — returns `true` if any non-pixel field is non-nil
- Helper `exifCameraString(_:)` — combines make + model, e.g. `"Apple iPhone 15 Pro"`, or just one if the other is nil
- Helper `infoRow(label:value:)` — a small private View with the label/value layout

---

## Feature 2: Export Metadata Embedding

### UX

In the export dialog (`ExportSettingsView`), below the JPEG quality slider:

```
[x] Embed Metadata
    Include source image list and Pearblossom info in the exported file.
```

- Default: ON (checked)
- State persisted to `UserDefaults` via `AppSettings.embedExportMetadata`
- When ON: exported file contains custom metadata (see below)
- When OFF: exported file contains only DPI (current behavior)

### Metadata Content

When embedding is enabled, the export includes:

1. **Source image list** — for each layer in the collage:
   - Filename (e.g., `IMG_4201.jpg`)
   - Pixel resolution (e.g., `4032 × 3024`)
   - Approximate canvas position (e.g., `at (512, 384)`)
   
2. **Pearblossom info**:
   - App name: `Pearblossom`
   - App version (from `Bundle.main`)
   - Collage name
   - Export date (ISO 8601)

No EXIF from source photos is copied — this is custom metadata describing the collage.

### `ExportMetadata` Struct

**File**: `Sources/Pearblossom/Rendering/ExportMetadata.swift` (new)

```swift
struct ExportMetadata {
    struct SourceImage {
        let filename: String
        let pixelWidth: Int
        let pixelHeight: Int
    }
    let sourceImages: [SourceImage]
    let collageName: String
    let exportDate: Date
    let appVersion: String
}
```

### Embedding Strategy

**JPEG**: Embed via XMP (Adobe Extensible Metadata Platform). An XMP packet is a small XML block appended to the JPEG file after the image data but before the EOI marker. The packet goes into the `kCGImagePropertyXMPDictionary` metadata key in the `CGImageDestination` options. Falls back to writing into `kCGImagePropertyExifUserComment` if XMP is unsupported for the destination.

**PNG**: Embed via tEXt/iTXt chunks using `kCGImagePropertyPNGDictionary` with custom keyword/text pairs. One keyword per piece of metadata (e.g., `"Pearblossom Source Images"`, `"Pearblossom Collage Name"`).

**Method on `ExportMetadata`**:

```swift
func apply(to options: inout [CFString: Any], format: ExportFormat)
```

This mutates the options dictionary passed to `CGImageDestinationAddImage`, adding the appropriate XMP or PNG text chunk entries. The calling code in `ExportWriter.write()` calls this before finalizing.

### Export Flow Changes

**`ExportRenderer`** — compile source image list:

```swift
static func sourceImageList(project: CollageProject) -> [ExportMetadata.SourceImage] {
    project.layers.sorted { $0.zOrder < $1.zOrder }.compactMap { layer in
        let path = layer.resolvedPhotoPath()
        let filename = URL(fileURLWithPath: path).lastPathComponent
        return ExportMetadata.SourceImage(
            filename: filename,
            pixelWidth: Int(layer.sourceResolution.width),
            pixelHeight: Int(layer.sourceResolution.height)
        )
    }
}
```

**`ExportWriter.write()`** — new signature:

```swift
static func write(
    _ image: CGImage,
    to url: URL,
    format: ExportFormat,
    jpegQuality: Double = 0.92,
    dpi: CGFloat? = nil,
    metadata: ExportMetadata? = nil   // NEW
) throws
```

Inside `write()`, after populating DPI options:

```swift
if let metadata = metadata {
    metadata.apply(to: &options, format: format)
}
```

**`ExportSettingsView.performExport()`** — build and pass metadata:

```swift
let exportMeta: ExportMetadata?
if embedMetadata {
    exportMeta = ExportMetadata(
        sourceImages: ExportRenderer.sourceImageList(project: project),
        collageName: project.name,
        exportDate: Date(),
        appVersion: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
    )
} else {
    exportMeta = nil
}
ExportWriter.write(image, to: url, format: selectedFormat,
                   jpegQuality: jpegQuality, dpi: sourceDPI,
                   metadata: exportMeta)
```

### Toggle in Export Dialog

**File**: `Sources/Pearblossom/Views/ExportSettingsView.swift`

- Add `@State private var embedMetadata: Bool` initialized from `AppSettings.shared.embedExportMetadata`
- Add toggle row below JPEG quality (only when format is JPEG) or always visible:

```swift
Toggle(isOn: $embedMetadata) {
    VStack(alignment: .leading, spacing: 2) {
        Text("Embed Metadata")
        Text("Include source image list and Pearblossom info.")
            .font(.caption)
            .foregroundColor(.secondary)
    }
}
.onChange(of: embedMetadata) { _, newValue in
    AppSettings.shared.embedExportMetadata = newValue
}
```

### AppSettings

**File**: `Sources/Pearblossom/App/AppSettings.swift`

New key:

```swift
case embedExportMetadata = "embedExportMetadata"
```

Default: `true`. Loaded in `init()`, persisted on change.

---

## Excluded from Scope

- ❌ Copying source photo EXIF to export (user chose custom Pearblossom metadata)
- ❌ GPS coordinate display or embedding (privacy sensitivity)
- ❌ EXIF editing / modification of source files
- ❌ EXIF display on collage canvas (only in collection browser)
- ❌ Batch EXIF reading for entire collection (lazy, per-photo on selection)
- ❌ XMP sidecar files (embedded only, no `.xmp` files)
- ❌ HEIC/WebP export metadata (PNG + JPEG only for v1)

---

## Implementation Order

| Step | File | Action |
|------|------|--------|
| 1 | `Utilities/EXIFReader.swift` | **NEW** — `EXIFData` struct + `EXIFReader.read()` |
| 2 | `Views/CollectionsListView.swift` | Add EXIF cache, `loadEXIF()`, extend `photoInfoRow` |
| 3 | `Rendering/ExportMetadata.swift` | **NEW** — `ExportMetadata` struct + `apply(to:format:)` |
| 4 | `Rendering/ExportRenderer.swift` | Add `sourceImageList()` helper |
| 5 | `Rendering/ExportWriter.swift` | Add `metadata` parameter, call `apply(to:format:)` |
| 6 | `Views/ExportSettingsView.swift` | Add embed toggle, build and pass metadata |
| 7 | `App/AppSettings.swift` | Add `embedExportMetadata` key |
| 8 | `ARCHITECTURE.md` | Document new utilities and export metadata design |
| 9 | `DESIGN.md` | Update if any model or file format fields change |

---

## Verification Checklist

- [ ] `swift build` — no errors or new warnings
- [ ] Select a photo with EXIF → info panel shows camera, aperture, ISO, shutter, focal, date
- [ ] Select a photo without EXIF → EXIF section hidden, no empty rows
- [ ] Switch between photos → cache reuses data, no redundant file reads
- [ ] Export JPEG with "Embed Metadata" ON → XMP/UserComment present (verify with `exiftool`)
- [ ] Export JPEG with toggle OFF → no custom metadata (DPI only)
- [ ] Export PNG with toggle ON → PNG text chunks present
- [ ] Toggle preference persists across app restarts
- [ ] Collection refresh clears EXIF cache
