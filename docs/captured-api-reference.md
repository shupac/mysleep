# Captured Eight Sleep API reference

Evidence: the official iPhone app recordings from October 15 and 16, 2026, supplied locally in `docs/`. This reference is derived from those files without making network requests. Raw captures remain ignored by Git.

The captures contain 162 and 145 flows respectively: 110 and 98 Eight Sleep HTTP requests, plus 52 and 47 CONNECT records. All 53 distinct Eight Sleep host/method/path combinations are listed below. Flow numbers identify requests in the local Proxyman files, not stable API identifiers.

## Reading the inventory

- Paths, query names, body field names/types, HTTP status codes, and flow numbers are preserved. User, device, source, push-target, interval and date path values are replaced with placeholders.
- Query values are preserved only for API switches, metric selectors, and category enums. Dates, email, timezone, and pagination cursors are placeholders. Body descriptions contain types rather than personal values.
- Response descriptions list the union of observed top-level JSON fields/types. They are observations, not exhaustive schemas or required-field guarantees. Repeated body shapes are deduplicated; empty arrays do not establish their element type.
- Requests to the three `8slp.net` API hosts use HTTPS. Authorization headers occur on 110 requests on October 15 and 96 on October 16. Token renewal requests carry refresh credentials in their JSON body instead. Actual header values are omitted.
- The event route has HTTP 101 and upgrades to WebSocket; this inventory does not infer an event-message contract from the upgrade.
- No captured endpoint is called or added to the application merely by appearing in this reference.

## Important request contracts

These are sanitized request templates, not commands to run. Credentials and
identifiers are placeholders. Captured success does not establish error behavior,
required scopes, idempotence, or whether every account/device supports a route.

### Refresh-grant authentication

October 16 flows 121 and 122 POST to `https://auth-api.8slp.net/v1/tokens`
using `Content-Type: application/json` and this body shape:

```json
{
  "grant_type": "refresh_token",
  "client_id": "{clientId}",
  "client_secret": "{clientSecret}",
  "refresh_token": "{refreshToken}"
}
```

The successful response includes `access_token`, `refresh_token`, `expires_in`,
`token_type`, and `scope`. Preserve returned lifetimes and scope rather than
assuming fixed values. This differs from MySleep's existing form-encoded password
grant: the capture proves the official app's refresh exchange, not a change to
MySleep's current authentication implementation. App client constants alone are
not the user's credential; the actual user tokens are the sensitive material.

### Done sleeping / see my report

October 16 flow 136 reads the first interval page. The interval later targeted
by flow 198 has `incomplete: true`. That write is:

```text
PUT https://client-api.8slp.net/v1/users/{userId}/intervals/{intervalId}
Content-Type: application/json
Authorization: Bearer {accessToken}
```

```json
{"edit":"stop"}
```

It returns HTTP 200 with an interval object containing `edit`, `editDate`, sleep
and presence timestamps, stages, snoring, duration summaries, and time series.
Flow 199 immediately reads:

```text
GET https://client-api.8slp.net/v1/users/{userId}/trends?consistent-read=true&from={date}&include-all-sessions=true&include-main=false&model-version=v3&to={date}&tz={timezone}
```

Flow 202 rereads intervals: the targeted interval has `edit: stop` and no longer
contains `incomplete`. Flow 203 returns to `consistent-read=false`. These are
observed transitions, not proof of a guaranteed processing latency. The recording
does not show a temperature-off write as part of this sequence. Interval listing
returns `intervals` and `next`; flow 224 demonstrates passing the opaque cursor
back as the URL-encoded `next` query parameter. Do not derive an interval ID from
its timestamp when the API already returns `id`.

### Pod power

October 15 flow 971 sends `off`; flow 976 sends `smart`:

```text
PUT https://app-api.8slp.net/v1/users/{userId}/temperature/pod?ignoreDeviceErrors=false
Content-Type: application/json
Authorization: Bearer {accessToken}
```

```json
{"currentState":{"type":"off"}}
```

```json
{"currentState":{"type":"smart"}}
```

Both return HTTP 200 with temperature/schedule/device data. The capture also
reads status using `client-api /temperature` and `app-api /temperature/all`.
This does not establish that the official `/temperature/pod` write and MySleep's
eightctl-derived `/temperature` write are interchangeable, or that their bed-side
scope is identical for every household configuration.

### Other writes

- Profile display preferences: `PUT client-api /v1/users/{userId}` with
  `{"displaySettings":{"locale":"en-US","clockSystem":"12-hour"}}`.
  The response contains a full `user` object, including personal fields.
