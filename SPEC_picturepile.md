
# Software Specification: Picasa CXF (`theme="picturepile"`) Parser & Renderer

## 1. Overview

This specification details a software program designed to parse, interpret, and reconstruct Picasa Collage XML (`.cxf`) files strictly matching the `theme="picturepile"` layout mode.

The tool converts abstract XML parameters into concrete spatial coordinates to re-render, export, or convert legacy Picasa picture-pile collages.

---

## 2. Scope & Constraints

* **Supported Features:** CXF files containing `<collage theme="picturepile">`.
* **Ignored Features:** Non-picturepile modes (`grid`, `mosaic`, `contact_sheet`), text overlays (`<overlays>`), and interactive editing features.
* **Platform Considerations:** Handles cross-platform Wine drive paths (e.g., `[Z]\Users\...`) and maps them to native POSIX or Windows file paths.

---

## 3. Input Specification

### 3.1 Document Schema

The parser must accept valid XML matching the following hierarchy:

```xml
<collage format="[W]:[H]" orientation="[landscape|portrait]" theme="picturepile" shadows="[0|1]">
  <background type="solid" color="[AARRGGBB]"/>
  <node x="[float]" y="[float]" w="[float]" h="[float]" theta="[float]" scale="[float]">
    <theme>[string]</theme>
    <src>[path_string]</src>
    <uid>[hash_string]</uid>
  </node>
</collage>

```

### 3.2 Data Extraction & Parsing Rules

#### Canvas Attributes (`<collage>`)

* **`format`**: Ratio string for the two canvas edges. Picasa writes the **long edge first** in both orientations — a portrait A4 collage is written `"297:210"` — so the ordering of the two numbers must not be used to infer the canvas shape.
* **`orientation`**: `"portrait"` or `"landscape"`. This, and **not** `format`, is authoritative for which axis carries the long edge. Matched case-insensitively; when absent or unrecognised, the ordering of `format` is used as a fallback.
* **Canvas size**: The long edge maps to 2000 pt; `format="297:210"` + `orientation="portrait"` therefore yields **1414 × 2000**. Implemented in `Import/CXFCanvasGeometry.swift`.
* **`shadows`**: Boolean integer (`1` = draw drop shadow under nodes, `0` = disable).

#### Background Attributes (`<background>`)

* **`color`**: 8-character Hexadecimal string in **`AARRGGBB`** format (e.g., `FFFFFFFF` = solid white, `00000000` = fully transparent).

#### Node Attributes (`<node>`)

Order of `<node>` elements in XML dictates the **Z-Index** layer order (first node = bottom layer, last node = top layer).

* **`x`, `y**`: Normalized anchor — the top-left corner, before rotation, of the square that holds the photo (see §5.1) — relative to canvas dimensions $[0.0, 1.0]$. *Not* the centre.
* **`w`, `h**`: Normalized width and height bounds relative to canvas dimensions $[0.0, 1.0]$, in the photo's displayed orientation (after EXIF orientation and any `Picasa.ini` rotation).
* **`scale`**: The photo's long edge, in units where the canvas's long edge is 1024. Redundant with `max(w·W, h·H)`; not read by the importer.
* **`theta`**: Rotation angle in **radians** ($0.0$ to $2\pi$). $6.283185 \approx 0^\circ$ rotation.
* **`<src>`**: Path string containing source photo location. Must undergo path normalization.

---

## 4. Path Translation Module

The program must include a path translation engine to convert legacy Wine/Picasa file paths into native OS system paths:

```
                  ┌───────────────────────────────┐
                  │ Input: [Z]\Users\paul\Pic.jpg │
                  └──────────────┬────────────────┘
                                 │
                         Detect Drive Prefix
                                 │
                   ┌─────────────┴─────────────┐
                   ▼                           ▼
          Windows Environment          POSIX / macOS System
          Strip [Z]\                   Strip [Z]\
          Replace / with \             Replace \ with /
          Result: C:\Users\paul\...    Result: /Users/paul/...

```

