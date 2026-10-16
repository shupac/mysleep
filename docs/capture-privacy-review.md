# Session capture privacy review

Reviewed October 16, 2026. Both local Proxyman archives in `docs/` were inspected
by decoding their request/response storage. No provider calls were made.
Sensitive values are intentionally omitted from this review.

## Decision: keep the raw captures out of Git

These files contain substantial security and privacy risks, rather than minimal
identifying metadata. Keep both `.proxymansessionv2` files ignored, including when
stored under `docs/`. Preserve the useful API evidence in
[captured-api-reference.md](captured-api-reference.md) instead.

| Finding | October 15 | October 16 | Why it matters |
| --- | --- | --- | --- |
| Total recorded flows | 162 | 145 | Includes unrelated connection metadata |
| Eight Sleep HTTP requests | 110 | 98 | Decrypted headers and JSON bodies |
| Requests with Authorization headers | 110 | 96 | Bearer credentials must not enter Git |
| Refresh-grant requests with refresh tokens | None observed | 2 | Potential account access beyond a short-lived access token |
| Token responses with access and refresh tokens | None observed | 2 | Usable secrets, subject to expiry/revocation |
| Populated personal profile fields | Yes | Yes | Email, first/last name, birth date, gender, ZIP code, user ID, current device |
| Sleep and physiological records | Yes | Yes | Sleep timing/stages, scores, HRV, heart/respiratory data, snoring and time series |
| Push registration write | 1 | 1 | Contains a device notification token and registration identifier |
| Non-Eight Sleep CONNECT records | 52 | 47 | Destination services, IP/port metadata and device/network context |

Additional identifying information includes household/device assignments,
health-source identifiers, request/session/device headers, timezone, and
pagination cursors. App-state message keys themselves can encode account IDs,
UUIDs, and historical dates, even when the values look like harmless UI state.
Removing Authorization headers alone would not sanitize either archive.

The health-integration POSTs have extensive HealthKit metric names and checkpoint
timestamps. In these captures their `value` arrays are empty and the demographic
value is `na`; they do not establish that populated HealthKit samples were uploaded.
The separate sleep API responses still contain substantial personal health data.
Likewise, a pregnancy-mode route or feature flag does not establish a personal
pregnancy status.

The unrelated services are CONNECT destinations only: the files do not establish
that Gmail, LastPass, Dropbox, ChatGPT, or other services' message content or
credentials were decrypted. Their domain/network metadata is still private.
The complete destination/count inventory is in the sanitized reference.

## Useful evidence retained

The reference accounts for every Eight Sleep request by host, method, templated
path, capture date and flow number. It documents all 53 distinct method/path/host
combinations, query parameters, request body field shapes, observed status codes,
and response top-level fields. It also lists all 44 other CONNECT destinations.
Repeated requests are grouped with their full flow-number lists.

The most useful contracts are:

- Sleep reports use Trends `model-version=v3` and expose duration/stage/raw metric
  fields beyond the older eightctl parser. The captures establish both
  `consistent-read=false` and `true` request variants.
- Ending sleep is an interval edit: discover an incomplete interval, PUT
  `{"edit":"stop"}`, then read Trends with `consistent-read=true`. It is a
  distinct operation from powering off heating/cooling.
- The official app also uses `PUT /v1/users/{userId}/temperature/pod` on the app
  API host, with `ignoreDeviceErrors=false` and a `currentState.type` body of
  `off` or `smart`. This is additional evidence; MySleep's existing power
  operations use a different eightctl-derived temperature endpoint.
- Refresh-token authentication, paginated intervals, temperature schedules,
  alarms, autopilot details/recap, aggregates, insights, subscriptions and feature
  flags are available for future investigation. Their presence does not imply
  that MySleep implements them or that their semantics are fully understood.

## Handling and validation

Keep the originals locally only as long as they are useful. Do not upload them to
a repository, issue, or public attachment. If a copy is needed for sharing,
construct a new synthetic fixture from the documented field shapes; replacing
only obvious tokens in a Proxyman ZIP is insufficient because metadata and
multiple storage sections may retain identifying information.

The sanitized reference excludes header values, tokens, personal scalar values,
raw date/ID paths, cursors, and account-specific message keys. A local comparison
against observed JWT strings, email addresses, long hex identifiers and bearer
header values found no matches in the generated reference. This is a targeted
check, not a general guarantee that arbitrary raw archives can be sanitized.

The repository ignore rules apply in all directories. These captures were not
tracked by the initial commit, so moving them into `docs/` did not add them to
Git history. No token validity or revocation was tested. If the originals are
shared outside trusted local storage, revoke the exposed sessions through the
provider; the files alone do not establish whether a token remains valid.
