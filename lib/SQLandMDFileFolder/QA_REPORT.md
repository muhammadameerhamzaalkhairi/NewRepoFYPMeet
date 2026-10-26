# LiveMeet QA Report

Review date: 25 October 2026 (Asia/Karachi)  
Project: `D:/7th Semester/Flutter/Project/livemeet`  
Overall verdict: **Not ready** for phone sign-off. The main workflow is implemented, but the Live screen can overflow with the keyboard or a short viewport, and switching tabs during an unfinished mutation can leave stale data and bypass the screen's busy guard. A hard rule about keeping non-UI logic outside screens is also unmet.

## Scope and evidence

- Read the complete 365-line `lib/SQLandMDFileFolder/livemeet_codex_spec.md` before reviewing the Dart implementation.
- Read **all 17 Dart files in lib, 2,423 lines**, including login, widgets, services, models and utilities. Inventory is below.
- Reviewed spec sections 2, 6–10 and every item in section 12. Compared existing tracked screens/widgets with local Git HEAD for visual changes; HEAD is a source baseline, not a screenshot baseline.
- Read dependency and lint configuration. No packages were installed, no SQL was run, and no Supabase connection or mutation was performed.
- Did not read `test/widget_test.dart` and did not run `flutter test`. No application was launched and no device behavior is claimed as observed.
- Existing worktree changes predated this review. Suggested fixes below are recommendations only; none were applied.

## Flutter analyze

Working directory: project root above.

Successful command:

```text
flutter --no-version-check analyze --no-pub lib
Analyzing lib...
No issues found! (ran in 3.2s)
Exit code: 0
```

This runs Flutter analysis on the requested production code. `lib` deliberately excludes the ignored test file; `--no-pub` avoids dependency resolution and associated project-file changes; `--no-version-check` avoids the update check. A first attempt, `flutter analyze --no-pub`, produced no analyzer output because the sandbox could not acquire the Flutter SDK bootstrap cache lock. That attempt was stopped before analysis; the successful scoped command above was then run with SDK-cache access. The clean result is for **lib**, not the entire project, and does not establish runtime layout or database correctness.

## Findings

**Total: 5 — Critical: 0; High: 1; Medium: 2; Low: 2.**

Line numbers refer to the reviewed working-tree files. Layout/race findings describe source-supported failure conditions; they have not been reproduced on a phone.