- Push registration: `PUT client-api /v1/users/{userId}/push-targets/{pushTargetId}`
  with `{"deviceToken":"{pushToken}","platform":"ios"}`. Successful responses
  have no decoded JSON body. Never reuse the captured token/registration ID.
- UI message state: `PUT app-api /v1/users/{userId}/app-state/messages` with
  `{"value":{"{messageKey}":"{messageValue}"}}`. Both the key and value may be
  account-specific; the response echoes this state.
- Apple Health integration: `POST app-api /v1/users/{userId}/health-integrations/sources/{sourceId}`
  with `{"metrics":{"{metricName}":{"checkpoint":"{timestamp}","value":[]}}}`.
  Captured keys include HealthKit identifiers and `biologicalSex`. The checkpoint
  endpoint reads per-source cursors. Observed uploads contain empty sample arrays
  (and `na` for the demographic value); field names alone do not prove that
  populated samples were uploaded. The inventory preserves the observed type
  variations across requests.

### Headers and response interpretation

Captured API request header names include `accept`, `accept-encoding`,
`accept-language`, `authorization`, `connection`, `content-length`, `content-type`,
`host`, `if-none-match`, `user-agent`, `x-client-app-version`, `x-client-device-id`,
`x-client-request-id`, `x-client-session-id`, `baggage`, `sentry-trace`,
`traceparent`, `tracestate`, `x-datadog-parent-id`, `x-datadog-sampling-priority`,
`x-datadog-tags`, and `x-datadog-trace-id`. The events upgrade also uses
`upgrade`, `sec-websocket-key`, `sec-websocket-version`, and
`sec-websocket-extensions`. This list records what was sent, not a requirement to
copy telemetry headers or device identifiers into a new client.

Responses use endpoint-specific envelopes (`user`, `result`, `days`, `intervals`,
etc.), rather than a universal wrapper. Account responses contain identity and
demographic data. Sleep responses contain dates and health data. A missing or null
metric must not silently become zero. Nested sleep field interpretation and
synthetic tests are described in [provenance.md](provenance.md) and the app's core
parser; the top-level inventory below does not replace those schemas.

## Endpoint inventory

### `GET https://app-api.8slp.net/v1/audio/categories`

- Evidence: Oct 15 flows 884; Oct 16 flows 143.
- Status: 200.
- Query: none.
- Request body: none recorded.
- Observed response fields: `categories: array`.

### `GET https://app-api.8slp.net/v1/devices/{deviceId}/priming/tasks/latest`

- Evidence: Oct 15 flows 898; Oct 16 flows 159.
- Status: 200.
- Query: none.
- Request body: none recorded.
- Observed response fields: `task: object`.

### `GET https://app-api.8slp.net/v1/health-survey/test-drive`

- Evidence: Oct 15 flows 892; Oct 16 flows 152.
- Status: 200.
- Query: none.
- Request body: none recorded.
- Observed response fields: `testDrive: object`.

### `GET https://app-api.8slp.net/v1/household/users/{userId}/summary`

- Evidence: Oct 15 flows 873; Oct 16 flows 129.
- Status: 200.
- Query: none.
- Request body: none recorded.
- Observed response fields: `currentSet: string, households: array`.

### `GET https://app-api.8slp.net/v1/intelligence/{userId}/podai/bio-age`

- Evidence: Oct 15 flows 927, 986; Oct 16 flows 209.
- Status: 200.
- Query: `date={date}`; `minOkNights=3`.
- Request body: none recorded.
- Observed response fields: `actualAge: number, ageDelta: null, agingCategory: null, agingStatus: null, avgPredictedAge: null, calibratedAvgPredictedAge: null, calibratedBioAge: null, calibratedMedianPredictedAge: null, calibratedPaceOfAging: null, cohortNorm: object, inProgressWeek: boolean, inWarmup: boolean, lastQualifyingWeek: null, lastUpdated: string, medianPredictedAge: null, paceOfAging: null, spectrumPosition: null, status: string, trackedNights: number, trend: null, userId: string, weekEndSunday: string`.

### `GET https://app-api.8slp.net/v1/intelligence/{userId}/podai/bio-age/trend`

- Evidence: Oct 15 flows 921, 933; Oct 16 flows 185, 213.
- Status: 200.
- Query: `minOkNights=3`; `n=90`.
- Request body: none recorded.
- Observed response fields: `lastUpdated: string, minOkNights: number, series: array, totalWeeks: number, trend: null, userId: string, windowEnd: string, windowStart: string`.

### `GET https://app-api.8slp.net/v1/purchase-tracker`

- Evidence: Oct 15 flows 889; Oct 16 flows 149.
- Status: 200.
- Query: `email={email}`.
- Request body: none recorded.
- Observed response fields: `purchases: array`.

### `GET https://app-api.8slp.net/v1/sms/users/{userId}`

