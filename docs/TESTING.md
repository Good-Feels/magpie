# Native regression catalog

Run from the Magpie repository on macOS with Xcode/Swift installed:

```sh
python3 scripts/test-regressions.py
```

The saved executable runs both the root suite and the dependent `ClipboardEngine` suite. SwiftPM does not run a dependency package's tests as part of the root suite. Each suite has a ten-minute acquisition/build/test limit; timeout stops its process group. All preexisting app and keeper tests remain. Results, exact commands, source hashes and product-only coverage summaries go in ignored `test-results/<UTC timestamp>/`. Preserve reviewed, sanitized release receipts under `Tests/evidence/`. Use `--help` for scratch/cache/output overrides.

Preconditions: exact committed `Package.resolved` files, network or populated dependency cache, access to macOS's pasteboard server for uniquely named **test** pasteboards, and permission to bind a Unix socket under `/private/tmp`. Never use `run.sh` to test this release: it launches an app against real state. The tests start only Magpie’s headless `--mcp-stdio` mode. They do not start the graphical app, read `NSPasteboard.general`, read production history, register login items, send analytics or install an app. SQLite databases, defaults suites and pasteboards have generated test identities and are cleaned up. Tests reset and restore the **process-local volatile** UserDefaults registration domain, because it is shared across suite names. Do not run this engine XCTest class in parallel within one process.

## Scenarios and expected results

| ID | Executable coverage | Expected result |
|---|---|---|
| MAG-001-A | `testMAG001CorruptDatabaseSurvivesRepeatedRealOpenFailures` | Production `DatabaseStartup.open`, used by AppState, returns failure for a real corrupt temp SQLite DB; original DB bytes survive repeated attempts; unknown history remains unlimited |
| MAG-001-B | `testMAG001StartupFailureBeforeSQLitePreservesDatabaseAndSidecars` | Arbitrary pre-open failure leaves all synthetic DB/WAL/SHM bytes intact; no empty-success recovery |
| MAG-001-C | `testMAG001ReopenPreservesPinnedHistoryAndPermissions` | Valid history/pins survive reopening; owner-only DB permissions retained |
| MAG-002-A | `testMAG002EverySensitiveMarkerRejectsAllRepresentations`, `testMAG002ConcealedMarkerOnLaterItemRejectsWholeSelection` | Concealed/transient/generated/password-manager markers reject text, image, RTF and files, including a marker on a later item |
| MAG-002-B | `testMAG002ExcludedSourceToEditorWithinPollingIntervalIsRejected`, `testMAG002BriefExcludedAppBetweenPollsIsRemembered`, `testMAG002MonitorActivationNotificationsReachCaptureGate` | Excluded-app-to-editor transitions and brief intervening activations are rejected through the production notification observer/poll/capture policy; evidence is recorded synchronously; the next clean interval can capture |
| MAG-002-C | `testMAG002SourceHintCannotOverrideObservedExclusion`, `testMAG002GenerationChangeDuringLazyPayloadIsRejected` | Untrusted origin hints cannot allow excluded content; a clipboard generation change during lazy decoding aborts capture |
| MAG-002-D | `testMAG002AllowedTextAndRichTextStillCaptureAndRestore` | Ordinary allowed text and RTF remain usable |
| MAG-003-A | `testMAG003FreshInstallUses200AndPreservesPins` | 205 unpinned writes retain the newest 200, plus a protected pin |
| MAG-003-B | `testMAG003LegacyMissingPreferencePreservesAllHistoryAsUnlimited` | Existing no-key history receives explicit unlimited before default registration; 205 legacy rows and the next clip survive |
| MAG-003-C | `testMAG003ExplicitUnlimitedAndFinitePreferencesAreRespected` | Explicit zero and finite limits remain effective; invalid negative values fall back to 200 |
| MAG-004-A | `testMAG004TwoFilesPersistReopenAndRestoreInOrder` | Full file selection survives GRDB save, reopen and pasteboard restoration in order |
| MAG-004-B | `testMAG004ChangedSecondFileAndOrderAreNotDeduplicated`, `testFullPayloadDedupPreservesFormattingAndContentType` | Full payload identity controls dedup; changed second file/order/format survives; exact consecutive duplicates are skipped |
| MAG-004-C | `testMAG004LegacySingleFileAndMalformedGroupFallback`, `testMAG004V1MigrationPreservesLegacyPinnedSingleFile` | Nullable v2 migration preserves v1 rows/pins; malformed grouped metadata falls back to the legacy single path |
| MAG-004-D | `testMAG004InvalidPayloadDoesNotEraseDestination` | Empty restored payload leaves the destination intact; a non-file URL advertised as a file is rejected |
| MAG-006-A | `testMAG006SharedTextCanBeReadAndRevokedOverStdio` | The built binary initializes, lists two read-only tools, and searches and fetches only explicitly shared synthetic text via the app’s Unix listener. Revocation, deletion and disabling remove access. |
| MAG-006-B | `testMAG006ModernDiscoveryAndInvalidRequestsOverStdio` | The built binary answers modern discovery, rejects invalid JSON, an unsupported version and an unknown write tool. |
| MAG-006-C | `scripts/test-mcp-clients.py`, Claude Desktop | A new Claude Desktop chat calls both read-only tools and receives the synthetic clip’s proof line. A fresh chat gets zero results after revocation. |
| MAG-006-D | `scripts/test-mcp-clients.py`, ChatGPT in Chrome through Secure MCP Tunnel | ChatGPT calls both read-only tools through the private tunnel and receives the proof line. A fresh chat gets zero results after revocation. |

