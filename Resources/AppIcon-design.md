# BrightnessFollow 应用图标

## 当前版本：原生明暗外观（0.3.5 / 构建 8）

- 2026-09-10：保留已选定的金色太阳与双屏造型，接入 Icon Composer。
- 唯一设计源：`AppIcon.icon/icon.json` 和 `AppIcon.icon/Assets/GoldForeground.png`。
- 默认底色为 `system-light`，深色为 `system-dark`；不使用紫色、青色等新配色。
- 透明前景由内置 imagegen 的编辑模式提取；无 API/CLI 图像生成回退。
- 采用的生成结果为 `exec-4653a5ec-8b6c-45c6-bdd8-2181c227163c.png`，已随原生文档保存。
- 图层以原生 `position.scale = 0.91` 配置。1254 像素输入在 1024 点原生画布中
  的有效占比约为 84%，相对 0.3.4 的约 75% 放大约 12%。不是放大外围底板。
- 禁用前景玻璃、组透明与投影；由系统处理外围圆角、底板和明暗外观。
- `AppIcon.png` / `AppIcon-dark.png` 是 `ictool` 的 1024 像素原生渲染预览。
- `actool` 编译 `Assets.car` 和 ICNS 回退；应用同时声明 `CFBundleIconName` 与
  `CFBundleIconFile`，最低系统版本仍为 macOS 13。原生明暗外观取决于系统支持。
- 0.3.4 资源备份在 `old-builds/icon-before-native-20260910/`，不纳入 Git。

### 采用的透明图层提取提示词

```text
Use case: background-extraction.
Asset type: transparent foreground layer for the existing BrightnessFollow macOS app icon.
Input image 1 is the exact edit target, not inspiration. The user has approved this gold sun and two-monitor symbol. This task is only to separate the symbol from its white backdrop for native light/dark icon composition.
Remove ALL white background pixels, including the white interiors of both monitor frames and the gaps between rays, and replace them with genuine transparent alpha.
Preserve the original golden-yellow and amber colors, the diagonally two-tone sun disk, all eight rounded rays, both open monitor outlines and stands, their exact sizes, positions, stroke widths, rounded corners, the separate downward ray, left-higher/right-lower arrangement and all negative space. Keep every part of the symbol in the same location on the same square canvas; do not crop, enlarge, redesign, simplify or recolor.
Target dimensions: 1024 x 1024, matching the input. Return a clean RGBA PNG, genuinely transparent everywhere outside the gold symbol, with crisp antialiased edges and no white fringe.
No opaque background, no checkerboard drawn into the image, no black or gray backing, no outer icon tile, no border, no shadow, no text, no new elements, no watermark. This is a precise transparent cutout of the existing artwork, not a new design.
```

以下保留 0.3.4 及更早的设计记录，不代表当前构建流程。

## 0.3.4 静态金色图标历史

- 生成方式：复用此前由内置 imagegen 生成、已获认可的金黄色原图；本次仅做尺寸转换与 ICNS 打包，没有重新生成造型或使用 API/CLI 回退。
- 最终设计：白底，金黄色太阳与双显示器；太阳沿对角线分为明亮金黄与较深琥珀色，两台显示器保持轻微高低错位，表达多屏亮度跟随。
- 用户确认：2026-09-09。比较配色预览后选择回到金黄色版本，并明确要求替换应用图标。
- 主图：`AppIcon.png`（1024 × 1024，满幅不透明背景）。
- 打包资源：`AppIcon.icns`，由 `Scripts/build-icon.sh` 生成。
- 后处理仅为尺寸转换与 ICNS 打包。主图不预留透明边距、不预裁圆角，避免被系统重复缩小。
- 几何处理：太阳下方光芒独立于显示器边框，保留朝向太阳的开口和清晰留白。
- 旧紫橙双圆主图与 ICNS 已备份至 `old-builds/icon-before-gold-20260909/`（不纳入 Git）。

## 金黄色双屏太阳正式版

复用已确认的 `Clear Sun and Twin Displays` 精修图，原始尺寸为 1254 × 1254。
主图等比例缩放为 1024 × 1024；不裁切、不重新着色、不增加边框、阴影或透明外边距。
使用现有 `Scripts/build-icon.sh` 生成 16、32、64、128、256、512 与 1024 像素表示。
应用版本为 0.3.4（构建 7）；Bundle ID、安装路径和稳定本地签名身份保持不变。

原始设计约束：两台圆角显示器和一枚太阳；左屏略高于右屏；太阳保留金黄与琥珀色的对角分区；
光芒和边框不交叉；背景为铺满画布的不透明白色，由 macOS 应用图标蒙版负责外部圆角。

以下保留此前版本的提示词作为设计历史，不代表当前采用的图标。

## 极简版初稿提示词