- Evidence: Oct 15 flows 855, 923; Oct 16 flows 175.
- Status: 200.
- Query: none.
- Request body: none recorded.
- Observed response fields: `groups: array, id: string, phoneNumber: string, settings: object`.

### `GET https://app-api.8slp.net/v1/user/{userId}/device_maintenance/maintenance_insert`

- Evidence: Oct 15 flows 966.
- Status: 200.
- Query: `v=2`.
- Request body: none recorded.
- Observed response fields: `array<{deviceAddress: null, deviceId: string, nextInsertReplacement: null, previousInsertReplacement: null}>`.

### `GET https://app-api.8slp.net/v1/users/{userId}/app-state/messages`

- Evidence: Oct 15 flows 893, 917, 934; Oct 16 flows 151, 182, 214.
- Status: 200.
- Query: none.
- Request body: none recorded.
- Observed response fields: `value: object`.

### `PUT https://app-api.8slp.net/v1/users/{userId}/app-state/messages`

- Evidence: Oct 15 flows 928, 929, 939; Oct 16 flows 183, 187, 215.
- Status: 200.
- Query: none.
- Request body: `{value: {{messageKey}: string}}`.
- Request content type: `application/json`.
- Observed response fields: `value: object`.

### `GET https://app-api.8slp.net/v1/users/{userId}/app-state/onboard`

- Evidence: Oct 15 flows 854, 894; Oct 16 flows 153.
- Status: 200.
- Query: none.
- Request body: none recorded.
- Observed response fields: `value: object`.

### `GET https://app-api.8slp.net/v1/users/{userId}/audio/tracks`

- Evidence: Oct 15 flows 924, 925, 926; Oct 16 flows 179, 180, 181.
- Status: 200.
- Query: `category=alarms | nsdr | soundscapes`.
- Request body: none recorded.
- Observed response fields: `tracks: array`.

### `GET https://app-api.8slp.net/v1/users/{userId}/autopilotDetails`

- Evidence: Oct 15 flows 915, 919, 935; Oct 16 flows 173, 174, 186.
- Status: 200.
- Query: none.
- Request body: none recorded.
- Observed response fields: `calibrationStatus: object, canUseMitigationLevels: boolean, daysUntilCanUseLevels: number, hasActiveSubscription: boolean, isAutopilotActive: boolean, snoringMitigation: object, userMode: object`.

### `GET https://app-api.8slp.net/v1/users/{userId}/autopilotDetails/autopilotRecap`

- Evidence: Oct 15 flows 912, 981.
- Status: 200.
- Query: `day={day}`; `tz={tz}`.
- Request body: none recorded.
- Observed response fields: `deltas: array, elevationAdjustmentCount: number, elevationAdjustments: array, isProcessingComplete: boolean, pillowTemperatureAdjustmentCount: number, pillowTemperatureAdjustments: array, temperatureAdjustmentCount: number, temperatureAdjustments: array, temperatureSettingsUpdate: object, timestamp: string`.

### `GET https://app-api.8slp.net/v1/users/{userId}/bedtime/recommendation`

- Evidence: Oct 15 flows 887; Oct 16 flows 148.
- Status: 200.
- Query: none.
- Request body: none recorded.
- Observed response fields: `daysAnalyzed: number, recommendedBedtime: string, standardDeviation: string, topPerformingDays: number`.

### `GET https://app-api.8slp.net/v1/users/{userId}/challenges`

- Evidence: Oct 15 flows 890; Oct 16 flows 150.
- Status: 200.
- Query: none.
- Request body: none recorded.
- Observed response fields: `results: array`.

### `GET https://app-api.8slp.net/v1/users/{userId}/days/count`

- Evidence: Oct 15 flows 856, 922; Oct 16 flows 176.
- Status: 200.
- Query: none.
- Request body: none recorded.
- Observed response fields: `count: number`.

### `GET https://app-api.8slp.net/v1/users/{userId}/events`

- Evidence: Oct 15 flows 877; Oct 16 flows 125.
- Status: 101.
- Query: none.
- Request body: none recorded.
- Observed response fields: `No decoded JSON body`.

### `GET https://app-api.8slp.net/v1/users/{userId}/health-integrations/metadata`

- Evidence: Oct 15 flows 874, 943, 953, 964, 965, 974; Oct 16 flows 139, 191, 194, 222, 225.
- Status: 200.
- Query: none.
- Request body: none recorded.
- Observed response fields: `activityTags: array, from: string, healthSourceCount: number, healthSources: array, to: string, totalDataPoints: number`.

### `POST https://app-api.8slp.net/v1/users/{userId}/health-integrations/sources/{sourceId}`