### Path Mapping Matrix

* **`[Z]\` or `Z:\**`: Map directly to Unix root `/` on macOS/Linux.
* **`$My Documents`**: Map to user's native Documents directory (`~/Documents`).
* **`$My Pictures`**: Map to user's native Pictures directory (`~/Pictures`).

---

## 5. Geometric Transformation Engine

To place an image onto the canvas at target output dimensions $(W_{\text{canvas}}, H_{\text{canvas}})$, apply transformations in order:

### 5.1 Anchor (Top-Left) Calculation

Picasa models each photo as sitting in the centre of a **square whose side is the photo's long edge**, $L = \max(W_{\text{box}}, H_{\text{box}})$ (the node's `scale` attribute is the same $L$). `x`, `y` address that square's top-left corner before rotation, and the square is rotated clockwise by $\theta$ about that corner:

$$X_{\text{anchor}} = x \times W_{\text{canvas}}, \qquad Y_{\text{anchor}} = y \times H_{\text{canvas}}$$

$$X_{\text{center}} = X_{\text{anchor}} + \tfrac{L}{2}\cos\theta - \tfrac{L}{2}\sin\theta$$

$$Y_{\text{center}} = Y_{\text{anchor}} + \tfrac{L}{2}\sin\theta + \tfrac{L}{2}\cos\theta$$

(Canvas space has a top-left origin with y down, so this rotation is clockwise on screen.) At $\theta = 0$ a landscape photo therefore sits $\tfrac{1}{2}(W_{\text{box}} - H_{\text{box}})$ lower than its anchor suggests, and a portrait photo $\tfrac{1}{2}(H_{\text{box}} - W_{\text{box}})$ further right. Because the offset scales with the box it differs per node, which is what makes a Picasa panorama's horizon line up.

Implemented in `CXFCanvasGeometry.layerCenter`. Verified with `Scripts/cxf_compare.sh`, which composites the real source photos with the CXF geometry and compares against Picasa's own exports (mean content error, 0–255, over 22 collages with θ = 0, small tilts, 30°, 60°, 90° and 270°):

| Rule | Mean error | Notes |
| --- | --- | --- |
| $(L/2, L/2)$ — this rule | 20.5 | never worse than the alternatives on any file |
| $(W_{\text{box}}/2, W_{\text{box}}/2)$ — previous rule | 52.6 | identical for landscape photos; wrong by $\tfrac{1}{2}(H-W)$ along the rotated diagonal for portrait ones (e.g. `crane` 108.9 vs 2.7) |
| $(W_{\text{box}}/2, H_{\text{box}}/2)$ — plain rotation of the box | 58.9 | |

A per-photo offset search on top of this rule leaves residuals inside the 2.5 pt fit resolution (`sam-train-2`, `sam-train-3`). Most of the remaining error comes from `Picasa.ini` crops and tone filters, which are not imported (§5.4).

**Rotation sign.** Picasa's positive `theta` is clockwise on screen. Pearblossom's renderers apply `CGAffineTransform(rotationAngle:)` to a y-up `CIImage`, which turns positive angles counter-clockwise, so the layer's `rotation` is stored as $-\theta$. Only the photo's own rotation is negated. The centre above is computed in canvas space with Picasa's clockwise $\theta$. (Storing $+\theta$ turned `sam-train-2`'s 270° photos upside down.)

### 5.2 Size Calculation

$$Width = w \times W_{\text{canvas}}$$

$$Height = h \times H_{\text{canvas}}$$

### 5.3 Rotation & Bounding Box

Rotate the image clockwise about the derived center $(X_{\text{center}}, Y_{\text{center}})$, computed in §5.1, by angle $\theta$ (in radians). The layer stores it negated; see "Rotation sign" in §5.1.


$$\text{Angle in Degrees} = \theta \times \left(\frac{180}{\pi}\right)$$

```
(0,0) ┌──────────────────────────────────────────────┐
      │ Canvas                                       │
      │           (X_center, Y_center)               │
      │                  ┌───────┐                   │
      │                  │ Image │ ↻ theta (rad)     │
      │                  └───────┘                   │
      └──────────────────────────────────────────────┘ (W_canvas, H_canvas)