```text
Use case: logo-brand
Asset type: finished minimalist macOS app icon for BrightnessFollow (a brightness synchronization utility).
Primary request: A radically simple icon: ONE warm golden sun symbol centered on ONE solid deep blue rounded-square tile. Exactly two flat colors. The sun is a solid circular disk with eight short, thick, evenly spaced rounded rays. Strong symmetry and generous breathing room. A single instantly recognizable shape, crisp and legible at 16 and 32 pixels.
Style: flat vector-like geometry, contemporary minimal macOS utility icon. No 3D, no glass, no bevels, no highlights, no texture, no gradients, no shadows, no glow, no outlines, no display screens, no computers, no arrows, no extra elements.
Composition: single square 1024 x 1024 artwork. The rounded-square tile occupies 82 percent of the canvas width and height, perfectly centered, with consistent transparent padding on all sides. The sun spans about 50 percent of the tile. The tile has generous smooth macOS-style rounded corners.
Color palette: flat deep ink blue tile and flat warm golden yellow sun, high contrast.
Constraints: genuine transparent alpha outside the rounded square; clean antialiased edges with no scattered pixels. Never draw a checkerboard, backdrop, mockup, caption, text or watermark. Deliver one icon only.
```


## 旧太阳版尺寸修正提示词

```text
Use case: precise-object-edit
Edit target: the supplied simple blue-and-yellow sun app icon.
Fix ONLY the canvas/background sizing for a macOS app icon. Preserve the same yellow sun shape, its eight rounded rays, its centered position and its current size relative to the overall canvas. Preserve the blue and yellow colors and the simple flat style.
Replace the transparent outer padding and rounded-square tile boundary with continuous opaque blue background extending to ALL FOUR EDGES and ALL FOUR CORNERS of the square canvas. The result is a FULL-BLEED OPAQUE SQUARE, not a pre-rounded icon. The operating system will apply the rounded-corner mask itself.
Exact goal: every background pixel, including corners, is blue; zero transparent padding; zero black backing, zero inset smaller rounded-square tile; no border, no extra shadow, no text, no bevel, no decorations. Keep the sun unchanged. Deliver one square PNG image.
```

## 双圆造型提示词

```text
Use case: logo-brand
Asset type: a single preview concept for the macOS app BrightnessFollow, a utility that makes one display follow another display's brightness.
Primary request: An extremely simple, elegant icon using a warm off-white background and two circular forms of contrasting brightness. Express the relationship between a source and its follower with a compact, slightly diagonal composition.
Subject: one larger solid graphite-gray circle paired with one smaller pale warm-gray circle. The smaller light circle sits slightly above and to the right, partially overlapping the dark circle, with a crisp narrow off-white separation at the overlap so both circles remain distinct. The unequal sizes and diagonal arrangement should create a subtle sense of echo and following. The light circle needs enough tonal contrast to remain visible on the background.
Style: flat, precise vector-like geometry; calm, restrained, sophisticated macOS utility branding. Bold simple silhouette and balanced negative space. Clear at 32 pixels. Only off-white, graphite, and warm gray. No gradients, texture, dimensional rendering, highlights, glass, shadows, outlines around the entire icon, decorative elements, text, letters, or watermarks.
Composition: one centered icon design on a square 1024 x 1024 canvas. The combined circle symbol occupies about 58% of the canvas width. The off-white background fills the entire canvas edge to edge, including all four corners, with no transparent padding and no inset smaller tile. The operating system will apply the app-icon corner mask.
Avoid: sun rays, stars, yellow-on-blue colors, display illustrations, arrows, a grid of alternatives, device mockups, and two equal circles arranged horizontally. Deliver one clean finished preview.
```

## 紫橙双圆配色修订提示词（0.3.3 曾采用）

```text
Use case: precise-object-edit
Asset type: one color-refined preview of the BrightnessFollow macOS app icon.
Input image 1 is the edit target. The user has approved the two-circle symbol and asks only for a more lively, colorful palette.

Primary request: Recolor the existing design, preserving its geometry exactly.
- Replace the large graphite lower-left circular form with rich saturated deep violet, approximately #5B32D6.
- Replace the smaller pale-gray upper-right circle with bright warm coral orange, approximately #FF754F.
- Keep the very light warm off-white background and the narrow off-white curved separation between the circles.

Strict invariants: retain the exact two-circle sizes, placement, proportions, circular edges, diagonal arrangement, overlap cutout, gap width, scale, framing, and negative space from the input. Do not redesign the symbol. Maintain the dark-versus-light brightness relationship.
Style: extremely simple flat vector-like fills, crisp edges, lively but tasteful color contrast. No gradients, texture, shadows, glass, embossing, outlines, new objects, text, lettering, rays, stars, or watermarks.
Target dimensions: square 1254 x 1254, matching the supplied reference. The opaque warm off-white background must fill the whole square edge to edge including every corner. No rounded outer tile, inset tile, mockup, transparent padding, or border.
Deliver exactly one finished icon preview, not a grid or a comparison board.
```

0.3.3 的双圆图曾等比例缩放为 1024 × 1024 并打包。0.3.4 已替换为上文记录的金黄色双屏太阳图标。