- Evidence: Oct 15 flows 941, 950, 951, 952, 954, 956, 957, 958, 960, 962, 963; Oct 16 flows 190, 196, 200, 207, 210, 216, 217, 218, 219, 220, 221.
- Status: 200.
- Query: none.
- Request body: `{metrics: {HKCategoryTypeIdentifierLowCardioFitnessEvent: {checkpoint: string, value: array}, HKCategoryTypeIdentifierMenstrualFlow: {checkpoint: string, value: array}, HKCategoryTypeIdentifierSleepAnalysis: {checkpoint: string, value: array}, HKQuantityTypeIdentifierActiveEnergyBurned: {checkpoint: string, value: array}, HKQuantityTypeIdentifierAppleExerciseTime: {checkpoint: string, value: array}, HKQuantityTypeIdentifierAppleMoveTime: {checkpoint: string, value: array}, HKQuantityTypeIdentifierAppleStandTime: {checkpoint: string, value: array}, HKQuantityTypeIdentifierAtrialFibrillationBurden: {checkpoint: string, value: array}, HKQuantityTypeIdentifierBasalEnergyBurned: {checkpoint: string, value: array}, HKQuantityTypeIdentifierBloodGlucose: {checkpoint: string, value: array}, HKQuantityTypeIdentifierBloodPressureDiastolic: {checkpoint: string, value: array}, HKQuantityTypeIdentifierBloodPressureSystolic: {checkpoint: string, value: array}, HKQuantityTypeIdentifierBodyTemperature: {checkpoint: string, value: array}, HKQuantityTypeIdentifierCyclingCadence: {checkpoint: string, value: array}, HKQuantityTypeIdentifierCyclingFunctionalThresholdPower: {checkpoint: string, value: array}, HKQuantityTypeIdentifierCyclingPower: {checkpoint: string, value: array}, HKQuantityTypeIdentifierCyclingSpeed: {checkpoint: string, value: array}, HKQuantityTypeIdentifierDistanceCycling: {checkpoint: string, value: array}, HKQuantityTypeIdentifierDistanceDownhillSnowSports: {checkpoint: string, value: array}, HKQuantityTypeIdentifierDistanceSwimming: {checkpoint: string, value: array}, HKQuantityTypeIdentifierDistanceWalkingRunning: {checkpoint: string, value: array}, HKQuantityTypeIdentifierDistanceWheelchair: {checkpoint: string, value: array}, HKQuantityTypeIdentifierFlightsClimbed: {checkpoint: string, value: array}, HKQuantityTypeIdentifierHeartRate: {checkpoint: string, value: array}, HKQuantityTypeIdentifierHeartRateRecoveryOneMinute: {checkpoint: string, value: array}, HKQuantityTypeIdentifierHeartRateVariabilitySDNN: {checkpoint: string, value: array}, HKQuantityTypeIdentifierNikeFuel: {checkpoint: string, value: array}, HKQuantityTypeIdentifierPeripheralPerfusionIndex: {checkpoint: string, value: array}, HKQuantityTypeIdentifierPhysicalEffort: {checkpoint: string, value: array}, HKQuantityTypeIdentifierPushCount: {checkpoint: string, value: array}, HKQuantityTypeIdentifierRestingHeartRate: {checkpoint: string, value: array}, HKQuantityTypeIdentifierRunningPower: {checkpoint: string, value: array}, HKQuantityTypeIdentifierRunningSpeed: {checkpoint: string, value: array}, HKQuantityTypeIdentifierStepCount: {checkpoint: string, value: array}, HKQuantityTypeIdentifierSwimmingStrokeCount: {checkpoint: string, value: array}, HKQuantityTypeIdentifierUnderwaterDepth: {checkpoint: string, value: array}, HKQuantityTypeIdentifierWalkingHeartRateAverage: {checkpoint: string, value: array}, HKWorkoutTypeIdentifier: {checkpoint: string, value: array}, biologicalSex: {checkpoint: string, value: string}}}`.
- Request content type: `application/json`.
- Observed response fields: empty JSON object (`{}`).

### `GET https://app-api.8slp.net/v1/users/{userId}/health-integrations/sources/{sourceId}/checkpoints`

