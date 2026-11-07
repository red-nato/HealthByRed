# Cinematic Home and section identities

Home has a red identity built around the user's red-sensor ring photograph. The
ring sits to one side of the actual sleep score; a static fine trace leads from
the sensor area toward time-in-bed and steps. The native progress indicator and
Sleep/Activity actions use the same red. There are no fabricated measurements,
new readiness algorithms, live-light animations or continuous blur effects.

The image's opening and exterior are transparent. Home uses a full-width,
symmetric tile. The ring has its own responsive column above the statistics,
and the date sits on the left below “Your rhythm”. The previous one-sided 40pt
gutter and absolute image overlay were removed after device feedback. The green
photo stays in Ring and an unlit photo appears in Settings. All three
PNG variants are bundled with the native app and embedded in the Rust server.
The direct Swift build paths copy all three image fallbacks as well.
See [cutout provenance and final prompts](ring-product.md).

## Identity

| Section | Dark accent | Light accent | Treatment |
| --- | --- | --- | --- |
| Home | `#ef5c63` | `#bc303e` | Black, ember-red surfaces, side-framed red ring |
| Ring | `#63ca78` | `#237344` | Deeper sensor green, original green product image |
| Settings | `#d9b49c` | `#916852` | A continuous red/copper/green blend on icons and ambient light; unlit ring |

The Health wordmark is larger; “by Red.” is smaller, with a red period. A ring
glyph sits at its left. Three circular sensor caps replace the previous narrow
radial peaks. Native UIKit draws and caches that template once; web uses matching
circle geometry in SVG.

Native navigation remains `TabView`; home measurements remain native list rows,
with full trends on tap. Settings and Ring remain native forms. Light/dark/system
preferences and accessibility layout behavior are retained.

## Connected ring motion

A shared product layer moves between the three placements in about 0.7 seconds.
Home starts at −12°; Ring centers at 0°; Settings rests at +8°. A small turn on
the vertical axis accompanies the position/size change, while the red, green and
unlit photographs crossfade. These are product illustrations, not live sensor
status or a three-dimensional model. Navigation controls and health calculations
are unchanged.

Native SwiftUI publishes untransformed bounds anchors and resolves them with
`GeometryProxy[anchor]` inside the same overlay that draws the flight. This avoids
adding the NavigationStack/TabView safe-area offset a second time. The overlay
fills that exact coordinate space with top-leading alignment. Incoming layout
briefly settles before travel starts; the animation lifetime begins afterward.
The interpolation returns the exact source/destination rectangles at its endpoints,
so handing the image back to its row requires no position correction. There are
no UIScreen dimensions, pixel-scale multipliers or device-specific offsets.

Only the active tab supplies a destination; a short timeout restores the static
image if layout never arrives. Web measures matching unrotated wrapper elements
in viewport pixels, including ancestor scaling, and uses the Web Animations API
on one composited overlay. Neither client runs an idle animation loop. Reduce Motion
skips travel. Rapid navigation cancels the previous trip; backgrounding and size
changes clean up the overlay. Scrolling the destination also cancels travel so it
cannot drift under the moving image. Offscreen sources switch directly.

## English interface

Home, Ring, Settings, modules, permissions, connection controls, errors, profile
dialogs, history and newly introduced accessibility labels use English. Web date
labels and emitted route fragments use English; older Spanish fragments remain
accepted as compatibility aliases. iOS declares English as its development
language and uses an English locale for its UI and added date/number formatting.
User-authored imported metadata and underlying ring records are not translated.

## Verification

- The actual Xcode app and test bundle build successfully for generic iPhone
  devices with signing disabled for verification; the user's signing setup is
  preserved. The new image set is included by the existing asset catalog.
- The 24 module/refresh/progress/motion/geometry logic tests pass in the temporary macOS harness
  using current production sources. The eight motion/geometry tests cover delayed layout, cancellation, rapid changes, Reduce Motion, missing destinations, viewport changes and exact endpoints across phone/tablet widths. These tests do not measure native UI FPS.
- The model-free Rust CLI builds, JavaScript syntax checks pass, PNG copies match,
  and source whitespace/plist checks pass.
- Ten web motion lifecycle/geometry tests pass (`node --test dashboard/tests/ring-continuity.test.cjs`), including interrupted navigation and restored visibility.
- Web checks cover English labels, the real score, the red PNG on light/dark
  backgrounds, navigation, theme switching, report access and history.
- Mobile references are the production web client in a 390px iframe on a temporary
  local QA server, with synthetic records kept outside the repository. They are
  not native iOS screenshots. No iOS simulator runtime is installed here.

Saved references:

- [Home, dark](../screenshots/cinematic-home-mobile-dark.png)
- [Home, light](../screenshots/cinematic-home-mobile-light.png)
- [Ring](../screenshots/cinematic-ring-mobile-dark.png)
- [Settings](../screenshots/cinematic-settings-mobile-dark.png)
- [Desktop Home](../screenshots/cinematic-home-desktop-dark.png)
- [Actual local server, empty Home](../screenshots/cinematic-home-empty-dark.png)

Current connected-ring references (production web with synthetic records):

- [Home, dark](../screenshots/connected-home-mobile-dark.png)
- [Home, light](../screenshots/connected-home-mobile-light.png)
- [Settings, dark](../screenshots/connected-settings-mobile-dark.png)
- [Settings, light](../screenshots/connected-settings-mobile-light.png)

## Adaptive layout correction

Current web references use synthetic records and the production web source:

- [320pt, dark](../screenshots/adaptive-home-320-dark.png)
- [390pt, dark](../screenshots/adaptive-home-390-dark.png)
- [428pt, dark](../screenshots/adaptive-home-428-dark.png)
- [390pt, light](../screenshots/adaptive-home-390-light.png)

Native code and its test bundle compile for generic iPhone. Native visual
verification still requires an iPhone or an installed iOS simulator runtime;
the browser references are not iOS captures.
