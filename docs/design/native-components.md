# Native component migration — October 21, 2026

The previous manually drawn bottom bar combined per-button height, multiple
padding layers, a glass modifier, an extra rim and a shadow. The daily overview
was also repeated below the vital cards. This revision replaces those structures
with system components and simplifies the information shown on Home.

## iOS

- `TabView` owns tab layout, selected states, safe areas and platform glass.
  On iOS 26+, `tabBarMinimizeBehavior(.onScrollDown)` makes room while scrolling.
  There are no private API overrides or forced tab-bar heights.
- Inicio is a native grouped `List` with `Section` and a system navigation toolbar.
  The single overview uses `Gauge` and links to the existing sleep/activity reports.
  Metrics use compact native rows; missing measurements do not create empty cards.
  Their full trend views remain accessible by tapping a row. The summary adapts
  vertically at accessibility text sizes.
- Ajustes and Anillo use `Form`, `Picker`, `Toggle`, `LabeledContent` and standard
  buttons/disclosures. The existing profile, modules and connection sheets remain.
- A cached UIKit template image draws a circular ring with three inward sensor
  domes. The same geometry is used in the web SVG. The supplied product PNG stays
  in the Ring screen and onboarding.
- The root retains the BLE controller through an owner that does not forward
  progress publications. Only busy-state transitions invalidate Root; connection
  controls observe their own progress. This avoids repeatedly rebuilding the
  complete dashboard for BLE status messages.

The dark canvas is `#000000`, row background `#0c0e0c`, and accent `#84ed65`.
Light mode uses the darker green `#24752c` for contrast. Branding is
**Health by Red.**, with a red final period. System type replaces rounded display
type. No third-party UI dependencies were added.

## Web parity

The web client receives the same colors, branding, glyph and single-overview
structure. A compact 54px bar retains 44px touch targets. Overview buttons open the
existing full reports; the calendar opens history. Trend cards remain on web,
whereas native iOS uses list rows and its existing full trend sheets.

## Verification

- The actual local Xcode app and test bundle compile for generic iOS devices,
  with signing disabled for this verification and the user's signing settings
  preserved. No new Swift source files need target membership.
- All 16 existing module/refresh/progress logic tests pass in the temporary macOS
  harness. These do not exercise native UI rendering.
- The model-free Rust CLI builds. JavaScript syntax and repository whitespace
  checks pass.
- Browser checks on the production web source confirm sleep/activity reports,
  history, tab navigation and dark appearance. The screenshot
  `../screenshots/native-components-web-reference-dark.png` uses synthetic data
  served only by a temporary local QA server, never bundled into the app.
- `simctl list runtimes` and `simctl list devices available` return no installed
  runtimes/devices. Native runtime appearance and frame rate have not been
  measured here; no FPS improvement is claimed.

Apple's [SwiftUI system-design walkthrough](https://developer.apple.com/videos/play/wwdc2025/323/)
describes the platform tab-bar appearance and scroll minimization behavior.

## Subsequent cinematic revision

The [cinematic Home revision](cinematic-home.md) retains native navigation and
forms, adds the red ring beside the home score, moves that score to a native
linear ProgressView, and introduces English copy and section-specific accents.
The palettes and screenshots above describe the preceding migration stage.