- Evidence: Oct 15 flows 905, 948; Oct 16 flows 155, 192.
- Status: 200.
- Query: none.
- Request body: none recorded.
- Observed response fields: `HKCategoryTypeIdentifierLowCardioFitnessEvent: string, HKCategoryTypeIdentifierMenstrualFlow: string, HKCategoryTypeIdentifierSleepAnalysis: string, HKQuantityTypeIdentifierActiveEnergyBurned: string, HKQuantityTypeIdentifierAppleExerciseTime: string, HKQuantityTypeIdentifierAppleMoveTime: string, HKQuantityTypeIdentifierAppleStandTime: string, HKQuantityTypeIdentifierAtrialFibrillationBurden: string, HKQuantityTypeIdentifierBasalEnergyBurned: string, HKQuantityTypeIdentifierBloodGlucose: string, HKQuantityTypeIdentifierBloodPressureDiastolic: string, HKQuantityTypeIdentifierBloodPressureSystolic: string, HKQuantityTypeIdentifierBodyTemperature: string, HKQuantityTypeIdentifierCyclingCadence: string, HKQuantityTypeIdentifierCyclingFunctionalThresholdPower: string, HKQuantityTypeIdentifierCyclingPower: string, HKQuantityTypeIdentifierCyclingSpeed: string, HKQuantityTypeIdentifierDistanceCycling: string, HKQuantityTypeIdentifierDistanceDownhillSnowSports: string, HKQuantityTypeIdentifierDistanceSwimming: string, HKQuantityTypeIdentifierDistanceWalkingRunning: string, HKQuantityTypeIdentifierDistanceWheelchair: string, HKQuantityTypeIdentifierFlightsClimbed: string, HKQuantityTypeIdentifierHeartRate: string, HKQuantityTypeIdentifierHeartRateRecoveryOneMinute: string, HKQuantityTypeIdentifierHeartRateVariabilitySDNN: string, HKQuantityTypeIdentifierNikeFuel: string, HKQuantityTypeIdentifierPeripheralPerfusionIndex: string, HKQuantityTypeIdentifierPhysicalEffort: string, HKQuantityTypeIdentifierPushCount: string, HKQuantityTypeIdentifierRestingHeartRate: string, HKQuantityTypeIdentifierRunningPower: string, HKQuantityTypeIdentifierRunningSpeed: string, HKQuantityTypeIdentifierStepCount: string, HKQuantityTypeIdentifierSwimmingStrokeCount: string, HKQuantityTypeIdentifierUnderwaterDepth: string, HKQuantityTypeIdentifierWalkingHeartRateAverage: string, HKWorkoutTypeIdentifier: string, biologicalSex: string`.

### `GET https://app-api.8slp.net/v1/users/{userId}/insights`

- Evidence: Oct 15 flows 983.
- Status: 200.
- Query: `date={date}`.
- Request body: none recorded.
- Observed response fields: `insights: array`.

### `GET https://app-api.8slp.net/v1/users/{userId}/level-suggestions`

- Evidence: Oct 15 flows 967.
- Status: 200.
- Query: none.
- Request body: none recorded.
- Observed response fields: `levelSuggestions: array`.

### `GET https://app-api.8slp.net/v1/users/{userId}/level-suggestions-mode`

- Evidence: Oct 15 flows 913; Oct 16 flows 172.
- Status: 200.
- Query: none.
- Request body: none recorded.
- Observed response fields: `autopilotEnabled: boolean, autopilotMode: string, autopilotOptions: object`.

### `GET https://app-api.8slp.net/v1/users/{userId}/llm-insights`

- Evidence: Oct 15 flows 878, 880, 881, 918, 930; Oct 16 flows 130, 131, 140, 204, 208.
- Status: 200.
- Query: `from={from}`; `to={to}`.
- Request body: none recorded.
- Observed response fields: `insights: object`.

### `GET https://app-api.8slp.net/v1/users/{userId}/llm-insights/settings`

- Evidence: Oct 15 flows 883; Oct 16 flows 141.
- Status: 200.
- Query: none.
- Request body: none recorded.
- Observed response fields: `length: string, priorityMetricsList: array, tone: string`.

### `GET https://app-api.8slp.net/v1/users/{userId}/metrics/aggregate`

- Evidence: Oct 15 flows 911, 931, 932, 983, 985; Oct 16 flows 171, 211, 212.
- Status: 200.
- Query: `metrics=sfs,sleep,deep,rem,hrv,snore | sleep_debt | sleepstarttime,wakeup`; `periods=week`; `to={to}`; `tz={tz}`.
- Request body: none recorded.
- Observed response fields: `periods: array`.

### `GET https://app-api.8slp.net/v1/users/{userId}/metrics/summary`

- Evidence: Oct 15 flows 978, 980.
- Status: 200.
- Query: `from={from}`; `metrics=avg_sqs,avg_sfs,sfs | sfs`; `periods=day`; `to={to}`; `tz={tz}`.
- Request body: none recorded.
- Observed response fields: `days: array`.

### `GET https://app-api.8slp.net/v1/users/{userId}/notifications`

