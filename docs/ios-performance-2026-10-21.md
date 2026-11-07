# iPhone performance follow-up — October 21, 2026

## Console interpretation

The supplied excerpt has no crash, failed model run, memory warning or thermal
warning. `active`, `background` and `protected-data-available/unavailable` are
lifecycle/data-protection notifications, including those caused by locking and
unlocking the phone. The reported app footprint was 47–86 MB with about 3 GB
available, and thermal state 0 (nominal). These snapshots do not measure frame
time and cannot exclude brief stalls.

`duration=0s` rounded down to whole seconds. Model-run logs now use
`duration_ms`, so subsecond work is visible.

`com.apple.PointerUI…` and `cannot add handler to 0 from 0 - dropping` do not
come from this repository's log calls. They appear to be system input-service
diagnostics; the excerpt does not establish their cause or whether they affect
this app's frame rate. A [developer report on Apple's forum](https://developer.apple.com/forums/thread/841594)
contains the same handler message in a keyboard/Device Hub context. That is a
comparison, not a confirmed diagnosis for this device. App diagnostics remain
enabled.

## Changes

- Load and decode the saved summary away from the main thread at startup.
- Coalesce automatic sync requests from foreground/unlock notifications. Reuse a
  successfully computed summary for up to three minutes between those requests,
  while still checking the ring's existing automatic-sync policy. New ring
  events, profile changes, restore/reset and manual refresh bypass that window.
  A new day/timezone or an interrupted analysis also triggers revalidation;
  repeated failures have a short 15-second retry cooldown.
- Do not publish duplicate model progress labels or observe unused per-unit
  progress at the dashboard root. Reuse sorted day lists and the
  selected night's data during a home render; stop recent-value scans at 14 items.
- Compute the Apple Health export fingerprint on its existing background queue.
- Replace stacked backdrop/large blur effects on scrolling cards and ring
  backgrounds with static fills/gradients. Keep Liquid Glass on native navigation
  and a CSS glass effect on web navigation. Respect Reduce Transparency.
- Use a near-black green canvas (`#030706`), dark cards (`#0a100d`), and the
  supplied black ring with a cleaned transparent cutout in both clients.

The shared health calculations, permissions and data destinations are unchanged.

## Validation and limits

The actual local Xcode project builds its app and test bundle for generic iOS
devices with `build-for-testing` and signing disabled for validation. The user's
signing identity is preserved. The test target's generated-FFI include path was
also repaired in the project and both XcodeGen specifications.

A temporary macOS SwiftPM harness executes the production module-validation,
summary-freshness and progress code: **16 tests passed**, including notification
storms, clock/date/timezone changes, cancellation and duplicate publications.
This does not execute the SwiftUI views or prove iPhone frame rates. The Rust CLI
also builds without model features; web appearance is checked against a disposable
empty database, with no personal records.

No iOS simulator runtime or physical iPhone profiling session was available here.
Compare the updated app launched from its icon after stopping the Xcode debugger.
If a hitch remains, capture a trace on the iPhone with Instruments' SwiftUI and
Time Profiler instruments; Apple's [SwiftUI performance guide](https://developer.apple.com/documentation/Xcode/understanding-and-improving-swiftui-performance)
explains how to identify expensive or overly frequent view updates. No measured
FPS improvement is claimed without that trace.
