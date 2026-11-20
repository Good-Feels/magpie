# Native regression catalog

Run from the Magpie repository on macOS with Xcode/Swift installed:

```sh
python3 scripts/test-regressions.py
```

The saved executable runs both the root suite and the dependent `ClipboardEngine` suite. SwiftPM does not run a dependency package's tests as part of the root suite. Each suite has a ten-minute acquisition/build/test limit; timeout stops its process group. All preexisting app and keeper tests remain. Results, exact commands, source hashes and product-only coverage summaries go in ignored `test-results/<UTC timestamp>/`. Preserve reviewed, sanitized release receipts under `Tests/evidence/`. Use `--help` for scratch/cache/output overrides.

Preconditions: exact committed `Package.resolved` files, network or populated dependency cache, a logged-in macOS session for the SwiftUI window and uniquely named **test** pasteboards, and permission to bind a Unix socket under `/private/tmp`. Run the saved test runner directly. It starts Magpie’s headless `--mcp-stdio` mode and hosts the production history list in an XCTest window. Fixture SQLite databases, defaults suites and pasteboards have generated test identities and are cleaned up. Tests reset and restore the **process-local volatile** UserDefaults registration domain, because it is shared across suite names. Run the engine XCTest class serially within its process.

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
| MAG-006-A | `testMAG006FullHistoryAccessAndRevocationOverStdio` | The built binary searches the entire database, finds a clip beyond the first 60 entries, pages results and long text, and reads images, rich text and file paths. Deletion, the access switch and relaunch are exercised through the app’s Unix listener. |
| MAG-006-B | `testMAG006ModernDiscoveryAndInvalidRequestsOverStdio` | The built binary answers modern discovery and tool listing with the required cache fields. Legacy tool listing still works, and invalid JSON, an unsupported version and an unknown write tool are rejected. |
| MAG-006-C | `scripts/test-mcp-clients.py`, Claude Desktop | A new Claude Desktop chat calls both read-only tools and receives the synthetic clip’s proof line. A fresh chat gets zero results after fixture deletion. |
| MAG-006-D | `scripts/test-mcp-clients.py`, ChatGPT in Chrome through Secure MCP Tunnel | ChatGPT calls both read-only tools through the private tunnel and receives the proof line. A fresh chat gets zero results after fixture deletion. |
| MAG-007-A | `testMAG007UnlimitedPagesReachOldClipsWithIdenticalTimestamps` | Unlimited keeps 1,207 clips. Pages preserve pin and timestamp ordering without gaps or duplicates. Search covers unloaded history and a deleted page boundary does not invalidate the next page. |
| MAG-007-B | `testMAG007PagedPreviewsPreserveClipActionsAndSharedIDs` | Bounded previews still find full-text matches. Full image, rich-text and legacy file payloads remain available by ID. Pinning, retention and clearing update which IDs exist. |
| MAG-007-C | `testMAG007SwiftUIScrollLoadsOlderPagesOnDemand` | The production SwiftUI list starts with 60 previews. Scrolling its AppKit document view loads all 1,207 synthetic text and image clips without duplicates. Thumbnail sizing, pin reorder and a rapid search change also pass. |
| MAG-008-A | `testMAG008ClaudeExtensionPackagesTheCurrentMagpiePath` | The generated extension includes a Claude manifest, stdio launcher and the exact Magpie executable path. Reconnecting from a new path replaces the cached installer. |
| MAG-008-B | `testMAG008ChatGPTPromptUsesActualPathAndPrivateSetup` | The generated Codex prompt preserves an executable path containing spaces and apostrophes. It uses a private tunnel and a synthetic verification clip. |
| MAG-008-C | `scripts/test-mcp-clients.py prepare-connection-app`, Claude Desktop | The production connection button opens the installer. The installed extension starts and a new chat reads the proof from beyond the search preview. Deleting the clip makes it disappear from a new search. |
| MAG-008-D | `scripts/test-mcp-clients.py verify-codex` | A fresh local Codex session runs the installed extension launcher, calls both tools, and returns the same proof. |
| MAG-008-E | `scripts/test-mcp-clients.py verify-connection-stdio` | The packaged launcher retrieves the sample and honors deletion in a host whose JavaScript streams are separate from its native standard input and output. |

The MCP tests use private temporary home directories, synthetic clips, and bounded subprocess and socket waits. Claude Desktop and ChatGPT account connections are separate from this regression runner.

### Live MCP client tests

Build the current Magpie executable and its dependencies using the saved SwiftPM regression runner. Start the fixture in a dedicated terminal using an unused short directory name. The fixture requires permission to bind a Unix socket and exits after 30 minutes. It runs only the production MCP protocol and local transport with synthetic sample clips. The build’s own `--mcp-stdio` mode handles client connections.

```sh
scripts/test-mcp-clients.py /private/tmp/magpie-qa-run serve --bridge .build/regression-root/debug/Magpie
```

For Claude Desktop, run `scripts/test-mcp-clients.py /private/tmp/magpie-qa-run claude-install` and quit and reopen Claude. For ChatGPT, use an isolated private tunnel and plugin according to the [MCP setup guide](MCP.md). Set the tunnel’s stdio command to the following, with your actual fixture and executable paths.