- Evidence: Oct 15 flows 872; Oct 16 flows 138.
- Status: 200.
- Query: `active=true`; `limit=10`.
- Request body: none recorded.
- Observed response fields: `notifications: array, pagination: object`.

### `GET https://app-api.8slp.net/v1/users/{userId}/orders`

- Evidence: Oct 15 flows 862; Oct 16 flows 124.
- Status: 200.
- Query: none.
- Request body: none recorded.
- Observed response fields: `items: array, nextCursor: null`.

### `GET https://app-api.8slp.net/v1/users/{userId}/pregnancy-mode`

- Evidence: Oct 15 flows 916, 977; Oct 16 flows 165, 184, 201.
- Status: 200.
- Query: none.
- Request body: none recorded.
- Observed response fields: empty JSON object (`{}`).

### `GET https://app-api.8slp.net/v1/users/{userId}/release-features`

- Evidence: Oct 15 flows 853, 868; Oct 16 flows 128.
- Status: 200.
- Query: none.
- Request body: none recorded.
- Observed response fields: `addPodOnboarding: boolean, adjustableBase: boolean, allowOfflineModeV2: boolean, allowPatternSelection: boolean, autoPriming: string, autopilotModeToggleDeprecationDate: string, autopilotRecap: boolean, bleReportedWifiConnectivity: string, deviceAlarmSupport: object, deviceVibrationSupport: object, enableAmbientTemperature: boolean, enableAppStoreReviews: boolean, enableAppleHealthKitNotification: boolean, enableAutopilotRecapAdjustments: boolean, enableExerciseCognitionIOSV2: boolean, enableFiredrills: boolean, enableHealthConnect: boolean, enableHealthTier: boolean, enableHotFlashMode: boolean, enableJetLag: boolean, enableMetricPinningIOS: boolean, enableMetricsAggregateCache: boolean, enableMicroclimate: boolean, enableMicroclimateOnboarding: boolean, enableMorningSmsAnnouncement: boolean, enableMultipodV2: boolean, enableMultipodV3: boolean, enableNapModeIOS: boolean, enableNewTemperatureScreen: boolean, enableOfflineModeIOS: boolean, enablePillowOnboarding: boolean, enablePillowOnboardingIOS: boolean, enableProjectKR: boolean, enableSensorDisconnectWarning: boolean, enableSleepDebtIOS: boolean, enableTagsV2: boolean, eoy2023: boolean, eoy2024RecapStartTime: string, goingToBedTruthTags: string, hrvAlgo: string, hrvReleaseDate: string, inWarrantyLeakUrl: string, isRoutinesGatekeepingEnabled: boolean, manualAutopilotMigrationDate: string, mdwReferrals: string, minimumDaysBeforeNextAppStoreReview: number, minimumInstallDaysBeforeAppStoreReview: number, needsRevenueCatUserIdUpdate: boolean, newBLEOnboarding: boolean, outOfWarrantyLeakUrl: string, patternsSupportedOnAllDevices: boolean, pillowSetup: boolean, pod4Onboarding: boolean, pod4OnboardingMessageType: string, pod4PromoBanner: boolean, pod4WhiteGlove: boolean, presenceTruthTags: string, primingCancellation: boolean, rediscoverTTC: boolean, routinesMinimumAppVersion: string, rrReleaseDate: string, shopWebviewHost: string, shopWebviewPath: string, showAdjustableBaseTab: boolean, showHypnogramDetail: boolean, showInAppSurveys: boolean, showValentinesDay: boolean, sleepAlgo: string, smsEnrollment: string, snoreReport: boolean, supportedPatterns: array, supportedPatternsByDevice: object, tempAssist: string, zowieChatUrl: string`.

### `GET https://app-api.8slp.net/v1/users/{userId}/tags/recommendations`

- Evidence: Oct 15 flows 920; Oct 16 flows 205.
- Status: 200.
- Query: `date={date}`; `placement=morning_check_in`.
- Request body: none recorded.
- Observed response fields: `date: string, tags: array`.

### `GET https://app-api.8slp.net/v1/users/{userId}/temp-events`

- Evidence: Oct 15 flows 972, 973.
- Status: 200.
- Query: `from={from}`.
- Request body: none recorded.
- Observed response fields: `events: array, phases: array`.

### `GET https://app-api.8slp.net/v1/users/{userId}/temperature/all`

- Evidence: Oct 15 flows 900, 907; Oct 16 flows 157, 167.
- Status: 200.
- Query: none.
- Request body: none recorded.
- Observed response fields: `currentSchedule: object, devices: array, nextSchedule: object, nextScheduledTimestamp: string, schedules: array, temperatureSettings: array`.

### `GET https://app-api.8slp.net/v1/users/{userId}/temperature/hot-flash-mode`