The MCP tests use private temporary home directories, synthetic clips, and bounded subprocess and socket waits. Claude Desktop and ChatGPT account connections are separate from this regression runner.

### Live MCP client tests

Build the current Magpie executable with SwiftPM. Start the fixture in a dedicated terminal using an unused short directory name. The fixture requires permission to bind a Unix socket and exits after 30 minutes. It runs only the production MCP protocol and local transport with synthetic sample clips. The build’s own `--mcp-stdio` mode handles client connections.

```sh
scripts/test-mcp-clients.py /private/tmp/magpie-qa-run serve --bridge .build/debug/Magpie
```

For Claude Desktop, run `scripts/test-mcp-clients.py /private/tmp/magpie-qa-run claude-install` and quit and reopen Claude. For ChatGPT, use an isolated private tunnel and plugin according to the [MCP setup guide](MCP.md). Set the tunnel’s stdio command to the following, with your actual fixture and executable paths.

```sh
/usr/bin/env CFFIXED_USER_HOME=/private/tmp/magpie-qa-run /absolute/path/to/Magpie --mcp-stdio
```

Use the unique query printed for each client. In a fresh chat, ask that client to search for the exact query and call `get_shared_clip` with the returned ID. The displayed proof line comes from beyond the search preview. Run the following assertions for each client, replacing `claude` with `chatgpt` for Chrome.

```sh
scripts/test-mcp-clients.py /private/tmp/magpie-qa-run check claude shared
scripts/test-mcp-clients.py /private/tmp/magpie-qa-run revoke claude
# Ask the same client to search for the same query in a fresh chat.
scripts/test-mcp-clients.py /private/tmp/magpie-qa-run check claude revoked
```

Allow up to two minutes for each chat. Record the fixture manifest, client versions, browser and pass, fail, blocked or unrun status. After testing, use `claude-remove` and restart Claude, disconnect the temporary ChatGPT plugin, and stop the tunnel client and fixture. Remove the temporary fixture directory after retaining sanitized evidence.

The focus test injects notifications and calls the same polling method as the timer. It verifies wiring and ordering without depending on XCTest run-loop scheduling; it is not an OS focus/UI end-to-end test. Source tracking is conservative: legitimate copies immediately after leaving an excluded app may be skipped for one polling interval. It cannot authenticate background writers or unmarked origins.

SQLite itself may regenerate invalid WAL/SHM sidecars while opening a corrupt database. MAG-001 therefore separates real-main-file preservation from the application's outer startup behavior on untouched synthetic sidecars. This avoids treating SQLite-managed housekeeping as Magpie's old unconditional reset.

## Dependency acquisition recovery

Keep dependency versions fixed. If SwiftPM stalls on a Sparkle binary artifact, use the exact official URL and checksum declared in the pinned Sparkle `Package.swift`; fetch the archive with a bounded client, verify SHA-256, and retain provenance before seeding only a scratch cache. Do not change the app's manifest to a different Sparkle version or a custom local dependency. November 17's receipt records the verified 2.9.0 archive and the SwiftPM 6.4 workspace-artifact metadata used for the local recovery.

## Release boundary

Run both complete native suites before release. A signed/notarized DMG and appcast validation do not establish an installed Sparkle upgrade. Follow `RELEASE.md` for that separate final release and installed-hop check. Never install over `/Applications/Magpie.app`; never run a candidate with the production bundle identity against live clipboard/history for a test.
