# MySleep

A personal SwiftUI app for iPhone and Apple Watch. Both devices connect directly
to Eight Sleep. No backend, cloud resources, subscription, API keys, database, or
third-party Swift dependencies are needed.

Open **`native/mysleep.xcodeproj`**. It contains the `MySleep` iPhone target
and `MySleepWatch` independent Watch target. Minimum iOS 17 / watchOS 10.

## What it does

- Shows the latest completed sleep period from the last 14 days.
- Displays score, sleep duration, deep/REM/light durations and percentages,
  sleeping heart rate, HRV, respiratory rate, awake time, snoring, and sleep timing.
- Refreshes on opening/activation; pull to refresh on iPhone or tap Refresh on Watch to bypass the
  five-minute report cache. Provider errors impose a one-minute retry cooldown.
- Saves the latest report for offline viewing; labels cached, unavailable, and
  old data. Reports are marked stale after 15 minutes without an update or when
  the sleep ended more than 36 hours ago.
- Exposes **Get Latest Sleep Report** as an App Intent on both platforms. It
  fetches a report and returns concise spoken text without opening the interface.
- Stores login credentials and OAuth tokens in each device's Keychain, accessible
  after the first unlock following a restart, including while subsequently locked.
  Credentials are not synchronized or migrated to another device.

Includes a Watch sleep-score complication. No performance windows, historical
charts, or background polling are implemented.

## Control your Pod

The home screen changes with the bed state. When the bed is on, it shows the
current Fahrenheit setting, a temperature adjustment, and **End sleep**. It hides
the sleep report until sleep ends. There is no separate Pod controls screen and
no Turn on action in the native app.

- Choose **55°F to 110°F** in **1°F steps**, then tap **Apply temperature**.
  Fahrenheit uses pyEight's nonlinear lookup table. The reported setting is a
  setpoint, not measured water temperature. Applying enables smart mode and
  writes the level.
- Tap **End sleep**, then confirm **End sleep and turn off bed**. It first sends
  the existing profile-scoped off command, then stops the newest incomplete
  interval from the last 36 hours (`edit: stop`). If no interval exists, it still
  turns heating/cooling off. Partial failures are reported explicitly.
- Successful End sleep forces a fresh report fetch and displays the latest
  completed report. The provider may still be processing the newest night; the
  report's date identifies what is available. Saved fallback reports remain
  labeled. The app does not poll in the background.
- When the bed is off, the home screen shows the latest report directly.

Refresh uses a **button on Apple Watch** and **pull to refresh on iPhone**. It
checks live power first, then fetches a report when applicable. Temperature
controls require status younger than a minute; stale or unconfirmed states
require refresh before another command. Unknown/error states expose no bed
commands, while allowing the latest available report to remain accessible.
Commands are scoped to the saved account's profile and follow its provider bed
assignment. No commands are queued offline, and writes aren't automatically
replayed after ambiguous network/server errors. See the
[home state diagram](docs/pod-control-state-machine.md) for transitions.

## Install on your devices

1. Open `native/mysleep.xcodeproj` in Xcode 26.3 or newer (the locally tested
   version). No package installation or project generation is required.
2. In Xcode Settings → Accounts, add your Apple account. Under **Signing &
   Capabilities**, select your development team for the iPhone, Watch, and
   **MySleepComplication** targets.
3. The project uses `com.meetshu.mysleep` for the iPhone and
   `com.meetshu.mysleep.watchkitapp` for the Watch. If you need another identifier,
   select the **project** (not a target) → **Build Settings** → **User-Defined**
   and change **SLEEP_BUNDLE_IDENTIFIER** for Debug and Release. All target
   identifiers and the Watch companion reference derive from this one setting.
   **SLEEP_APP_NAME** controls the displayed name, currently **MySleep**. Keep the
   target-level bundle identifier fields as expressions rather than overriding
   them individually.
4. Connect/unlock your iPhone, trust the Mac, and enable Developer Mode if Xcode
   requests it. Select the **MySleep** scheme and your iPhone, then Run.
5. Pair your Watch to that iPhone and enable Developer Mode as prompted. Select
   **MySleepWatch** and your paired physical Watch, then Run. You may need to
   enable the app in the iPhone Watch app's list of available apps.
6. Open **MySleep → Settings** on each device. Enter your Eight Sleep email and
   password, confirm the IANA time zone (e.g. `America/Los_Angeles`), and tap
   **Save and connect**. Passwords are never embedded in the build or logged.
7. Open the Watch app once and verify a report. Then test with your iPhone out of
   reach while the Watch has Wi-Fi or cellular connectivity.

**Each device signs in separately.** The apps do not transfer passwords between
phone and Watch. A paired iPhone keyboard may make entering the Watch password
more convenient, but normal fetching and Siri execution on the Watch do not
require the phone. Sign-out clears credentials, tokens, and the cached report on
that device only; it does not revoke the provider token or sign out the other
app.