- Evidence: Oct 15 flows 901, 908; Oct 16 flows 163, 166.
- Status: 200.
- Query: none.
- Request body: none recorded.
- Observed response fields: `enabled: boolean, hotFlashDuration: string, levelDelta: number`.

### `PUT https://app-api.8slp.net/v1/users/{userId}/temperature/pod`

- Evidence: Oct 15 flows 971, 976.
- Status: 200.
- Query: `ignoreDeviceErrors=false`.
- Request body: `{currentState: {type: string}}`.
- Request content type: `application/json`.
- Observed response fields: `currentSchedule: object, devices: array, nextSchedule: object, nextScheduledTimestamp: string, schedules: array, temperatureSettings: array`.

### `GET https://app-api.8slp.net/v1/users/{userId}/truth-tags`

- Evidence: Oct 15 flows 885; Oct 16 flows 144.
- Status: 200.
- Query: none.
- Request body: none recorded.
- Observed response fields: `tags: array`.

### `GET https://app-api.8slp.net/v2/users/{userId}/alarms`

- Evidence: Oct 15 flows 899, 902, 910; Oct 16 flows 156, 158, 168, 197.
- Status: 200.
- Query: none.
- Request body: none recorded.
- Observed response fields: `alarms: array, recommendedAlarm: object`.

### `GET https://app-api.8slp.net/v3/users/{userId}/subscriptions`

- Evidence: Oct 15 flows 871; Oct 16 flows 127.
- Status: 200.
- Query: none.
- Request body: none recorded.
- Observed response fields: `capabilities: array, churned: boolean, hasAccessToBasicFeatures: boolean, hasAccessToPremiumFeatures: boolean, hasBasic: boolean, isInGracePeriod: boolean, isUnpaidPremium: boolean, primarySubscription: object, subscriptions: array`.

### `GET https://auth-api.8slp.net/v1/grants`

- Evidence: Oct 16 flows 177.
- Status: 200.
- Query: none.
- Request body: none recorded.
- Observed response fields: `grants: array`.

### `POST https://auth-api.8slp.net/v1/tokens`

- Evidence: Oct 16 flows 121, 122.
- Status: 200.
- Query: none.
- Request body: `{client_id: string, client_secret: string, grant_type: string, refresh_token: string}`.
- Request content type: `application/json`.
- Observed response fields: `access_token: string, expires_in: number, refresh_token: string, scope: string, token_type: string`.

### `GET https://client-api.8slp.net/v1/devices/{deviceId}`

- Evidence: Oct 15 flows 866, 914; Oct 16 flows 133, 170.
- Status: 200.
- Query: none.
- Request body: none recorded.
- Observed response fields: `result: object`.

### `GET https://client-api.8slp.net/v1/users/{userId}`

- Evidence: Oct 15 flows 852, 861, 867, 909; Oct 16 flows 123, 126, 132, 169.
- Status: 200.
- Query: none.
- Request body: none recorded.
- Observed response fields: `user: object`.

### `PUT https://client-api.8slp.net/v1/users/{userId}`

- Evidence: Oct 15 flows 886; Oct 16 flows 146.
- Status: 200.
- Query: none.
- Request body: `{displaySettings: {clockSystem: string, locale: string}}`.
- Request content type: `application/json`.
- Observed response fields: `user: object`.

### `GET https://client-api.8slp.net/v1/users/{userId}/days/{date}/tags`

- Evidence: Oct 15 flows 906, 987; Oct 16 flows 206.
- Status: 200.
- Query: none.
- Request body: none recorded.
- Observed response fields: `tags: array`.

### `GET https://client-api.8slp.net/v1/users/{userId}/intervals`

- Evidence: Oct 15 flows 870; Oct 16 flows 136, 202, 224.
- Status: 200.
- Query: `next={next}`.
- Request body: none recorded.
- Observed response fields: `intervals: array, next: string`.

### `PUT https://client-api.8slp.net/v1/users/{userId}/intervals/{intervalId}`

- Evidence: Oct 16 flows 198.
- Status: 200.
- Query: none.
- Request body: `{edit: string}`.
- Request content type: `application/json`.
- Observed response fields: `device: object, deviceTimeAtUpdate: string, duration: number, edit: string, editDate: string, hrvAlgorithmVersion: string, id: string, presenceAlgorithmVersion: string, presenceEnd: string, score: number, sleepAlgorithmVersion: string, sleepEnd: string, sleepStart: string, snoring: array, stageSummary: object, stages: array, timeseries: object, timezone: string, ts: string`.

### `PUT https://client-api.8slp.net/v1/users/{userId}/push-targets/{pushTargetId}`

