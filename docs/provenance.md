# Reused API work

The implementation ports the already-inspected checkout of
[steipete/eightctl](https://github.com/steipete/eightctl), commit
`d260bb4dc038623bef998350629999980be9f3a9`.

| Swift component | Existing source |
| --- | --- |
| `EightClient.swift` form login and expiry | `internal/client/auth.go` |
| Token endpoint and public Android app client constants | `internal/client/eightsleep.go` |
| Bearer headers and rejected-token handling | `internal/client/transport.go` |
| Trends query, model flags, timezone | `internal/client/metrics.go`, `sleep.go` |
| Aggregate sleep fields and stage shape | `internal/client/sleep.go` |
| Ended presence window and session time series | `internal/client/presence.go` |

Swift uses a device-local Keychain instead of eightctl's OS/file fallback. A single
actor coalesces UI/intent fetches. Reauthentication is limited to once per GET;
GET 429/5xx responses have at most two short retries. Long Retry-After values fail
promptly rather than retrying earlier than permitted. The service imposes a
one-minute cooldown after failures, keeping Siri latency and login traffic bounded.
No provider response bodies or credentials are logged or exposed in error text.

No new API endpoints were discovered or contacted for this implementation. Raw
HRV, snoring, and precise sleep timestamps aren't established by the old typed
parser. Their optional projections and limitations are documented in the README;
synthetic fixtures are test cases, not evidence of live provider support.

The reused eightctl portions are covered by the accompanying
[eightctl MIT license](eightctl-LICENSE.txt).

# Apple references used for native integration

- [Creating an independent watchOS app](https://developer.apple.com/documentation/watchos-apps/creating-independent-watchos-apps)
- [Keeping watchOS content up to date](https://developer.apple.com/documentation/watchos-apps/keeping-your-watchos-app-s-content-up-to-date)
- [Creating an App Intent](https://developer.apple.com/documentation/appintents/creating-your-first-app-intent)
- [AppIntent authentication and execution](https://developer.apple.com/documentation/appintents/appintent)
- [Running shortcuts with Siri](https://support.apple.com/guide/shortcuts/apd07c25bb38/ios)
- [Showing shortcuts on Apple Watch](https://support.apple.com/guide/shortcuts/apd5888b0858/ios)

## Pod controls

`EightClient.podStatus` and `control` reuse `internal/client/temperature.go`:
GET/PUT `https://app-api.8slp.net/v1/users/{userId}/temperature`. Temperature
uses two sequential PUTs (`currentState.type=smart`, then `currentLevel`), and
power-off sends `currentState.type=off`. End sleep now uses the captured interval
contract below. Controls are scoped to the authenticated
user. Writes accept empty success bodies; only rejected-token responses are
replayed, and partial changes are surfaced explicitly. No live Pod was changed
during development/testing.

## Fahrenheit conversion

The UI uses whole-degree Fahrenheit setpoints from 55°F to 110°F. Conversion uses
the nonlinear `RAW_TO_FAHRENHEIT_MAP` from the MIT-licensed
[pyEight constants](https://github.com/lukas-clarke/eight_sleep/blob/main/custom_components/eight_sleep/pyEight/constants.py),
inspected 2026-10-14. Its [conversion utility](https://github.com/lukas-clarke/eight_sleep/blob/main/custom_components/eight_sleep/pyEight/util.py)
selects the nearest lookup entry and preserves the first entry on ties. MySleep
uses the same rule, including duplicate Fahrenheit entries. The existing
eightctl daemon’s 55–100°F linear approximation is deliberately not used.

The selectable range follows [Eight Sleep’s published range](https://help.eightsleep.com/en_us/what-is-the-temperature-range-of-the-pod-SkIiUtbxl).
The table also contains a 111°F readback at raw level 100. That reported setting
is displayed faithfully, but the selectable control is capped at 110°F. Merely
loading a setting never sends a command. These are setpoint conversions, not
measurements of water temperature. Comparison with the user’s current official
app/firmware still requires a live-device check. See [license](pyeight-LICENSE.txt).

## Captured Trends v3 schema — 2026-10-15

A user-supplied Proxyman capture of the official iPhone app established that its
Trends request uses `model-version=v3`. Completed days contain `sleepDuration`
instead of the adapter's original required `sleepDurationSeconds`, aggregate
`deepDuration`/`remDuration`/`lightDuration`, `snoreDuration`, and an `incomplete`
flag. The captured sleep duration equals `sleepQualityScore.sleepDurationSeconds.current`,
stages sum to that duration, and snore duration equals the quality metric's
explicit seconds value. Raw HRV, heart rate, and respiratory rate are available
under `sleepQualityScore.<metric>.current`, gated by `available`.

The parser supports this observed schema as well as the original fields. Tests
use synthetic values in the captured shape. The original capture, personal
metrics, account identifiers, and authorization headers are not stored here.
No live provider requests were made to validate this change.


## Captured End sleep contract — 2026-10-16

The user-supplied morning Proxyman capture shows flow 136 reading
`GET https://client-api.8slp.net/v1/users/{userId}/intervals`. The latest interval
has `incomplete: true`. Flow 198 sends
`PUT /v1/users/{userId}/intervals/{intervalId}` with `{"edit":"stop"}` (HTTP 200).
Flow 199 reads Trends v3 with `consistent-read=true`; flow 202 rereads intervals,
where the stopped interval no longer has `incomplete` and has `edit: stop`.
No temperature-off write appears in this sequence, so End sleep only stops the
interval. Selection uses the newest incomplete interval on the first page,
restricted to starts within 36 hours to avoid editing old records. No active
candidate produces an explicit error. Writes retain the existing no-transient-
retry policy. The next report bypasses the local freshness cache. Synthetic
fixtures test the contract; no live provider writes were made during development.
