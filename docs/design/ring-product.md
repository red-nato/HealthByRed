# Ring photograph and cutout

The current black ring with green sensors replaces the previous silver render.
It comes from the user's supplied `codex-clipboard-3c146dc2-e364-4970-9f42-d68be79840b2.png`.
On October 21, 2026, the built-in `image_gen` tool was used in **edit mode** to
clean the white cutout fringe, requesting a transparent background and preserving
the product's geometry, finish and illuminated sensors. This is an AI-edited
product illustration, not a device identification or live SpO₂ reading.

Project assets (identical transparent PNGs, 1254 × 1254):

- `dashboard/web/ring-product.png` — embedded by the Rust server at `/ring-product.png`.
- `apps/ios/OuraApp/Assets.xcassets/RingProduct.imageset/ring-product.png` — native asset.

The direct Swift build scripts also copy the PNG into the bundle for the
`UIImage(contentsOfFile:)` fallback. Every placement preserves the aspect ratio.
The opening and background have alpha transparency, so the image works in both
themes. No network image requests are needed at runtime.

## Final edit prompt

Use case: background-extraction. Edit target: the supplied black smart ring image with illuminated green internal sensors. This is an edge cleanup and alpha-matte repair ONLY. Preserve the exact same ring, original front-on circular geometry with subtle flat top, perspective, dark metal finish, detailed electronics, sensor placement and natural green illumination. Do not redesign, repaint or reimagine the product. Remove the ragged white/light gray cutout fringe along BOTH the outer edge and the inner hole. Reconstruct a clean, naturally antialiased edge without eroding the ring or losing the bright metal highlight. The whole background outside the ring AND the entire opening through its center must be truly transparent (alpha), with no black/white backdrop or fake checkerboard. Preserve existing transparency. Keep the single ring centered and completely visible, with a modest transparent margin around it. No text, labels, extra objects or added reflections; no extra light bloom outside the product. Output a high quality transparent PNG suitable for a native health app in both near-black and light themes.


## Red sensor variant for Home

The user subsequently supplied
`codex-clipboard-94f6c3d4-bb8b-47e8-82c5-1be8a2b99cfe.png` for the Home identity.
The built-in `image_gen` tool was used in **edit mode**, with
`transparent_background: true`, to extract and clean that product photograph.
The green variant remains in Ring. This red image is illustrative, not a live
sensor measurement. Both versions are bundled locally with no remote image fetch.

The edited red asset is an RGBA PNG, 1254 × 1254, with a transparent opening and
outside background. Its alpha is visually verified against both the dark and
light Home surfaces. Identical copies are saved at:

- `dashboard/web/ring-red.png`, served by Rust at `/ring-red.png`.
- `apps/ios/OuraApp/Assets.xcassets/RingRed.imageset/ring-red.png`.

### Final red cutout prompt

Use case: background-extraction. EDIT TARGET: the supplied photograph of a black smart ring, front-on, with a bright red sensor at bottom center. Create a clean transparent PNG cutout of this exact product photograph. Preserve the ring's original shape, circular opening, subtle flattened top, dark titanium finish, visible internal components, all three rounded inner sensor domes, camera angle, and red illumination. Remove only the black backdrop outside the product AND through the entire central hole. Repair ragged cutout edges with naturally antialiased alpha; no white, gray or black fringe. Preserve the genuine red reflections on the inner band and the bright bottom sensor. Do not repaint or redesign the product. No extra lights, green LEDs, typography, logos, hands, floor, props or fake checkerboard. The central opening must be truly transparent. No broad baked-in red haze in the central opening or outside the ring; the app will supply its own subtle cinematic glow. Keep the full ring visible, centered, with a modest transparent margin. Output high-quality square RGBA PNG for use at 180–300px in a health app on dark and light backgrounds.


## Unlit Settings variant

The third locally bundled photo completes the shared ring transition. See
[unlit cutout provenance, paths and exact final prompt](ring-off-cutout.md).