No App Store distribution is necessary. Development signing still requires an
Apple account and compatible devices. A free Personal Team has provisioning
restrictions and short-lived profiles; Xcode determines eligibility for your
hardware/account. Reinstall/re-sign if its development profile expires. A paid
Developer Program membership is optional for this project but can simplify
longer-term device provisioning.

## Watch face sleep score

Rebuild and install the Watch app, open it once, and refresh your sleep report.
Touch and hold your Watch face → **Edit** → **Complications**, choose a slot, and
select **MySleep → Sleep Score**. Circular, corner, inline, and rectangular slots
are supported; the rectangular widget also appears in the Smart Stack.
Tap the complication to open MySleep and refresh.

The complication shows the latest score fetched **on the Watch**, including
reports fetched through Siri. It does not poll Eight Sleep in the background.
A clock icon / **Saved** label marks data after 15 minutes without a fetch, when
the sleep ended more than 36 hours ago, or after an offline fallback. Larger slots
also show the sleep date. Missing scores show **—**. Account changes and sign-out
clear the shared score. WatchOS controls when timeline reloads appear.

The Watch and complication targets share the App Group
`group.$(SLEEP_BUNDLE_IDENTIFIER).watch`, with only the score and dates stored
there. Both targets need provisioning with this App Group enabled in Xcode's
**Signing & Capabilities**. The complication does not receive login credentials.
Real-device signing, adding the complication, and privacy behavior while locked
or in Always On still need verification on your Watch.

## Siri: “Hey Siri, how did I sleep?”

1. Install and sign in to MySleep on the device where you will use Siri.
2. On iPhone, open **Shortcuts**, tap **+**, and add the app action
   **MySleep → Get Latest Sleep Report** (search for the action by name).
3. Name the shortcut **How did I sleep?**
4. The action already returns a Siri dialog and a text value. For an explicit
   spoken result, add **Speak Text**, using the action's returned text. Do not add
   another network request or put credentials in the shortcut. If your Siri
   version speaks both the action dialog and Speak Text, remove Speak Text.
5. In the shortcut details, enable **Show on Apple Watch**. Make sure the native
   Watch app is installed and separately signed in, then run the shortcut once
   from the Watch's Shortcuts app.
6. Say **“Hey Siri, how did I sleep?”** on your Watch or iPhone. If Siri routes
   the generic phrase to another sleep feature, invoke the shortcut explicitly,
   or use the built-in phrase **“How did I sleep with MySleep?”**.

The same intent is compiled into both native targets and uses the local device's
Keychain and direct API client. The device must be unlocked/authenticated to read
private sleep data. If offline with a saved report, Siri explicitly says the
report is older or cached. If no saved report exists, Siri explains the error.
Siri phrase recognition and cross-device shortcut routing require a physical
paired-device check; they cannot be established by a simulator build alone.

To use **“Hey Siri, End sleep”**, create a shortcut named **End sleep** with the
**MySleep → End Sleep** action. Enable **Show on Apple Watch** in its details
to use it there. Use **“Hey Siri, done sleeping with MySleep”** without creating a personal shortcut.
The earlier **“End sleep with MySleep”** and **“End sleep in MySleep”** phrases
also remain available.
The End Sleep action can run while the device is locked after its first unlock
following a restart. It uses the same profile-scoped combined bed-off and
interval-stop operation as the home screen. Failures are returned to Siri instead of
announcing success. The next report request bypasses the five-minute cache and
uses `consistent-read=true`, matching the official app after stopping sleep.

### HomePod: “Hey Siri, finish sleeping”

Create a personal shortcut named **Finish sleeping** containing **MySleep → End
Sleep**. In Home → Home Settings → your name, enable Recognize My Voice and
Personal Content/Personal Requests for the bedroom HomePod. The iPhone must be
powered on and connected to the same Wi-Fi network; it can be in another room.
HomePod routes the shortcut to the phone rather than storing Eight Sleep login
credentials itself.

**After installing this update, unlock the iPhone and open MySleep once.** This
migrates existing Keychain items in place to
`AfterFirstUnlockThisDeviceOnly`, preserving the saved account and tokens. After
a restart, unlock the iPhone once again; it can then stay locked. New sign-ins and
token renewals use the same device-only accessibility class. No iCloud Keychain
sync or backup transfer is enabled.

Only End Sleep uses `alwaysAllowed`; reading sleep reports through Siri still
requires local device authentication. Cached reports keep complete file
protection. HomePod Personal Requests and voice recognition remain Apple's
separate settings and may impose their own authentication requirements. Enabling
the app action while locked does not bypass those HomePod settings. A physical
HomePod test is required to confirm routing and behavior for your configuration.

## Local verification

For a local browser client with request diagnostics, run `python3 web/server.py`
and open **http://127.0.0.1:8787**. It uses the native Swift client and parser,
keeps its session in memory, and includes a demo mode. See
[web client instructions](web/README.md) for debugging and checks.