| ID | Severity | File and line | Problem and impact | Recommended fix (not applied) |
|---|---|---|---|---|
| QA-01 | High | `lib/screens/live_screen.dart:317–350`, especially `:319` and `:350`; empty/error content at `:241–274`. Similar empty/error constraint at `lib/screens/meetings_screen.dart:167–194`. | **Rigid vertical layout can overflow or leave no usable results area.** Live places its date, 38px title, optional paused line, search field, filter strip and gaps in a non-scrolling Column above an Expanded list, with 78px vertical padding. The Scaffold normally reduces its body when the search keyboard opens. On a short phone/landscape viewport, or with enlarged text, those non-flex children can exceed the available height: Expanded cannot rescue the header. Empty/error views also force a centered, non-scrolling Column into exactly the remaining list height; a short viewport or long server error can overflow that Column. This blocks a central search workflow and conflicts with the narrow-screen/long-text requirement (§10). | Make the header and results work within keyboard-reduced height, for example using a scrollable/sliver composition while keeping data lists built lazily and preserving the existing styling. Make empty/error content scroll when it cannot fit. Check a 320px-wide short phone, landscape, paused state, open keyboard, large text and long errors. |
| QA-02 | Medium | `lib/screens/main_screen.dart:23–32,40–45`; `lib/screens/dashboard_screen.dart:92–115,217–223`; equivalent completion paths in `lib/screens/live_screen.dart:146–165` and `lib/screens/meetings_screen.dart:86–115`. | **Navigation can discard the busy flag and the successful reload while an RPC is pending.** Busy belongs to the screen, but bottom-tab navigation remains enabled and replaces that screen. Example: confirm End meeting on Home over a slow connection, then immediately open Live. Live can fetch the still-running meeting before the end RPC commits. When the old Home request completes, its mounted guard correctly returns, so its reload never runs and the visible Live screen retains the old state until refresh/tab revisit. Returning to a fresh copy of the originating screen also resets busy and can allow another request while the original is unfinished. Database constraints may reject conflicting requests; the UI still loses operation coordination. | Share an operation-in-progress flag with MainScreen through constructor callbacks and prevent tab/in-screen navigation until the mutation and reload finish, or notify MainScreen on completion and explicitly refetch the current screen. Keep setState/callbacks as required; do not remove mounted guards or introduce a state package. |
| QA-03 | Medium | `lib/screens/import_screen.dart:33–61,91–166`. | **Non-UI Excel parsing, validation and grouping remain embedded in a 345-line screen.** Cell conversion, workbook decoding, title extraction, row validation, group numbering and summary calculation live in ImportScreen rather than services/models/utils. The parser is understandable and generally matches §8.2, but this directly misses hard rule §2.7 and places substantial reusable logic in the UI state. | Extract the workbook/row parser and its structured result into a plain service/model or utility. Keep file picking, busy state, error display and navigation in the screen. Preserve all eight payload keys and current visual layout. |
| QA-04 | Low | `lib/screens/login_screen.dart:86–95`; `lib/widgets/Button.dart:21,29`. | **Sign-in never receives a disabled state while authentication is loading.** The label becomes “Signing in...” but Button defaults to enabled, so it remains visually active and tappable. The `if (isLoading) return` guard does prevent duplicate sign-in requests; this is a disabled-state/feedback defect, not a claim of unguarded authentication calls. It already exists in the Git baseline. | Pass `enabled: !isLoading` to the sign-in Button while retaining the existing handler guard and mounted checks. |
| QA-05 | Low | `lib/widgets/Button.dart:9,19,43` and its caller `lib/screens/main_screen.dart:31`; `lib/widgets/TextBox.dart:10,18,24–27`. | **Two exposed widget options are silently ignored.** Button stores `foreColor` but computes text color solely from `color`; TextBox stores `keyboardType` but does not forward it to TextFormField. These are ineffective configuration fields rather than analyzer-reported unused locals. Both behaviors predate the current feature changes. Current navigation remains readable because Button derives black text on its white/lime backgrounds; blindly honoring the currently passed white foreColor would alter that behavior. | Remove the unused foreColor argument/callers if no configurable foreground is intended, or implement it and correct callers so the current black-on-white/lime design stays intact. Forward keyboardType to TextFormField if that API is retained. No extra package is needed. |

### Reproduction details for the two runtime risks

**QA-01:** On a short Android phone or in landscape, open Live, focus Search and keep the keyboard visible. Repeat while paused and at increased system text size. Also inspect the no-active-meeting state and a long load error. Expected: all content remains reachable without overflow stripes, clipped errors or an unusable list area. The code establishes the constrained-layout risk; its exact threshold depends on the device, keyboard and text scale.

**QA-02:** Throttle the connection. Start or end a meeting/group, confirm its dialog, then change tabs before the RPC returns. The destination can load the old database state, while the disposed screen suppresses its own completion reload. Repeat by leaving and returning before the first request completes. Expected: one mutation remains coordinated, and the visible screen eventually displays the committed state. Do not interpret this as evidence that database uniqueness has failed.

## Section 12 acceptance checklist

**Totals: PASS 7 · FAIL 0 · DEVICE 6.**

- **PASS** means the requested Dart behavior is verifiable from source, assuming the RPC/view contract in the spec. It is not a claim that the backend was exercised.
- **FAIL** would mean a direct mismatch in that checklist item's required behavior.
- **DEVICE** means the full item includes real-file totals, database outcomes, elapsed-time accuracy or process lifecycle that this source-only review cannot establish.
- There are **no direct FAIL verdicts among these 13 checklist items**. The hard-rule and runtime-risk findings above remain open independently of that narrow checklist.

