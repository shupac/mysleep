# Eight Sleep cloud API, traced from eightctl

Inspected 2026-10-14. Source: `/Users/shu/code/eightctl`, commit
`d260bb4dc038623bef998350629999980be9f3a9` of
[steipete/eightctl](https://github.com/steipete/eightctl).

This documents the requests the checked-out client implements. No account login,
live sleep-data request, or Pod change was performed. Mock tests establish client
behavior, not current provider acceptance. These are undocumented cloud APIs;
capabilities and response fields may vary by account and hardware.

## 1. Authentication

```http
POST https://auth-api.8slp.net/v1/tokens
Content-Type: application/x-www-form-urlencoded
```

Form fields (URL-encode each value, rather than building the string manually):

| Field | Value |
| --- | --- |
| `grant_type` | `password` |
| `username` | Your Eight Sleep email |
| `password` | Your Eight Sleep password |
| `client_id` | `0894c7f33bb94800a03f1f4df13a4f38` |
| `client_secret` | `f0954a3ed5763ba3d06834c73731a32f15f168f47d4f164751275def86db0c76` |

The repo identifies these client constants as extracted from the official Android
app v7.39.17; both are configurable. They identify the app client. Your account
email/password authorize the account access. The implementation sends the client
credentials in the form body, with no HTTP Basic authorization or existing bearer
token. It implements no browser redirect, authorization code, PKCE, MFA, or SSO flow.

Fields decoded from the successful response, shown with illustrative values:

```json
{
  "access_token": "ACCESS_TOKEN",
  "expires_in": 3600,
  "userId": "USER_ID"
}
```

`expires_in` is seconds. An empty access token is an error. Missing/zero
`expires_in` defaults to 3600 in this client; that fallback is not proof of the
provider's actual token lifetime. The effective expiry is calculated as login
response processing time + `expires_in` - 60 seconds. Treat the access token as an
opaque bearer credential; the client does not decode or validate it as a JWT.

Source: [auth.go](/Users/shu/code/eightctl/internal/client/auth.go:18),
[host and client constants](/Users/shu/code/eightctl/internal/client/eightsleep.go:11).

## 2. Hosts, identity, and endpoint selection

| Purpose | Base URL |
| --- | --- |
| Token exchange | `https://auth-api.8slp.net/v1` |
| Sleep metrics, users, devices, most features | `https://client-api.8slp.net/v1` |
| Power, temperature, smart schedule, away mode | `https://app-api.8slp.net/v1` |

Below, `C` means the client base and `A` means the app base, both INCLUDING `/v1`.
The Go `AppURL` constant itself excludes `/v1`, so its call sites add it. Avoid
accidentally omitting or duplicating that segment in your function.

### Identity and sides

1. Use the token response's `userId`, if supplied. Otherwise request
   `GET C/users/me` and read `user.userId`.
2. `GET C/users/me` also supplies `user.currentDevice.id`; if missing, eightctl
   falls back to the first string in `user.devices`.
3. For side targeting, request
   `GET C/devices/{deviceId}?filter=leftUserId,rightUserId,awaySides`.
4. Read the device response's `result.leftUserId`, `result.rightUserId`, and
   `result.awaySides`. Optionally fetch `GET C/users/{targetUserId}` for identity
   and `user.currentDevice.side`.

Temperature actions target a **user ID**. There is no `side=left` query or body
field in these calls. Household-wide controls are separate requests for each
resolved user. The same account token is reused; selecting a household user does
not cause a new login. Access still depends on provider authorization.

Away mode can change or collapse the top-level side assignments. eightctl prefers
distinct IDs from `awaySides.leftUserId` and `awaySides.rightUserId` when both
exist; otherwise it fills missing top-level IDs from awaySides. A single unique
user is treated as `solo`. A user-reported side of `away` is not a physical side.
Fetched target-user responses must contain the exact requested user ID.

Sources: [identity discovery](/Users/shu/code/eightctl/internal/client/eightsleep.go:68),
[target discovery and mapping](/Users/shu/code/eightctl/internal/client/targets.go:44).

### Core endpoint map

| Operation | Method and URL | Query/body |
| --- | --- | --- |
| Discover account/device | `GET C/users/me` | None |
| Read user | `GET C/users/{userId}` | None |
| Device information / side mapping | `GET C/devices/{deviceId}` | Optional `filter` above |
| Sleep data for day/range | `GET C/users/{userId}/trends` | Query below |
| Session intervals | `GET C/users/{userId}/intervals/{sessionId}` | No query/body |
| Temperature event history | `GET C/users/{userId}/temp-events` | Optional `from`, `to` |
| Status and smart schedule | `GET A/users/{userId}/temperature` | None |
| Turn on | `PUT A/users/{userId}/temperature` | `{"currentState":{"type":"smart"}}` |
| Turn off | `PUT A/users/{userId}/temperature` | `{"currentState":{"type":"off"}}` |
| Set level | Two sequential `PUT A/users/{userId}/temperature` requests | First smart body above, then `{"currentLevel":-20}` |
| Read away mode | `GET A/users/{userId}/away-mode` | None |
| Enable away | `PUT A/users/{userId}/away-mode` | `{"awayPeriod":{"start":"TIMESTAMP"}}` |
| Disable away | `PUT A/users/{userId}/away-mode` | `{"awayPeriod":{"end":"TIMESTAMP"}}` |

Temperature levels are integers in `[-100,100]`, not degrees Celsius/Fahrenheit.
Setting a level also turns on smart mode; the two writes are not atomic. The
client does not establish that combining both fields in one PUT is supported.
Writes ignore the successful response body, so your handler must tolerate an empty
success response (e.g. HTTP 204).

For away writes, eightctl sets TIMESTAMP to UTC now minus 24 hours, formatted
`YYYY-MM-DDTHH:mm:ss.sssZ`. This is what the implementation does; it does not
establish the full range of timestamps the provider accepts. Away state readback
may lag a successful write.

Sources: [temperature.go](/Users/shu/code/eightctl/internal/client/temperature.go:27),
[metrics.go](/Users/shu/code/eightctl/internal/client/metrics.go:14),
[away.go](/Users/shu/code/eightctl/internal/client/away.go:14),
[schedules.go](/Users/shu/code/eightctl/internal/client/schedules.go:16).

## 3. Request structure

### Authenticated request headers

These are the headers eightctl sends. Source inspection alone does not establish
which optional headers the provider strictly requires.

```http
Authorization: Bearer ACCESS_TOKEN
Content-Type: application/json; charset=UTF-8
Accept: application/json
User-Agent: okhttp/4.9.3
Connection: keep-alive
```

Bodies are JSON, except the form-encoded login. GET calls have no body. The client
sends the same bearer token to both API hosts. It sends no API key, cookie,
device-signature header, or timestamp signature. Let the runtime handle compression
and connection pooling; edge runtimes may manage or restrict `Connection`.

The Go client uses a 20-second timeout per HTTP request, TLS >=1.2, and disables
HTTP/2 because the repo reports hangs against the provider with Go HTTP/2. This is
an implementation compatibility choice, not proof that other runtimes must disable
HTTP/2.

Source: [transport.go](/Users/shu/code/eightctl/internal/client/transport.go:38),
[HTTP client configuration](/Users/shu/code/eightctl/internal/client/eightsleep.go:42).

### Sleep query

Example (use URLSearchParams or an equivalent URL encoder):

```text
GET https://client-api.8slp.net/v1/users/USER_ID/trends
    ?from=2026-10-01
    &to=2026-10-14
    &tz=America%2FLos_Angeles
    &include-main=false
    &include-all-sessions=true
    &model-version=v2
```

| Parameter | eightctl behavior |
| --- | --- |
| `from` | Start calendar date, `YYYY-MM-DD`; set equal to `to` for a single day |
| `to` | End calendar date, `YYYY-MM-DD` |
| `tz` | Resolved IANA timezone; use `America/Los_Angeles` explicitly in a serverless environment |
| `include-main` | Always string `false` |
| `include-all-sessions` | Always string `true` |
| `model-version` | Always string `v2` |

The generic Trends method omits empty `from`/`to`; GetSleepDay sends both. The
repository does not establish provider date-span limits, pagination, or the
meaning of all these flags. `tz=local` is not accepted according to its comments.
Use explicit dates in the selected timezone rather than the serverless host's UTC
calendar date. A range can be requested in one Trends call; the CLI's `sleep range`
command happens to loop over days and is less efficient for this purpose.

Source: [sleep.go](/Users/shu/code/eightctl/internal/client/sleep.go:41),
[metrics.go](/Users/shu/code/eightctl/internal/client/metrics.go:14).

## 4. Response structure

There is no universal `data` or `result` envelope. The following are partial
structures consumed by the client, with illustrative values; these are not live
captures or complete provider schemas. Preserve unknown fields if exporting raw
data. In particular, the Go structs turn missing numeric fields into zero, so a
new integration should distinguish absent/null values from real zero values.

### Account and device

```json
{
  "user": {
    "userId": "USER_ID",
    "devices": ["DEVICE_ID"],
    "currentDevice": {"id": "DEVICE_ID", "side": "left"}
  }
}
```

```json
{
  "result": {
    "leftUserId": "LEFT_USER_ID",
    "rightUserId": "RIGHT_USER_ID",
    "awaySides": {}
  }
}
```

### Trends

Fields from the sleep and presence parsers, combined here for illustration:

```json
{
  "days": [{
    "day": "2026-10-13",
    "score": 88,
    "tnt": 3,
    "respiratoryRate": 14.2,
    "heartRate": 56,
    "latencyAsleepSeconds": 600,
    "latencyOutSeconds": 120,
    "sleepDurationSeconds": 27000,
    "stages": [{"stage": "EXAMPLE_STAGE", "duration": 3600}],
    "sleepQualityScore": {
      "hrv": {"score": 80},
      "respiratoryRate": {"score": 90}
    },
    "presenceStart": "2026-10-14T05:30:00Z",
    "presenceEnd": "2026-10-14T13:15:00Z",
    "sessions": [{
      "timeseries": {
        "heartRate": [["2026-10-14T12:00:00Z", 56]]
      }
    }]
  }]
}
```

The parser establishes named `*Seconds` fields, `stages[].stage/duration`, and
`sessions[].timeseries` as a map of arrays of sample arrays. It reads sample
element 0 as an RFC3339 timestamp. Tests use a numeric heart rate in element 1;
the parser itself only inspects the timestamp. Stage enum values, stage-duration
units, `tnt` semantics, session ID field name, and the full timeseries contract are
not established by these structs. `sleepQualityScore.hrv.score` is a score field;
do not label it raw HRV milliseconds without verifying actual responses.

`days: []` is possible. GetSleepDay turns it into an error and otherwise returns
only `days[0]`. Use raw Trends for the full payload. Session intervals are decoded
into `any`, so the repo establishes their URL but no trustworthy response schema
or session-ID discovery rule. Inspect a real authorized Trends response before
implementing that linkage.

Presence is inferred from Trends, not obtained from a dedicated realtime sensor
endpoint. eightctl considers recent heart-rate timestamps (<=10 minutes, or <=30
minutes without presenceEnd), then falls back to an open presence window. This
heuristic can report stale presence and should not be presented as realtime truth.

Sources: [SleepDay](/Users/shu/code/eightctl/internal/client/sleep.go:14),
[presence parser](/Users/shu/code/eightctl/internal/client/presence.go:12),
[intervals method](/Users/shu/code/eightctl/internal/client/metrics.go:33).

### Temperature and schedule

```json
{
  "currentLevel": -20,
  "currentState": {"type": "smart"},
  "smart": {}
}
```

`currentLevel` and `currentState.type` are at the root. The status parser does not
restrict the returned type to an enum. `smart` is the raw Autopilot schedule object;
missing/null `smart` means no configured smart schedule to this client. Its
internal fields are not typed. Away GET instead expects root `{"isAway":true}`
and fails if the boolean is missing.

### CLI output is not the upstream schema

`sleep day/range` maps fields to CLI names such as `date`, `duration`, `heart_rate`,
and `hrv_score`. `metrics trends` wraps the raw response inside a CLI row's
`trends` field; `metrics intervals` similarly uses `interval`. Those extra wrappers
are produced locally and must not be assumed to exist in the HTTP response.

## 5. Token management and failures

The client implements **renewal through the password grant**, not a refresh-token
exchange. It neither parses nor stores `refresh_token`; that does not prove the
provider never returns one or offers other flows.

Request lifecycle:

1. Reuse a valid token in process memory.
2. Otherwise load an unexpired cached token. The cached effective expiry already
   includes the 60-second margin; there is no token-introspection request.
3. If no usable cached token exists, repeat the form-encoded credential login.
4. For an API 401, close the response, clear the rejected in-memory token and
   attempt cache deletion, then authenticate directly. Direct login avoids
   reloading the rejected token if cache deletion failed. Replay the request.
5. For an API 429, close the response and wait 2, 4, then 6 seconds. The shared
   retry limit is three retries after the original attempt (four API attempts
   total). Mixed 401/429 responses consume the same counter.

Token endpoint failures are returned immediately; that login call does not use
the API retry loop. Network errors and other API error statuses are also returned
without automatic retry. The implemented 429 handling ignores `Retry-After`.
Authentication errors expose HTTP status only; other API errors include the raw
body in the returned error string. Do not log that body blindly in a new service.

Cache records have `token`, `expires_at` (serialized timestamp), and optional
`user_id`. Identity is scoped to API base URL + OAuth client ID + normalized email,
not the selected target user ID. Local logout deletes cache entries but does not
revoke the server-side token.

Sources: [auth lifecycle](/Users/shu/code/eightctl/internal/client/auth.go:69),
[retry loop](/Users/shu/code/eightctl/internal/client/transport.go:38),
[cache](/Users/shu/code/eightctl/internal/tokencache/tokencache.go:25).

## Serverless integration design

The following are implementation recommendations derived from this flow:

- Keep email/password in the platform's secret store so expired/rejected tokens
  can be renewed. Avoid exposing account credentials or bearer tokens to clients.
- Keep a warm-instance token cache for speed and a protected persistent token
  record for reuse across cold starts. Do not rely on local disk/keychains for
  durable state. Key it by account and client identity, not Pod side.
- Use a distributed lock or conditional update around renewal, with a recheck
  after acquiring it, to prevent simultaneous cold starts from flooding login.
  Version token records so a late 401 cannot delete a newer token.
- Pin the authorized target user(s), encode path components, validate temperature
  as an integer in range, and expose a small set of operations instead of an
  arbitrary authenticated URL proxy. Protect the function's own inbound endpoint.
- Explicitly send the account's IANA timezone for every sleep query.
- A successful write confirms API acceptance; allow for delayed cloud readback.
  Report partial success when the first temperature PUT succeeds and the second
  fails, or when controlling several household users.
- Use bounded retries and a function deadline that covers API calls and renewal.
  Honor `Retry-After` when available; avoid automatically replaying ambiguous
  network failures for actions such as alarm creation or nap extension.

The first live validation should cover login, `/users/me`, one day of Trends, and
temperature GET. Those read-only responses will resolve the remaining schema
gaps before enabling controls.

## Additional Pod feature endpoints implemented in the repo

All paths in this appendix are relative to `C` unless marked `A`. These describe
implemented request construction; they have not been verified live here. Most
responses are passed through as untyped JSON.

| Method and path | Request body / decoded response |
| --- | --- |
| `GET /users/{u}/alarms` | Response `{"alarms":[...]}` |
| `POST /users/{u}/alarms` | Alarm fields `id`, `enabled`, `time`, `daysOfWeek`, `vibration`, optional `sound`; response `{"alarm":{...}}` |
| `PATCH /users/{u}/alarms/{a}` | Patch object; response `{"alarm":{...}}` |
| `DELETE /users/{u}/alarms/{a}` | No body; success response ignored |
| `POST /users/{u}/alarms/{a}/snooze` | `{}` |
| `POST /users/{u}/alarms/{a}/dismiss` | `{}` |
| `POST /users/{u}/alarms/active/dismiss-all` | `{}` |
| `POST /users/{u}/vibration-test` | `{}` |
| `POST /users/{u}/temperature/nap-mode/{action}` | `{}`; action `activate`, `deactivate`, `extend` |
| `GET /users/{u}/temperature/nap-mode/status` | Untyped JSON |
| `POST /users/{u}/temperature/hot-flash-mode/{action}` | `{}`; action `activate`, `deactivate` |
| `GET /users/{u}/temperature/hot-flash-mode` | Untyped JSON |
| `GET /users/{u}/autopilotDetails` | Untyped JSON |
| `GET /users/{u}/autopilot-history` | Untyped JSON |
| `GET /users/{u}/autopilotDetails/autopilotRecap` | Untyped JSON |
| `POST /users/{u}/level-suggestions-mode` | `{"enabled":true}` or false |
| `POST /users/{u}/autopilotDetails/snoringMitigation` | `{"enabled":true}` or false |
| `GET /users/{u}/base` | Untyped JSON |
| `POST /users/{u}/base/angle` | `{"head":20,"foot":0}`; example values, provider limits not established |
| `GET /users/{u}/base/presets` | Untyped JSON |
| `POST /users/{u}/base/presets` | `{"name":"PRESET_NAME"}` |
| `POST /devices/{d}/vibration-test` | `{}` |
| `GET /users/{u}/audio/tracks` | `{"tracks":[{"id":"...","title":"...","type":"..."}]}` |
| `GET /audio/tracks` | Same decoded track fields |
| `GET /audio/categories` | Untyped JSON |
| `GET /users/{u}/audio/player/state` | Untyped JSON |
| `POST /users/{u}/audio/player` | `{"action":"play","trackId":"..."}` (trackId optional), or `{"action":"pause"}` |
| `POST /users/{u}/audio/player/seek` | `{"position":10000}`; milliseconds |
| `POST /users/{u}/audio/player/volume` | `{"level":50}`; provider bounds not established |
| `POST /devices/{d}/audio/player/pair` | `{}` |
| `GET /users/{u}/audio/tracks/recommended-next-track` | Untyped JSON |
| `GET /users/{u}/audio/tracks/favorites` | Untyped JSON |
| `POST /users/{u}/audio/tracks/favorites` | `{"trackId":"..."}` |
| `DELETE /users/{u}/audio/tracks/favorites/{trackId}` | No body |
| `GET /devices/{d}/peripherals` | Untyped JSON |
| `GET /devices/{d}/owner` | If this fails, client extracts `result.ownerId` from device info |
| `GET /devices/{d}/warranty` | Untyped JSON |
| `GET /devices/{d}/online` | Untyped JSON |
| `GET /devices/{d}/priming/tasks` | Untyped JSON |
| `GET /devices/{d}/priming/schedule` | Untyped JSON |

Alarm `time` is a string and `daysOfWeek` is an integer array; the client structs
do not establish weekday numbering, valid sound names, or the server's minimum
required create fields. Check these before exposing alarm creation.

Sources: [alarms](/Users/shu/code/eightctl/internal/client/alarmlist.go),
[alarm actions](/Users/shu/code/eightctl/internal/client/alarms.go),
[temperature modes](/Users/shu/code/eightctl/internal/client/tempmodes.go),
[Autopilot](/Users/shu/code/eightctl/internal/client/autopilot.go),
[base](/Users/shu/code/eightctl/internal/client/base.go),
[audio](/Users/shu/code/eightctl/internal/client/audio.go),
[catalog](/Users/shu/code/eightctl/internal/client/catalog.go),
[devices](/Users/shu/code/eightctl/internal/client/device.go).

The changelog records retired schedule CRUD and metrics summary/aggregate/insights
features. Use Trends for sleep metrics and the temperature resource's `smart`
field for the currently implemented schedule read.