```sh
swift test --package-path native
xcodebuild -project native/mysleep.xcodeproj -scheme MySleepWatch \
  -destination 'generic/platform=watchOS Simulator' \
  -derivedDataPath native/.build-watch CODE_SIGNING_ALLOWED=NO build
xcodebuild -project native/mysleep.xcodeproj -scheme MySleep \
  -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath native/.build-ios CODE_SIGNING_ALLOWED=NO build
```

Unit tests use synthetic fixtures and a scripted HTTP transport. They never call
Eight Sleep or write actual account credentials to Keychain. To preview fixture
data in either app, add `--demo` to a **Debug** scheme's launch arguments. Add
`--demo-stale` for the cached/offline state or `--demo-empty` for onboarding. Add `--demo-controls` together with `--demo` to
preview Pod controls directly; demo commands never reach a real Pod. Demo
mode performs no API calls. Release builds ignore these arguments.

The Xcode project is checked in. `python3 scripts/generate-project.py` regenerates
it after source-file additions; it preserves the current development team, signing settings, shared app name,
and shared bundle identifier.

## API scope and metric limitations

This started as a Swift port of the existing eightctl API integration. The report
adapter also supports the v3 schema observed in an official-app capture on
2026-10-15. See [provenance](docs/provenance.md) and the prior
[API notes](docs/eightctl-api-notes.md).
The [capture reference](docs/captured-api-reference.md) inventories the observed
requests; the [privacy review](docs/capture-privacy-review.md) explains why raw
recordings stay excluded from Git.

- Login uses the existing OAuth password grant. Tokens are reused until their
  expiry minus 60 seconds. Expiry/rejection triggers another password login;
  eightctl does not implement a refresh-token grant.
- Sleep data comes from the existing `/users/{id}/trends` endpoint with the saved
  timezone and `model-version=v3`, matching the captured official-app request.
  Only the authenticated user's data is requested.
- A complete report requires an ended presence window and positive sleep
  duration (`sleepDurationSeconds` or v3 `sleepDuration`). Rows marked incomplete
  and ongoing/future rows are skipped, and completed rows are sorted by end
  time. The aggregate day may contain multiple sessions or naps; this app does not
  claim to identify the main overnight session separately.
- The report shows three groups: Overall (sleep score), Biometrics (HR and
  HRV milliseconds), and Duration (total sleep, Deep, REM, bedtime, wake time).
  Stage durations must reconcile with total sleep before display. Missing values
  display `—`. Presence-only timestamps remain labeled In bed / Out of bed.
- The captured v3 schema supplies `deepDuration`, `remDuration`, `lightDuration`,
  and `snoreDuration` in seconds. Raw HRV, heart rate, and respiratory rate come
  from `sleepQualityScore.<metric>.current` only when `available` is true.
  The adapter also recognizes optional raw `hrvMs`/`hrv`, session HRV samples,
  and `snoringDurationSeconds` if supplied.
  Missing raw HRV displays a separately labeled **HRV score** when available;
  snoring otherwise displays `—`. It never converts an HRV score to milliseconds.
- Awake time uses a verified aggregate `awake` stage or the sum of v3 session
  `stageSummary.awakeDuration` values. Session sleep totals must match the day,
  and sleep + awake + out durations must reconcile with session totals. Time out
  of bed is excluded; awake duration may include pre-sleep/post-sleep intervals.
- Valid `sleepStart`/`sleepEnd` fields, if supplied, show Bedtime/Wake time. The
  established fallback is `presenceStart`/`presenceEnd`, honestly labeled **In
  bed / Out of bed**. Those aren't claimed to be exact sleep-onset/wake times.
- All sample data is synthetic. A successful local build doesn't verify current
  Eight Sleep compatibility or availability of every requested measurement.

## Structure

- `native/Core`: direct API client, protected persistence, report adapter, summary,
  and the actor coordinating UI and Siri requests.
- `native/App`: shared adaptive SwiftUI interface and native App Intent.
- `native/Tests`: authentication, parsing, persistence, concurrency, and summary tests.
- `native/Fixtures`: synthetic Debug preview data, never used by the live client.

The earlier Worker and Watch-to-Worker prototypes were retired when the design
changed. There is no backend to configure or deploy.

The iPhone UI suite is also included in the `MySleep` scheme. It checks the
report, Settings, cached/offline labeling, and onboarding with synthetic data:

```sh
xcodebuild -project native/mysleep.xcodeproj -scheme MySleep \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.1' \
  -derivedDataPath native/.build-ios CODE_SIGNING_ALLOWED=NO test
```

Choose an installed simulator from `xcrun simctl list devices available` if that
runtime is not installed. The Watch preview in `docs/watch-preview.png` and the
iPhone preview in `docs/iphone-preview.png` show synthetic data, not your account.
