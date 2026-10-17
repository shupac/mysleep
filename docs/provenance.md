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

The initial implementation reused those endpoints. Later user-supplied captures
established additional endpoints and the v3 schema described below. No live API
requests were made to audit those captures. Synthetic fixtures remain test cases;
source observations and implementation limits are documented separately.

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
No temperature-off write appears in this captured sequence. The initial End sleep
implementation only stopped the interval; the October 17 update below adds power-off. Selection uses the newest incomplete interval on the first page,
restricted to starts within 36 hours to avoid editing old records. The initial implementation reported an error when no active candidate existed;
the October 17 update allows bed-off to succeed in that case. Writes retain the existing no-transient-
retry policy. The next report bypasses the local freshness cache. Synthetic
fixtures test the contract; no live provider writes were made during development.


## Capture audit and full inventory — 2026-10-16

See the [complete captured API reference](captured-api-reference.md) for all 53
observed Eight Sleep method/host/path combinations and their flow references,
including the official app's temperature/pod power writes. The
[privacy review](capture-privacy-review.md) records the decision to retain the raw
archives locally and exclude them from Git because they contain tokens and
personal account, device, and sleep data. The earlier eightctl-only notes now
live in [eightctl-api-notes.md](eightctl-api-notes.md).


## Combined End sleep action — 2026-10-17

At the user's request, the Watch/iPhone button and EndSleepIntent now first send
the existing profile-scoped temperature-off command, then stop the newest recent
incomplete interval. These are separate requests, not an atomic provider API.
A rejected/unconfirmed power-off stops the operation; if power-off is accepted
but interval discovery or stopping fails, a dedicated partial-result error says
so. An absent active interval still permits successful power-off. No writes are
replayed after ambiguous network/server failures. This combines the existing
eightctl-derived power contract with the captured interval-stop contract; it is
not a newly observed single official-app operation.

The End Sleep App Intent exposes the same operation on both platforms. App
Shortcut phrases use the application-name placeholder as required by Apple's
[App Intents guidance](https://developer.apple.com/videos/play/wwdc2025/244/).
The app refreshes App Shortcut registration at startup. For the exact phrase
“Hey Siri, end sleep”, create a personal shortcut named End sleep using the
MySleep End Sleep action and enable Show on Apple Watch. Apple's
[Siri shortcut instructions](https://support.apple.com/guide/shortcuts/apd07c25bb38/ios)
explain invocation by personal shortcut name. Settings now includes this setup.


The primary built-in phrase is now **“End with MySleep”**, added October 17 after
Siri routed the shorter sleep phrase to an unrelated room command. The earlier
app-qualified phrases remain aliases. Physical voice recognition still requires
a device check.


## Live active-mode correction — 2026-10-17

Read-only authenticated status checks on all three documented temperature reads
returned `smart:bedtime`. Native UI previously accepted only exact `smart`; it
therefore hid controls as an unsupported mode despite the bed being on. The
shared `PodStatus.isOn` now recognizes bare `smart` and nonempty `smart:` phase
variants. Screen selection, temperature readback confirmation, and resetting the
completed-sleep override all use that predicate. Unknown families still expose
no controls, with an explicit unavailable-status label on the report fallback.
The recorded session was used for authentication; no tokens, profile IDs or
personal readings were written to documentation or printed. No bed-control
request was issued during diagnosis.


The current primary built-in phrase is **“Done sleeping with MySleep”**. The
shortcut tile is labeled Done sleeping; the stable EndSleepIntent identifier and
End Sleep action remain compatible with existing personal shortcuts. Earlier
app-qualified phrases remain aliases. No personal shortcut is required for this
app-qualified phrase.


## Locked-phone HomePod End Sleep — 2026-10-17

EndSleepIntent now uses `alwaysAllowed`, permitting the action to run on the
locked phone selected by HomePod Personal Requests. GetLatestSleepIntent retains
`requiresLocalDeviceAuthentication`. The existing saved session migrates in place
on its next successful unlocked load to
`kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`, with synchronization disabled.
All new session/token saves use that same protection class. An already-migrated
load performs no attribute write, allowing later locked reads. Migration errors
surface without deleting/replacing saved bytes. Before the first unlock after
reboot, the OS still denies access. Report file protection is unchanged.

Apple references: [alwaysAllowed](https://developer.apple.com/documentation/appintents/intentauthenticationpolicy/alwaysallowed),
[device-only background Keychain access](https://developer.apple.com/documentation/security/ksecattraccessibleafterfirstunlockthisdeviceonly),
[Personal Requests](https://support.apple.com/en-us/108397). The app change is not
a guarantee that HomePod's separate voice recognition/authentication settings are
configured.