| # | Acceptance item | Verdict | Evidence / remaining verification |
|---|---|---|---|
| 1 | Import actual Excel: 3 days, 104 groups, 389 students; add three dated meetings and open Coming | DEVICE | `import_screen.dart:97–188,210–246` derives the title, builds eight-key rows, counts distinct date/group keys, calls import_schedule, resets and navigates to Meetings. `meetings_screen.dart:135–149` sorts Coming correctly. The actual Excel file was not found in the project inventory, and the real 3/104/389 totals plus three server-created meetings cannot be verified here. |
| 2 | Same file again: upload card says Already added and Confirm is disabled | PASS | `import_screen.dart:168–188,219–225,301–305,333–336` detects matching title/dates, renders the warning inside the upload card, disables Confirm, and also handles an all-already-added RPC response. Actual server idempotency still follows the supplied migration contract. |
| 3 | Start 13 Oct with a dialog; other cards faded/disabled; Home says Meeting is live | PASS | `meetings_screen.dart:78–115,155,199–206` confirms Start and reloads. `MeetingCard.dart:47–58,129–150` locks other meetings and fades them to 0.5. `dashboard_screen.dart:315–324` uses the running status for the exact Home label. No date restriction is added. |
| 4 | Home Done 0, Remaining 35, Total 35; all Live groups Upcoming | DEVICE | `dashboard_screen.dart:349–351` displays overview counters, and `live_screen.dart:78–91,280–285` renders fetched group statuses. These exact initial counts/statuses depend on the actual import and server data; Dart does not manufacture or validate them. |
| 5 | Select/start group 4 with dialog; Running first, ticking timer; other Start buttons disabled | PASS | `live_screen.dart:114–120,129–165,213–218,295–306` guards Start, confirms, selects after success and sorts running first. The sole ticker is at `:49–53`. `LiveDetailMeetingCard.dart:219–237` wires the enabled flags. QA-02 applies if navigation occurs while the action is pending. |
| 6 | Pause without dialog; all timers freeze and group actions disable; Resume excludes paused time | DEVICE | Frontend freeze/disable paths are correct: `dashboard_screen.dart:94–109,199–205`; `live_screen.dart:49–53,114–135,330–331`; `MeetingCard.dart:97–101`; `time_utils.dart:13–21`. The code sends pause/resume directly, uses pausedAt, subtracts stored paused_seconds and stops ticking while paused. Accurate persisted pause accumulation across multiple real pause/resume cycles needs server/device timing checks. |
| 7 | End group 4 with dialog; show total, move down; Home Done 1 and Remaining 34 | DEVICE | `live_screen.dart:148–165,213–218,292–294` confirms End, reloads, sorts done below upcoming and displays stored duration_sec. Home reads refreshed counters on its next tab visit. The actual stored duration and exact 1/34 server counters need the real 35-group meeting. |
| 8 | While group 2 runs, group 3 cannot start | PASS | `live_screen.dart:111–120,140–146` requires no running group and rechecks the same eligibility inside the action handler. The busy flag is set before the confirmation dialog. |
| 9 | End meeting from Home with dialog; empty Home; Previous total, Done 2 and Skipped 33 | DEVICE | `dashboard_screen.dart:94–123,315–342` confirms End, reloads and renders the empty state. `meetings_screen.dart:138–148` selects done for Previous, and `MeetingCard.dart:107–119` shows stored total/done/skipped. Finishing the running group, marking the other 33 skipped and computing totals are server behavior; no SQL was executed or backend tested. |
| 10 | Another meeting can now be started | PASS | After reload, `meetings_screen.dart:80,155,202` only locks while another active meeting exists; `MeetingCard.dart:47,129–133` enables Start for an unlocked upcoming meeting. The service uses the specified start_meeting RPC. |
| 11 | Search by 3, student, reg #, supervisor and tech; filters combine with search | PASS | `live_screen.dart:185–218` lowercases/splits whitespace, requires every word to match at least one allowed field, includes “group N”, applies the status filter and then rank/group-number sorting. Filters are exactly All/Running/Upcoming/Done. This is substring matching, as the spec allows; “3” can also match a reg # or group 13. QA-01 is an independent keyboard/layout risk. |
| 12 | Opening another expanded card closes the previous card | PASS | One `int? expandedGroup` at `live_screen.dart:38`; `:295–299` replaces/toggles it. A single group id drives expanded content, so multiple cards cannot remain open. |
| 13 | Kill/reopen while running: timers resume correctly | DEVICE | `main.dart:48–50` selects the authenticated entry screen; `dashboard_screen.dart:47–68` and `live_screen.dart:66–94` reload persisted meeting/row timestamps and synchronize server time. Timer calculation is timestamp-based, not an in-memory increment. Actual session restoration, process death, persisted data, server offset and elapsed-time accuracy require a real kill/relaunch test. |

