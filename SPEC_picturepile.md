
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

* **`x`, `y**`: Normalized center position relative to canvas dimensions $[0.0, 1.0]$.
* **`w`, `h**`: Normalized width and height bounds relative to canvas dimensions $[0.0, 1.0]$.
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

`x` addresses the node's **left edge** and `y` its **top edge before rotation** — *not* its center. (Verified against observed Picasa output: reading them as centers would place nodes more than half off-canvas, and x matches Picasa's own export to <0.5% while the recomputed content bounding box matches the photo aspect exactly.)

$$X_{\text{anchor}} = x \times W_{\text{canvas}}$$

$$Y_{\text{anchor}} = y \times H_{\text{canvas}}$$

and then the centre offset below.

The rendered center is the anchor plus the box's half-extents rotated clockwise by $\theta$ — but Picasa uses the half-**width** for **both** axes (a half-extent mix-up in its own layout code, the same class of bug this importer once had, with halfW instead of halfH):

$$X_{\text{center}} = x \times W_{\text{canvas}} + \tfrac{W_{\text{box}}}{2}\cos\theta - \tfrac{W_{\text{box}}}{2}\sin\theta$$

$$Y_{\text{center}} = y \times H_{\text{canvas}} + \tfrac{W_{\text{box}}}{2}\sin\theta + \tfrac{W_{\text{box}}}{2}\cos\theta$$

At $\theta = 0$ this places the box $\tfrac{1}{2}(W_{\text{box}} - H_{\text{box}})$ lower than the stored $y$ implies. Because the offset scales with the box, it differs per node — which is what makes a Picasa panorama's horizon line up and an unadjusted render's not. Derived empirically by compositing the real source photos with the CXF geometry and comparing against Picasa's own exports; see the table in `PLANS.md`. There is **no horizontal counterpart** — offsetting x as well, or x alone, measurably worsens every sample.

Both terms must use the same sign convention: Picasa's positive `theta` is clockwise, which matches Pearblossom's renderer, so `rotation` is stored as $+\theta$ — the same sign as the offsets above. Negating the rotation while keeping the clockwise offsets tilts each photo the wrong way (up to $2\theta$ apart from Picasa).

### 5.2 Size Calculation

$$Width = w \times W_{\text{canvas}}$$

$$Height = h \times H_{\text{canvas}}$$

### 5.3 Rotation & Bounding Box

Rotate the image about the derived center $(X_{\text{center}}, Y_{\text{center}})$, computed in §5.1, by angle $\theta$ (in radians):


$$\text{Angle in Degrees} = \theta \times \left(\frac{180}{\pi}\right)$$

```
(0,0) ┌──────────────────────────────────────────────┐
      │ Canvas                                       │
      │           (X_center, Y_center)               │
      │                  ┌───────┐                   │
      │                  │ Image │ ↺ theta (rad)     │
      │                  └───────┘                   │
      └──────────────────────────────────────────────┘ (W_canvas, H_canvas)

```

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
