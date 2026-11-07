# Unlit ring cutout

The user supplied `codex-clipboard-1b81c5c2-3af1-4547-b46c-971406bf9978.png`. The built-in `image_gen` tool edited that photograph with `transparent_background: true`. The original generated output is retained at `/Users/red/.codex/generated_images/01a15f9d-feb1-7bb2-9a41-17e215e850b8/exec-3218c943-8655-4c85-9048-3c76202dd974.png`.

The selected 1254 × 1254 RGBA cutout is saved identically at:

- `dashboard/web/ring-off.png` (Rust route `/ring-off.png`).
- `apps/ios/OuraApp/Assets.xcassets/RingOff.imageset/ring-off.png`.

Both exterior and central opening are transparent, visually checked on dark and light Settings surfaces. The three rounded sensor domes remain unlit. It is decorative product artwork, not a reading of hardware state. No remote image fetch or image service runs in the application.

## Exact final prompt (built-in edit mode)

Use case: background-extraction. Asset type: transparent PNG product cutout for the Settings screen of a health application. Input image 1 is the edit target. Remove only the black background outside the ring and through its central opening, producing real alpha transparency with clean antialiased edges and no black or white fringe. Preserve the photographed dark smart ring exactly: front view, flattened upper edge, circular proportions, fine metallic texture, and three rounded inner sensor domes along the bottom. Sensors must remain switched OFF: no red or green illumination, no glow, no added reflections. Keep the entire ring centered and fully visible with a small even transparent margin in a square canvas. No text, no shadow, no background, no new objects. Do not redesign or reshape the ring.

