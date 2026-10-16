# Local validation — 2026-10-14

- **44 Swift core tests passed**, 0 failures (`swift test --package-path native`).
  Coverage includes form encoding, token expiry and reauthentication, user-ID
  discovery, bounded retries and Retry-After, timezone/DST dates, completion
  selection, stage percentages, missing/zero data, HRV score separation, caching,
  concurrent fetch coalescing, account switching, spoken summaries, Pod status,
  smart-mode/level writes, off/on bodies, rejected-token replay, ambiguous write
  failures, partial temperature changes, and report/control serialization.
- **4 iPhone UI tests passed**, 0 failures, on iPhone 17 Pro / iOS 26.1 Simulator:
  report and Settings, cached/offline report, first-run onboarding, and the Pod
  control flow (apply temperature, confirm End sleep, then verify off state).
- Both **iPhone and watchOS simulator builds succeeded**, including app icons and
  generated App Intent metadata. The iPhone build embeds the Watch app correctly.
- Both interfaces were launched and visually inspected with synthetic data.
  `watch-preview.png` and `iphone-preview.png` are fixture screenshots.
- The Watch Info.plist has `WKRunsIndependentlyOfCompanionApp = true`.
  Generated intent metadata on both platforms includes `GetLatestSleepIntent`,
  a text return value, dialog support, and local-device authentication policy.

The first iOS 26.3 simulator attempt failed during test-runner startup. Retrying
on iOS 26.1 exposed two UI assertions using visible rather than accessibility text;
those were corrected, and all three tests passed in the final run.

## Still requires your configuration / devices

- Development signing and installation on your real iPhone and Apple Watch.
- Sign-in on each device, verification of live provider responses and account
  metric availability (especially raw HRV, snoring, and precise sleep timing).
- Keychain behavior on locked/unlocked physical devices; unit tests use isolated
  memory storage rather than altering your real Keychain.
- Siri phrase recognition and on-Watch Shortcut routing with the iPhone out of
  reach. Simulator builds don't prove those physical-device behaviors.

No real Eight Sleep credentials were used, no live API requests were made, and
no backend, cloud resources, or App Store submission were created.

## Watch controls update

The shared control screen compiles for iOS and watchOS. The Watch preview
`watch-controls-preview.png` is from Debug demo mode. End sleep now uses the captured interval-stop
request (see provenance.md); the existing screenshots predate that change. No live Pod control was exercised.

## Fahrenheit controls update

The selector and reported setting now display °F. Five additional core tests
verify nonlinear reference points, all 56 selectable whole-degree round trips,
nearest-level readback, invalid input, and the final JSON body (68°F sends −58).
The demo UI flow also adjusts the Fahrenheit slider before applying. Selectable
setpoints are 55–110°F; an existing level-100 setting is faithfully shown as
111°F according to the lookup table, without automatically changing it.

## Watch sleep-score complication

- Added a WidgetKit extension with circular, corner, inline, and rectangular
  layouts, plus shared App Group provisioning configuration.
- All **44 Swift core tests pass**, including score snapshot formatting, missing
  scores, time-based stale status, cached/offline publication, successful fetches,
  and clearing the shared score on account changes and sign-out.
- Both simulator builds pass. Bundle checks verify that iPhone embeds the Watch
  app, the Watch app embeds the WidgetKit extension, and their shared App Group
  identifiers match.
- The Watch app and Siri publish only score/report dates to the complication;
  credentials remain in the Watch app's Keychain. No background API polling.
- Physical Watch signing/App Group provisioning, watch-face placement, system
  reload scheduling, and locked/Always On privacy behavior need device testing.

## Trends v3 compatibility — 2026-10-15

- 48 core tests pass, including v3 aggregate durations, available raw quality
  metrics, incomplete-day exclusion, and stage-duration reconciliation.
- The parser was also run locally against the supplied official-app Trends
  response. It successfully selects the 2026-10-15 report and extracts sleep
  duration, stages, and HRV. No private capture data was added to fixtures.
- The request contract test now requires `model-version=v3`.

## Local web client — 2026-10-15

- The web server compiles the shared native Core with a JSON-lines Swift bridge;
  it uses isolated in-memory session/report storage rather than native Keychain.
- Eight Python handler/bridge tests pass: origin/Host checks, static-file
  allowlisting, malformed input, safe failures, demo isolation, and disconnect.
- A Swift transport test passes for token/account-ID redaction, omission of raw
  metric values, schema diagnostics, and exclusion of authentication bodies.
- JavaScript syntax checks pass. The local browser demo was visually inspected
  and shows synthetic sleep, stages, heart rate, HRV, and respiratory rate.
- No real credentials or live Pod commands were used. Live report reproduction
  requires signing into the local web client.

## Awake slice — 2026-10-15

- 51 core tests pass. New coverage verifies summed session awake duration,
  exclusion of out-of-bed time, matching sleep/session totals, missing/invalid
  summaries, zero awake duration, and chart percentages using sleep + awake.
- Eight web tests pass; JavaScript syntax check passes.
- iOS and watchOS simulator builds succeed. The web chart was visually verified
  with synthetic data showing four stages, including a distinct Awake slice.
- The supplied captured latest-day session summaries reconcile and their awake
  duration fits the day presence window. No private capture data was committed.

## Essential metrics view — 2026-10-15

Removed charts and extra metrics from the iPhone, Watch, and web report views.
The three report groups are Overall (sleep score), Biometrics (HR, raw HRV),
and Duration (total sleep, Deep, REM, bedtime and wake time). Presence-only
fallback times retain their honest labels. Both native simulator builds pass;
JavaScript syntax passes and the web view was visually verified with demo data.
No API or parsing behavior changed.


## Interval stopping update — 2026-10-16

All 55 Swift core tests passed, including interval selection, completed/stale/future
interval rejection, no replay after a failed stop write, and bypassing a fresh
report cache after stopping sleep with a consistent Trends read. Tests use
synthetic requests and responses. Full app build validation was blocked by
unavailable CoreSimulator services / watchsimulator runtimes in the environment.
The updated UI confirmation has not been rerun in the simulator. No live Eight
Sleep request was sent.