- Evidence: Oct 15 flows 875; Oct 16 flows 137.
- Status: 200.
- Query: none.
- Request body: `{deviceToken: string, platform: string}`.
- Request content type: `application/json`.
- Observed response fields: `No decoded JSON body`.

### `GET https://client-api.8slp.net/v1/users/{userId}/tags`

- Evidence: Oct 15 flows 869; Oct 16 flows 135.
- Status: 200.
- Query: `from={from}`; `to={to}`.
- Request body: none recorded.
- Observed response fields: `days: array`.

### `GET https://client-api.8slp.net/v1/users/{userId}/temperature`

- Evidence: Oct 15 flows 882, 896, 897; Oct 16 flows 145, 154, 162.
- Status: 200.
- Query: none.
- Request body: none recorded.
- Observed response fields: `currentLevel: number, currentSchedule: object, currentState: object, nextBedtimeDisplayWindow: object, nextSchedule: object, nextScheduledTimestamp: string, settings: object`.

### `GET https://client-api.8slp.net/v1/users/{userId}/trends`

- Evidence: Oct 15 flows 879, 888, 891, 903, 904, 979, 984; Oct 16 flows 142, 147, 160, 161, 164, 199, 203.
- Status: 200.
- Query: `consistent-read=false | true`; `from={from}`; `include-all-sessions=true`; `include-main=false`; `model-version=v3`; `to={to}`; `tz={tz}`.
- Request body: none recorded.
- Observed response fields: `avgDeepPercent: number, avgPresenceDuration: number, avgScore: number, avgSleepDuration: number, avgTnt: number, days: array, modelVersion: string, sfsCalculator: string`.

## Other recorded connections

All non-`8slp.net` flows in these files are CONNECT records, not decrypted HTTP endpoint requests. They reveal destination domains and network/device metadata, but do not establish the URL paths, request bodies, or API behavior of those services. Counts include repeated connection attempts. The S3 names below are observed infrastructure destinations, not evidence of readable backup objects.

| Destination | Oct 15 CONNECTs | Oct 16 CONNECTs |
| --- | ---: | ---: |
| `a.klaviyo.com` | 1 | 1 |
| `ab.chatgpt.com` | 0 | 1 |
| `api.apple-cloudkit.com` | 1 | 0 |
| `api.iterable.com` | 1 | 1 |
| `api.openai.com` | 0 | 1 |
| `api.whatsapp.net` | 1 | 0 |
| `api2.amplitude.com` | 1 | 1 |
| `api3.branch.io` | 1 | 1 |
| `b.6sc.co` | 1 | 0 |
| `bolt.dropbox.com` | 2 | 2 |
| `browser-intake-datadoghq.com` | 2 | 2 |
| `cdn.branch.io` | 1 | 1 |
| `chat.google.com` | 0 | 1 |
| `chat.openai.com` | 1 | 0 |
| `chatgpt.com` | 2 | 0 |
| `clientstream.launchdarkly.com` | 4 | 2 |
| `connectivitycheck.platform.hicloud.com` | 2 | 1 |
| `eight-backup-ap-southeast-2.s3.ap-southeast-2.amazonaws.com` | 2 | 3 |
| `eight-backup-us-east-1.s3.us-east-1.amazonaws.com` | 2 | 3 |
| `eight-status-page.s3.amazonaws.com` | 0 | 3 |
| `featureassets.org` | 1 | 1 |
| `gateway.icloud.com` | 1 | 0 |
| `ios.chat.openai.com` | 1 | 1 |
| `iphone-ld.apple.com` | 1 | 0 |
| `lp-push-server-1515.lastpass.com` | 1 | 2 |
| `mail.google.com` | 0 | 1 |
| `mobile.launchdarkly.com` | 1 | 1 |
| `o33249.ingest.us.sentry.io` | 1 | 0 |
| `o4507766157017088.ingest.us.sentry.io` | 1 | 1 |
| `ocsp2.apple.com` | 1 | 0 |
| `peoplestack-pa.clients6.google.com` | 2 | 0 |
| `play.google.com` | 2 | 1 |
| `prodregistryv2.org` | 0 | 1 |
| `proxyman.com` | 0 | 1 |
| `signaler-pa.clients6.google.com` | 2 | 2 |
| `sr-client-cfg.amplitude.com` | 1 | 1 |
| `ssl.gstatic.com` | 1 | 2 |
| `storage.googleapis.com` | 2 | 3 |
| `waa-pa.clients6.google.com` | 1 | 0 |
| `ws.chatgpt.com` | 3 | 1 |
| `ws3.qualified.com` | 1 | 0 |
| `www.cloudflare.com` | 1 | 1 |
| `www.googleapis.com` | 0 | 1 |
| `www.msftconnecttest.com` | 2 | 2 |