```sh
/usr/bin/env CFFIXED_USER_HOME=/private/tmp/magpie-qa-run /absolute/path/to/Magpie --mcp-stdio
```

Use the unique query printed for each client. In a fresh chat, ask that client to search for the exact query and call `get_clip` with the returned ID. The displayed proof line comes from beyond the search preview. Run the following assertions for each client, replacing `claude` with `chatgpt` for Chrome.

```sh
scripts/test-mcp-clients.py /private/tmp/magpie-qa-run check claude present
scripts/test-mcp-clients.py /private/tmp/magpie-qa-run delete claude
# Ask the same client to search for the same query in a fresh chat.
scripts/test-mcp-clients.py /private/tmp/magpie-qa-run check claude deleted
```

Allow up to two minutes for each chat. Record the fixture manifest, client versions, browser and pass, fail, blocked or unrun status. After testing, use `claude-remove` and restart Claude, disconnect the temporary ChatGPT plugin, and stop the tunnel client and fixture. Remove the temporary fixture directory after retaining sanitized evidence.

To cover the access switch in both clients, build the sandboxed app below and run `claude-install` with its fixture directory. In Claude Desktop, use **Developer → Reload MCP Configuration** and start a regular Claude chat. Point the dedicated private ChatGPT QA tunnel’s stdio command at the same fixture app executable with `--mcp-stdio`. With history access on, search for `magpie-button-fixture` and read the proof from the full result in each client. After turning access off, start a fresh chat in each client and repeat the search. Both tools should return the message asking you to turn on clipboard history access. When finished, run `claude-remove`, reload the config, and stop the test tunnel.

### Connection buttons

Use a scratch directory from a completed root regression build. Run the saved fixture builder and open the resulting **Magpie Connection QA** app. It uses the production settings and access code, a separate sandbox identity, and an isolated database with 72 newer entries ahead of the synthetic test clip. Use a Claude Desktop profile without a Magpie extension already installed. You need a signed-in local Codex CLI and Node.js for the installed launcher assertion.

```sh
scripts/test-mcp-clients.py /private/tmp/magpie-button-qa prepare-connection-app
```

Confirm **Allow access to clipboard history** starts off. Turn it on and wait for **Ready**. Open **Connect to ChatGPT** and confirm the sheet offers the setup prompt, then close it. Click **Connect to Claude** and approve the installation. Claude should list Magpie as enabled and make `search_clips` and `get_clip` available in a new chat. Ask Claude to search for `magpie-button-fixture`, fetch the returned ID and repeat the `Proof` line. Compare it with the fixture proof file below. Allow up to two minutes per chat.

Run the packaged launcher and Codex assertions before deleting the clip. The first simulates a desktop host with its own JavaScript streams. The second uses the files installed by Claude and configures the server only for that invocation.

```sh
scripts/test-mcp-clients.py /private/tmp/magpie-button-qa verify-connection-stdio present
scripts/test-mcp-clients.py /private/tmp/magpie-button-qa verify-codex \
  --launcher "$HOME/Library/Application Support/Claude/Claude Extensions/local.mcpb.good-feels-inc.magpie-clipboard/server.js" \
  --proof-file "$HOME/Library/Containers/com.goodfeels.magpie.qa/Data/tmp/magpie-fixture-proof.txt"
```

For a Codex check without installing the Claude extension, use the same command with `--bridge '/private/tmp/magpie-button-qa/Magpie Connection QA.app/Contents/MacOS/MagpieConnectionQA'` in place of `--launcher`.

Click **Delete Synthetic Clip** and confirm a fresh Claude chat gets zero results for the same query. Run `scripts/test-mcp-clients.py /private/tmp/magpie-button-qa verify-connection-stdio deleted`. Uninstall only the test Magpie extension, quit the QA app, and remove its temporary fixture directory. Record the runner and fixture hashes, client versions and results without retaining the proof text or any account data.

The focus test injects notifications and calls the same polling method as the timer. It verifies wiring and ordering without depending on XCTest run-loop scheduling; it is not an OS focus/UI end-to-end test. Source tracking is conservative: legitimate copies immediately after leaving an excluded app may be skipped for one polling interval. It cannot authenticate background writers or unmarked origins.

SQLite itself may regenerate invalid WAL/SHM sidecars while opening a corrupt database. MAG-001 therefore separates real-main-file preservation from the application's outer startup behavior on untouched synthetic sidecars. This avoids treating SQLite-managed housekeeping as Magpie's old unconditional reset.

## Dependency acquisition recovery

Keep dependency versions fixed. If SwiftPM stalls on a Sparkle binary artifact, use the exact official URL and checksum declared in the pinned Sparkle `Package.swift`; fetch the archive with a bounded client, verify SHA-256, and retain provenance before seeding only a scratch cache. Do not change the app's manifest to a different Sparkle version or a custom local dependency. November 17's receipt records the verified 2.9.0 archive and the SwiftPM 6.4 workspace-artifact metadata used for the local recovery.

## Release boundary

Run both complete native suites before release. A signed/notarized DMG and appcast validation do not establish an installed Sparkle upgrade. Follow `RELEASE.md` for that separate final release and installed-hop check. Never install over `/Applications/Magpie.app`; never run a candidate with the production bundle identity against live clipboard/history for a test.