## Hard rules, screens and edge cases reviewed

| Area | Result from code |
|---|---|
| §2.1 / §3 existing visual design | No unrequested change to the documented palette, card radii, page padding or font defaults was identified in the source comparison. The fourth tab/font/spacing adjustment, new Meetings UI, three counters, Up next list and timer content are requested changes. Wrapping supervisor content supports the explicit long-text requirement. Pixel-level equivalence still requires phone/screenshots; no runtime visual PASS is claimed. |
| §2.2 state and navigation | setState only; sharing through onNavigate constructors/callbacks. MainScreen swaps four screen types in Home / Live / Meetings / Import order. Data screens load in initState; Import fetches duplicate dates after picking, as §8.2 specifies. QA-02 is the pending-operation coordination gap. |
| §2.3 lists | All four data lists use ListView.builder: Home Up next `dashboard_screen.dart:240`; Live groups `live_screen.dart:227`; Meetings `meetings_screen.dart:160`; expanded students `LiveDetailMeetingCard.dart:169`. The two embedded lists set shrinkWrap and NeverScrollableScrollPhysics. Fixed tab/filter/button controls are not data lists. |
| §2.4 Supabase access | Reads/mutations are centralized in MeetingService using from/select/rpc plus filters/order/limit. No Flutter raw SQL or direct insert/update/delete path found. Auth initialization/sign-in are existing authentication operations. |
| §2.5 English, debug output and cleanup | No print/debugPrint calls, old “Upcomming”/“Add” labels, “succeffluuy” message, or analyzer-reported unused imports/locals found in lib. Roman Urdu comments in Import are not visible UI text. The ignored widget fields are QA-05; the unused-looking foreColor is a public property and does not produce an analyzer warning. |
| §2.6 await/mounted and dispose | No unsafe context/setState continuation after await was found. Branches share a mounted guard before their next UI operation; catches/finally are guarded. Import error handling checks mounted inside showImportError. The confirm-dialog helper only returns a bool after its await and does not reuse context then. main/service/time helpers have no State/context to guard. Search listener and all controllers are disposed correctly. |
| §2.7 file boundaries | Non-UI Excel parsing remains in ImportScreen: QA-03. Services/model/time helpers otherwise exist in the prescribed folders. |
| §6 timers and time zones | Exactly one Timer.periodic in each of Home, Live and Meetings; each is initialized once, checks mounted and running status, and is cancelled in dispose. No card has a timer. Paused timers use frozenAt; finished values use stored total_seconds/duration_sec. Every displayed time is routed through formatTime, which uses toLocal. Calendar-only meeting dates intentionally preserve their date. Server sync occurs once per load. |
| §8.1 Meetings | Coming is status-based, active first then ascending date/id; Previous is done descending date. Both filters, empty/error/loading states, import navigation, refresh, locking, Start/Pause/Resume/End enablement and error SnackBar/reload are present. Done cards omit action buttons. |
| §8.2 Import | A1 trimmed title/fallback, first-error required-cell validation, short-row/header skipping, group numbering, eight-key payload, corrected summary keys, full/partial duplicate text, all-added response, success reset/navigation and Postgrest error box are implemented. Real workbook totals remain DEVICE. |
| §8.3 Live | Active meeting only; empty navigation, paused header, first-row group fields, correct rank/group sort, combined all-words search/filter, single selection/accordion, stored totals and Start/End guards present. Long project/student names have Expanded/Flexible parents and supervisor/time content uses Wrap. Vertical viewport risk is QA-01. |
| §8.4 Home | Correct active/paused/no-active titles, running-group timer, no-group hints, overview counters, max three upcoming groups ordered by number, Live links, End confirmation and direct Pause/Resume implemented. No standalone meeting timer is required on Home. |
| §9 confirmation dialog | White AlertDialog, radius 25, bold CustomText title, normal message, barrierDismissible false, black Cancel text and black/white pill Confirm; returns true only for Confirm. Used for meeting Start/End and group Start/End. Pause/Resume bypass it. System Back returning false is consistent with the contract. |
| §10 RPC errors, empty states and double taps | Meeting/group mutations show PostgrestException.message in a SnackBar and reload on errors; Import shows the required red error box. Generic failures also surface. Local mutation busy guards are set before dialogs/requests and disabled flags are wired on the feature actions. The login visual disabled state is QA-04 and cross-tab guard reset is QA-02. Error/loading/empty presentations exist; constrained error layout is included in QA-01. |
| Packages / out of scope | pubspec.yaml retains only the existing Flutter, cupertino_icons, excel, file_picker and supabase_flutter runtime dependencies; Git shows no dependency/config change. No Provider, Riverpod, Bloc, GetX or other added state package/import found. No out-of-scope skip/history-detail/realtime/export/editing feature identified. |

