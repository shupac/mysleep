# MySleep local web client

A browser UI for the **same Swift client, parser, and service** used by the iPhone
and Watch apps. Use it to distinguish authentication, transport, report schema,
and completion-selection failures without a phone proxy.

## Run on your Mac

From the repository root:

```sh
python3 web/server.py
```

Requires Python 3 and the Swift compiler included with Xcode. No third-party
packages are needed. The first launch compiles `native/Core/*.swift` together
with `web/Bridge.swift` into an ignored `web/.build` directory. Later launches
recompile when a Swift source changes. Restart the server after Swift edits;
reload the browser after HTML, CSS, or JavaScript edits.

Open **http://127.0.0.1:8787**. Sign in with your Eight Sleep account and time zone,
or select **Explore with demo data**. Use `--port 8788` if the port is occupied.
The printed URL must match the browser URL exactly (use `127.0.0.1`, not
`localhost`). The server only listens on the Mac's loopback interface.

The web session is independent of the native apps' Keychain. It keeps credentials,
tokens, and the latest report in process memory, without saving them to files,
browser storage, or the Keychain. **Disconnect** clears the web session. Ctrl-C
stops the server and the Swift process. All tabs on this local server share one
session; this is a development client for one user on a trusted Mac, not a hosted
or multi-user service. It cannot be opened directly from your phone.

## Diagnose a missing report

1. Connect and fetch the report. Nothing is sent to the Pod unless you explicitly
   use its controls.
2. Look at **Request diagnostics**. Each upstream request shows the host, redacted
   path, HTTP status, and elapsed time. Trends responses show model version, day
   field names, duration-field presence, and completion flags.
3. HTTP 401 suggests an authentication problem; 429 indicates rate limiting;
   5xx/network errors indicate an upstream/connection failure. HTTP 200 followed
   by a report error points to response validation or report selection.
4. **Copy diagnostics** copies structural metadata and safe error messages. It
   excludes passwords, authorization headers, tokens, raw response bodies, and
   report values. You can share this output for debugging. It still includes
   sleep dates and the fact that those dates have report data.

The shared service retains its one-minute retry cooldown after a report failure.
Rapid Refresh clicks during that interval can produce no network requests. A
cached report is labeled when a live refresh fails.

Pod controls require a successful status check within the previous minute.
Temperature changes enable heating/cooling. End sleep uses the existing off
command; it does not claim to explicitly start report generation. Demo mode
cannot control the real Pod.

## Verify

```sh
python3 -m unittest discover -s web/tests -v
CLANG_MODULE_CACHE_PATH=/private/tmp/eightsleep-swift-cache swiftc \
  -D WEB_TESTING -parse-as-library native/Core/*.swift web/Bridge.swift \
  web/tests/DiagnosticsTests.swift -o /private/tmp/eightsleep-web-diagnostics-tests
/private/tmp/eightsleep-web-diagnostics-tests
```

The HTTP handler and bridge tests use synthetic data and no live sign-in. The
diagnostics test checks identifier/token redaction and auth-body exclusion.
