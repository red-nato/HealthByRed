# App screenshots

`overview.png`, `sleep.png`, and `activity.png` were captured on September 16,
2026 from the production SwiftUI app on the iPhone 17 Pro simulator (iOS 26.5,
dark appearance), running against the author's own Ring 5 data as synced to
the local store (last sync July 17, 2026). No ring identifiers or keys are
shown. Images are unretouched simulator screenshots, opened with the
`-openDay` launch argument.

## Pairing and symptom radar — September 8, 2026

`pairing-dark.png`, `pairing-sync-dark.png`, and `pairing-help-light.png` show
setup, active sync, and ring-discovery guidance. `symptom-radar-light.png` and
`symptom-radar-dark.png` show the simplified radar with synthetic minor-signs
biometrics. Captured on the same iPhone 17 Pro / iOS 26.5 simulator.

A separate temporary preview app presents the production SwiftUI views with
controlled state; the shipped entry point is unchanged. No real keys or health
data are included. Screenshots are unretouched. The views were also checked at
an accessibility text size, and UI automation exercised key validation and
visibility, diagnostics, reset cancellation, pause, failure guidance, and the
personal-range toggle.

## Compact radar and day refresh, September 9, 2026

- [Collapsed radar](symptom-radar-collapsed-dark.png)
- [Expanded measurements and personal ranges](symptom-radar-expanded-dark.png)
- [Support panel](support-panel-dark.png)
- [Historical activity refresh](day-analysis-refresh-dark.png)

These unretouched iPhone 17 Pro simulator captures use synthetic data and the
production SwiftUI views in a temporary preview app. UI checks cover disclosure,
missing data, accessibility text size, support actions, reset cancellation, and
refreshing both tabs through the historical-day browser. Refresh callbacks in the
preview simulate success and failure to verify live updates and retained results.
The app's native test suite separately runs the actual activity model to verify
that refreshing an older day bypasses its cache and preserves other days.

## Health redesign — October 21, 2026

- [Desktop light](redesign-web-light.png)
- [Desktop dark](redesign-web-dark.png)
- [Mobile dark, 390 px](redesign-web-mobile-dark.png)

Browser captures of the redesigned production web source with an intercepted empty
summary. There are no invented health measurements in these captures or bundled
demo data in the app. The ring is an explicitly labelled vector illustration.
These are web previews, not native iOS simulator captures. The native model-free
source compiled and linked; no simulator runtime was available for visual testing.

## Compact mobile redesign — October 21, 2026 (v2)

- [Inicio, dark](redesign-v2-home-dark.png) and [light](redesign-v2-home-light.png).
- [Anillo](redesign-v2-ring-dark.png), [Ajustes](redesign-v2-settings-dark.png),
  [empty state](redesign-v2-empty-dark.png), [desktop](redesign-v2-desktop-dark.png).
- [Real local-server ring screen](redesign-v2-live-ring.png), using an empty
  throwaway database and no personal health records.

Mobile captures are 390 × 844 CSS pixels at 2× density. Populated home/desktop
captures use synthetic measurements confined to the temporary QA harness; they
are not bundled product demo data. Empty-state and ring captures contain no health
measurements. Navigation, module choice/import, profile access, persistent themes,
report/export/back and 320–1440px widths were exercised. The bottom bar remains
accessible and appearance lives in Ajustes. Native source compiled and linked for
the iOS simulator target; no simulator runtime or physical-ring UI session was
available. The PNG and its [generation prompt](../design/ring-product.md) are saved
in the project and included by both build paths.

## Near-black theme and supplied ring — October 21, 2026

- [Dark ring screen](near-black-ring-dark.png).
- [Light ring screen](near-black-ring-light.png).

These are current web-client captures from the local Rust server with a
disposable empty database. They show the new black ring cutout and near-black
green theme; they are not iPhone performance measurements or native screenshots.
The generic-iOS app and test bundle build successfully. The module/freshness/
progress logic passes 16 tests in a temporary macOS harness. See the
[performance notes](../ios-performance-2026-10-21.md) for scope and limits.

## Native component migration — October 21, 2026

[Web reference](native-components-web-reference-dark.png) shows the shared black
canvas, sensor-green accent, red brand period and reduced home structure. It uses
synthetic measurements from a temporary QA server and is **not** a native iOS
capture. iOS now uses system TabView/List/Form/Gauge components; its app and test
bundle compile for iPhone, but no simulator runtime is installed for screenshots.
See [migration notes](../design/native-components.md).

[Updated ring screen](native-components-web-ring-dark.png) is the actual local
Rust preview with an empty disposable database. It confirms the new ring glyph,
compact web bar, pure-black background and corrected brand, without health data.

## Cinematic section identities — October 21, 2026

- [Home, red/dark](cinematic-home-mobile-dark.png)
- [Home, light](cinematic-home-mobile-light.png)
- [Ring, deeper green](cinematic-ring-mobile-dark.png)
- [Settings, red/green/copper](cinematic-settings-mobile-dark.png)

These show the production web client in a 390px mobile iframe, using synthetic
data from a temporary local QA server. They are not native iOS screenshots.
The iPhone app and test bundle compile with the same assets, section palettes
and English copy. See [design and validation](../design/cinematic-home.md).

The [desktop reference](cinematic-home-desktop-dark.png) uses the same synthetic
QA records. The [actual local-server empty state](cinematic-home-empty-dark.png)
uses a disposable empty database and contains no health measurements.


## Connected ring — October 21, 2026

- [Home with protruding ring, dark](connected-home-mobile-dark.png)
- [Home with protruding ring, light](connected-home-mobile-light.png)
- [Settings with the unlit ring, dark](connected-settings-mobile-dark.png)
- [Settings with the unlit ring, light](connected-settings-mobile-light.png)

Unretouched browser captures at a 390px content width, with synthetic measurements.
These are web references, not native iPhone captures. Both clients implement the
same three-state motion, and the native iPhone app/test bundle build successfully.
The native motion controller's lifecycle tests run in a temporary macOS harness;
there is no installed iOS simulator runtime for native visual/FPS verification.

[Local Settings](connected-settings-local-dark.png) is the actual Rust preview on
port 8766 with a disposable empty database. [Empty Home](connected-home-empty-dark.png)
shows its no-records state and the local-history error disclosure from that
uninitialized QA database. Neither contains personal health records.


## Adaptive tile and transition correction — October 21, 2026

- [Small phone, 320pt](adaptive-home-320-dark.png)
- [Phone, 390pt](adaptive-home-390-dark.png)
- [Large phone, 428pt](adaptive-home-428-dark.png)
- [Light appearance, 390pt](adaptive-home-390-light.png)

These browser captures use synthetic measurements. The full-width tile has equal
side margins, its date is on the left, and the ring cannot cover Time in bed or
Steps. Native iOS uses the same layout with real SwiftUI bounds anchors resolved
inside its animation overlay. Its app/test bundle compiles; 24 Swift logic tests
and 10 web lifecycle/geometry tests pass. These are not native iOS screenshots.