```

### 5.4 Source Edits in `Picasa.ini`

Picasa keeps non-destructive edits in a `Picasa.ini` (or `.picasa.ini`) file in each photo's folder, under a `[filename.jpg]` section (parsed by `Import/PicasaINI.swift`). Picasa lays a collage out using the edited photo, so the node's `w`/`h` describe the photo with whatever edits it had **at layout time**:

* **`rotate=rotate(n)`**: $n$ quarter turns clockwise, on top of any EXIF orientation.
* **`crop=rect64(hex)`**: a 64-bit hex value, with leading zeros dropped, packing four 16-bit fractions of 65535: left, top, right, bottom of the displayed image.
* **`filters=…`**: tone and colour filters (`autolight`, `finetune2`, …). Out of scope.

**Rotation is imported.** A photo turned $n$ quarter turns covers the same footprint as the stored photo in a box with $w$ and $h$ swapped (for odd $n$), rotated a further $n \cdot 90°$ about the same centre. So `CXFCanvasGeometry.layerPlacement` keeps the §5.1 centre, swaps the box, and adds the turns to $\theta$; no model change is needed, and `sourceResolution` (the stored photo) matches the swapped box.

**Edits can postdate the collage.** `Picasa.ini` holds a photo's *current* edits, and Picasa does not re-lay-out a saved collage when a photo is edited later. `sam-train-2`'s scans carry `rotate(3)`, but their boxes are portrait like the raw scans and Picasa's export shows them unrotated. `CXFCanvasGeometry.quarterTurnsInEffect` therefore compares the box's aspect with each combination (no edits, rotation only, crop only, both) and applies the rotation only when a rotated combination is closest. Ties go to applying the edits. Boxes match the laid-out photo to about 0.01%, which separates even `scan1` (raw scan 0.7270, rotated crop 0.7068, box 0.7271 → edits postdate). Even turns do not change the shape, so they cannot be tested and are always applied; no sample has them.

Measured with `Scripts/cxf_compare.sh` (mean content error): `iona-office` ×4 69 → 3.0, with no other file changing; mean over the 22 picturepile references 20.5 → 8.4.

**Crops are not imported.** The importer logs a warning and shows the whole photo, because the model's `cropRect` is not used by either renderer. `--picasa-crop` previews them in the harness: `sam-trains` 64.9 → 13.1. The crop-then-rotate order is assumed, because no sample has both edits in effect.

---

## 6. Rendering Pipeline

```
1. Initialize Canvas
   ├── Parse canvas format & target DPI (e.g., 300 DPI for A4 = 3508x2480px)
   └── Fill canvas with background color parsed from <background color>

2. Process Nodes Sequentially (Z-Order: Low to High)
   FOR EACH <node> IN <collage>:
     ├── Resolve <src> file path
     ├── Load source image from disk
     ├── Resize image to calculated (Width, Height)
     ├── IF <theme> == "whiteframe":
     │     Add white border padding + drop shadow
     ├── IF <collage shadows="1">:
     │     Render drop-shadow effect
     ├── Rotate image by theta radians
     └── Composite image onto canvas at (X_center, Y_center)

3. Output Render
   └── Export composite canvas to PNG/JPEG

```

---

## 7. Error Handling Requirements

| Error Condition | Program Action |
| --- | --- |
| `theme != "picturepile"` | **Abort:** Throw `UnsupportedThemeException` ("Only picturepile theme is supported"). |
| Missing Source Image (`<src>`) | **Warn & Continue:** Draw placeholder box with missing image path text. |
| Invalid XML syntax | **Abort:** Throw `XMLParsingException`. |
| Out-of-bounds coordinates ($x, y > 1.0$) | **Process:** Render node partially off-canvas as defined. |
