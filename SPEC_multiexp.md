# Software Specification: Picasa CXF (`theme="multiexp"`) Parser & Renderer

## 1. Overview

This specification details a software program designed to parse, interpret, and reconstruct Picasa Collage XML (`.cxf`) files matching the `theme="multiexp"` (Multiple Exposure) layout mode.

Unlike freeform or grid layouts, the **Multiple Exposure** theme stacks multiple source photos on top of one another at full or near-full canvas size, applying **alpha transparency blending** to create a single composite "double/multiple exposure" photo effect.

---

## 2. Scope & Constraints

* **Supported Features:** CXF files containing `<collage theme="multiexp">`.
* **Ignored Features:** Non-multiexp themes (`picturepile`, `grid`, `mosaic`), text overlays, and interactive editing features.
* **Blending Model:** Standard alpha opacity blending, composited over a solid black base. The `<background>` color is ignored for multiexp (Picasa always composites multiple exposures on black).

---

## 3. Input Specification

### 3.1 Document Schema

The parser must accept valid XML matching the following hierarchy:

```xml
<collage format="[W]:[H]" orientation="[landscape|portrait]" theme="multiexp">
  <background type="solid" color="[AARRGGBB]"/>
  <spacing value="[float]"/>
  <node x="[float]" y="[float]" w="[float]" h="[float]" theta="[float]" scale="[float]" alpha="[float]">
    <theme>noborder</theme>
    <src>[path_string]</src>
    <uid>[hash_string]</uid>
  </node>
</collage>

```

### 3.2 Data Extraction & Parsing Rules

#### Canvas Attributes (`<collage>`)

* **`format`**: Parsed as a ratio string `W:H` (e.g., `"297:210"` or `"4:3"`).
* **`orientation`**: `"landscape"` or `"portrait"`.
* **`theme`**: Must strictly equal `"multiexp"`.

#### Node Attributes (`<node>`)

Order of `<node>` elements in XML dictates the **layer stacking order** from bottom (first node) to top (last node).

* **`alpha`**: Float value $[0.0, 1.0]$ representing opacity. If omitted, default to $\frac{1.0}{N}$ (where $N$ is the total count of `<node>` elements).
* **`x`, `y**`: Normalized center position relative to canvas $[0.0, 1.0]$. In default `multiexp`, this is centered near `(0.5, 0.5)`.
* **`w`, `h**`: Normalized scale bounds $[0.0, 1.0]$ relative to canvas dimensions. Photos are scaled uniformly to fill this rect, preserving aspect ratio; overflow is cropped (no stretching).
* **`theta`**: Rotation angle in **radians** ($0.0$ to $2\pi$).
* **`<src>`**: Path string pointing to source image file (requires path translation).

---

## 4. Blending & Composition Engine

The program must combine images using **Alpha Compositing** over the background.

```
(0,0) ┌──────────────────────────────────────────────┐
      │ Canvas Background (Black)                     │
      │                                              │
      │    ┌────────────────────────────────────┐    │
      │    │ Image 1 (Layer 0, Alpha: 0.50)      │    │
      │    │ ┌──────────────────────────────────┼──┐ │
      │    │ │ Image 2 (Layer 1, Alpha: 0.50)    │ │
      │    └─┼──────────────────────────────────┘ │ │
      │      └────────────────────────────────────┘ │
      └─────────────────────────────────────────────┘ (W_canvas, H_canvas)

```

### 4.1 Global Blending Formula

For each pixel at canvas location $(x, y)$, calculate the output color $C_{\text{out}}$ by iterating through the background and sequentially applying each image node layer using the **Over Operator**:

$$C_{\text{out}} = C_{\text{src}} \cdot \alpha_{\text{src}} + C_{\text{dst}} \cdot (1 - \alpha_{\text{src}})$$

Where:

* $C_{\text{src}}$ and $\alpha_{\text{src}}$ are the RGB color and opacity of the current image node.
* $C_{\text{dst}}$ is the accumulated RGB color of the canvas layers beneath it.

---

## 5. Rendering Pipeline

```
1. Initialize Canvas
   ├── Parse canvas aspect ratio and set target pixel dimensions (W_canvas, H_canvas)
   └── Fill canvas buffer with black (the <background> color is ignored for multiexp)

2. Read & Pre-process Nodes
   ├── Count total node elements N
   └── FOR EACH <node> IN <collage>:
         ├── Resolve <src> path using Path Translation Engine
         ├── Load source image from disk
         ├── IF node HAS attribute "alpha":
         │     Set layer_alpha = float(node.alpha)
         │   ELSE:
         │     Set layer_alpha = 1.0 / N  (Default equal exposure)
         └── Store node with computed layer_alpha

3. Composite Layers (Bottom-to-Top Order)
   FOR EACH processed node:
     ├── Scale image uniformly to fill the node rect (w * W_canvas × h * H_canvas),
     │   preserving aspect ratio; crop overflow centered (no stretching)
     ├── Apply rotation by theta radians around image center
     ├── Set image global alpha channel to layer_alpha
     └── Composite onto canvas at position (x * W_canvas, y * H_canvas) using Alpha Blend

4. Output Render
   └── Export final blended composite to PNG or JPEG

```

---

## 6. Error Handling Requirements

| Error Condition | Program Action |
| --- | --- |
| `theme != "multiexp"` | **Abort:** Throw `UnsupportedThemeException` ("Only multiexp theme is supported"). |
| Missing `alpha` attribute | **Fallback:** Dynamically calculate opacity as $\frac{1.0}{\text{number of nodes}}$. |
| Missing Source Image (`<src>`) | **Warn & Continue:** Skip missing node or render faint placeholder bound box to preserve overall exposure weight. |