## Five highest-priority phone tests

1. **Real Excel and duplicates:** Import the original workbook and verify 3 days / 104 groups / 389 students, three dated Coming cards and automatic navigation. Reimport it; verify Already added and disabled Confirm. Also try a partially imported workbook, picker cancellation, corrupt/short rows and each blank required field; the first error must identify the Excel row.
2. **Full meeting sequence:** Start 13 Oct, verify 0/35/35, start group 4, pause for a measured interval, resume and end it; confirm 1/34, stored duration and ordering. Start group 2, verify group 3 is blocked, then end the meeting; verify Previous shows Done 2 / Skipped 33 and another meeting can start. Check all confirmations and cancellation, and no dialog for Pause/Resume.
3. **Slow/offline/error/concurrency:** Double-tap actions, delay the network and switch tabs during a pending RPC (QA-02). Disconnect during loading/actions; verify readable errors, no disposed-state crash, busy recovery and successful refresh/retry. If a second authorized device is available, attempt a conflicting meeting start and check the server message plus reload.
4. **Phone layout and search:** Test 320px width, short height, landscape, large system text, long project/supervisor/student/tech names, all four bottom tabs and device system insets. Open the keyboard on Live while running, paused, empty and showing a long error; verify results stay reachable and no overflow appears. Check each search field, multiword “group 3”, every filter and accordion behavior.
5. **Process death and timer accuracy:** Kill/reopen while running and while paused. Compare Home/Live/Meetings with an independent stopwatch across several pause/resume cycles, tab switches and backgrounding; paused time must not be counted. Check server-offset behavior with an intentionally different phone clock and confirm local display times. There must be no duplicated ticker effect or reset after relaunch.

## Reviewed Dart inventory

| File | Lines |
|---|---:|
| lib/main.dart | 53 |
| lib/models/meeting.dart | 55 |
| lib/screens/dashboard_screen.dart | 402 |
| lib/screens/import_screen.dart | 345 |
| lib/screens/live_screen.dart | 356 |
| lib/screens/login_screen.dart | 124 |
| lib/screens/main_screen.dart | 67 |
| lib/screens/meetings_screen.dart | 255 |
| lib/services/meeting_service.dart | 88 |
| lib/utils/time_utils.dart | 64 |
| lib/widgets/Button.dart | 53 |
| lib/widgets/confirm_dialog.dart | 38 |
| lib/widgets/CustomText.dart | 37 |
| lib/widgets/filter.dart | 40 |
| lib/widgets/LiveDetailMeetingCard.dart | 248 |
| lib/widgets/MeetingCard.dart | 162 |
| lib/widgets/TextBox.dart | 36 |
| **Total** | **2,423** |

## Review output integrity

The only authored file is `lib/SQLandMDFileFolder/QA_REPORT.md`. SHA-256 baselines were captured for all 20 pre-existing files under lib (including the spec, SQL and image asset), plus pubspec.yaml, pubspec.lock and analysis_options.yaml. After report creation, all 23 existing files were verified unchanged: zero checksum mismatches. Git status showed only QA_REPORT.md added to the pre-existing worktree changes. No source fix, formatting change, test execution, migration or database operation is part of this review.

