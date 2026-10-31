# LiveMeet QA report 2

Review date: 26 October 2026 (Asia/Karachi)  
Project: `D:/7th Semester/Flutter/Project/livemeet`  
Verdict: **Not ready**  
Findings: **6 — Critical: 0; High: 2; Medium: 3; Low: 1.**

## Scope and verification limits

Read the complete `livemeet_codex_spec.md` first, then all 17 Dart files under `lib/` (2,656 lines), both SQL files (321 lines), and the complete earlier `QA_REPORT.md`. Inspected the image asset as well. Reviewed the current working tree, including the existing uncommitted feature changes. Read package/lint configuration and the installed authentication implementation to check logout failure behavior.

This was a read-only source audit. No Dart, SQL or test file was edited; no `flutter test`, migration, database query or RPC was run. No app or phone was launched. Concrete source defects are distinguished below from **unverified** runtime scenarios. The real workbook and deployed Supabase schema/policies were unavailable, so actual import totals and deployment state are not certified.

Earlier report reconciliation:

- **QA-01:** Empty/error content now scrolls in Live and Meetings, filters scroll horizontally, and Live hides its heading while the keyboard is visible. These fixes are acknowledged; QA2-05 concerns only the remaining fixed-height header on very short keyboard-reduced viewports.
- **QA-02:** Fixed for mutations: MainScreen ignores navigation while its shared busy flag is true. All mutation `finally` blocks call `onBusyChanged(false)` outside the mounted guard.
- **QA-03:** Intentionally postponed; parser extraction is not repeated as a finding.
- **QA-04:** Fixed: Sign in now passes `enabled: !isLoading`.
- **QA-05:** TextBox now forwards `keyboardType`. Button still ignores `foreColor`, but current callers render readable labels; no additional user-visible bug is asserted for that unused option.

## Flutter analysis

The requested `flutter analyze lib` was attempted from the project root. It produced no analysis output while sandboxed; the Flutter batch bootstrap requires access to its SDK cache lock outside the workspace. That attempt was stopped (exit 1), and the equivalent scoped analysis completed with SDK-cache access and dependency/version checks suppressed:

```text
flutter --no-version-check analyze --no-pub lib
Analyzing lib...
No issues found! (ran in 4.1s)
Exit code: 0
```

This is a clean analysis of production `lib/`, not a device test or a database validation. No tests were run.

## Findings, sorted by severity

### QA2-01 — High — Interleaved meeting dates silently merge distinct projects into one group

**File and line:** `lib/screens/import_screen.dart:136–156`; downstream grouping at `lib/screens/live_screen.dart:87–89` and SQL insertion at `lib/SQLandMDFileFolder/supabase_meetings_migration.sql:109–117`.

**What goes wrong / reproduce:** Import a valid workbook with three student data rows in this order: 13 Oct / 11:00 / Project A, 19 Oct / 11:00 / Project B, 13 Oct / 12:00 / Project C, with distinct registration numbers and all required fields populated. Every date change resets the counter, so A and C both receive group 1 within the 13 Oct meeting; Live merges their students, displays only the first project's details, and Start/End updates both projects as one group.

The counter behavior was reproduced with an in-memory PowerShell transcription of the existing loop, without creating files or inserting data: all three rows received group 1. The upload summary counts three distinct date/time/project/supervisor keys, while the SQL overview would count only two `(meeting_id, group_no)` groups. There is no validation requiring contiguous date blocks.

**Suggested smallest fix:** Reject a date that reappears after its block has ended, with its Excel row number, before enabling import. If interleaved dates should be supported, retain a separate counter and last group key per date rather than resetting one global counter. Do not silently accept colliding group numbers.

### QA2-02 — High — Failed logout leaves signed-out users on the populated authenticated screen

**File and line:** `lib/screens/dashboard_screen.dart:100–119`; `lib/main.dart:48–50`.

**What goes wrong / reproduce:** Load Home with a meeting, disconnect the network, then confirm Logout and allow the auth request to fail. The installed GoTrue implementation clears the local session before awaiting its server logout request, but this screen navigates to Login only on success; its catch merely shows an error, leaving the old meeting visible with no authenticated session and no auth-state router to remove the screen.

**Evidence:** Installed `gotrue-2.27.3/lib/src/gotrue_client.dart:1078–1110` defaults to local sign-out, calls `_removeSession()` at line 1089, emits signedOut, then awaits `admin.signOut` at line 1101; qualifying errors propagate. The app has no `onAuthStateChange` listener. The failure sequence is established from the pinned installed source; its offline presentation is **unverified on a phone**. A second Logout can recover, but the first failed request must not retain authenticated UI after local logout.

**Suggested smallest fix:** After a sign-out error, inspect `auth.currentSession`; if it is null, clear the route stack to Login with a mounted guard, while still reporting any remote sign-out failure. Retain Home only if a session actually remains. Alternatively route signedOut events centrally and dispose that subscription.

### QA2-03 — Medium — Home never renders Up next

**File and line:** `lib/screens/dashboard_screen.dart:481–500`; unused implementation at `:344–413`.

**What goes wrong / reproduce:** Start a meeting with upcoming groups and open Home. The page ends after Done/Remaining/Total because the entire Up next heading, See all link and `upNextList()` call are commented out; users cannot see the next three groups required by the spec.

**Suggested smallest fix:** Restore the heading/link and call to the existing `upNextList()` below the counters. Its existing filtering, ascending group-number ordering, three-item limit and embedded builder already supply the requested data behavior.

### QA2-04 — Medium — Slow clock-sync responses make live timers run behind and jump on reload

**File and line:** `lib/utils/time_utils.dart:5–8`; used by the load methods in Home `:59`, Live `:79`, and Meetings `:62`.

**What goes wrong / reproduce:** While a group is running, delay delivery of the `server_now` response by five seconds after the server generates its timestamp, then refresh Live. The offset subtracts the phone's receipt time from that old timestamp, so the live clock runs approximately five seconds behind; a subsequent fast refresh moves it forward, and a stored server-computed finished duration can jump relative to the displayed timer.

This is a direct consequence of the formula even when the phone's clock is correct. The delayed-network reproduction is **unverified**; no response interception or backend call was performed.

**Suggested smallest fix:** Capture local times immediately before and after the RPC and estimate offset against their midpoint; reject/retry high round-trip samples instead of replacing a good offset with them. Keep the lowest-latency sample when possible. Midpoint estimation reduces ordinary symmetric latency error; it cannot guarantee exact time under arbitrary asymmetric delays.

### QA2-05 — Medium — Live still overflows when keyboard-reduced height cannot hold its fixed controls (unverified)

**File and line:** `lib/screens/live_screen.dart:364–401`; outer bottom bar at `lib/screens/main_screen.dart:56–72`.

**What goes wrong / reproduce:** On a short phone in landscape, pause the meeting, focus Search and keep the keyboard open; use a viewport where Live's available body height after the bottom bar and keyboard is less than roughly 220 dp at default text scale. Hiding the date/title leaves 78 dp vertical padding, the paused banner, Search, filter strip and three 10 dp gaps outside the scrollable results, so the Column still overflows and can leave no results area.

**Unverified:** No phone/emulator layout was rendered; the precise threshold depends on keyboard, font metrics and text scale. This is the remaining constrained-height case, not a repeat of the fixed non-scrollable empty/error content. At ordinary 384 dp portrait width, horizontal button sizing itself is not the identified problem.

**Suggested smallest fix:** Let the remaining header controls scroll with the results through a sliver composition or provide an equivalent height-aware fallback. Preserve lazy group building and pull-to-refresh. Merely hiding the main heading cannot handle a body shorter than the remaining fixed controls.

### QA2-06 — Low — Rounding each pause separately accumulates timer error

**File and line:** `lib/SQLandMDFileFolder/supabase_meetings_migration.sql:163–180`, `:198–219`, `:259–260`; Dart display truncates seconds at `lib/utils/time_utils.dart:20`.

**What goes wrong / reproduce:** Keep a group running and perform 20 pause/resume cycles whose server-recorded pauses are each 1.6 seconds, then end the group. Each pause is rounded to 2 seconds before accumulation, so 32 seconds of actual pause becomes 40 seconds in both the meeting and running group's pause counters, undercounting active time by about eight seconds, beyond the normal one-second display granularity.

The 32-versus-40 arithmetic was checked in memory; repeated real RPC timing is **unverified**. PostgreSQL's numeric-to-integer conversion rounds before conversion; see its [PostgreSQL 16 numeric conversion implementation](https://github.com/postgres/postgres/blob/REL_16_STABLE/src/backend/utils/adt/numeric.c), especially `numeric_int4_opt_error`, `numericvar_to_int32`, and `numericvar_to_int64`. Independently flooring each pause would also accumulate error.

**Suggested smallest fix:** Preserve fractional pause time in the stored accumulator (numeric seconds or integer milliseconds) and only round/truncate once for display/final duration. Apply the same precision consistently to meeting and group calculations and adjust Dart numeric parsing accordingly.

## Coverage and source conclusions

| Area | Reviewed behavior and practical limits |
|---|---|
| Home logout | Confirmation is non-barrier-dismissible; local busy is set before the dialog and prevents a second Logout or meeting action. Parent busy is set before signOut and reset in finally. Success clears all old routes to Login. Network failure after local session removal is QA2-02. |
| Home lime card | Meeting title wraps in Expanded beside Live/Paused; separate meeting timer and running group number, project, timer, supervisor and local started time are present. No-group hints distinguish remaining work from all finished. End confirms; Pause/Resume does not. Both reject busy/loading/error/no-active states in the handler. |
| 384 dp buttons and long text | Home has `(384 - 36 page padding - 40 card padding - 20 gaps) / 3 = 96 dp` per button at font size 12. Live has about 101 dp per button at size 15; MeetingCard uses the same three-column width with 48 dp height. No direct horizontal overflow is identified at default scale. Titles/names wrap, supervisor/status uses Wrap, and student tech uses Flexible. Large accessibility text and narrow/short screens still need rendering; QA2-05 covers the remaining vertical constraint. |
| Home counters/Up next | Overview fields feed Done/Remaining/Total directly; SQL counts distinct groups. Counter numbers and labels scale down within the three cards. Up next is not attached to the widget tree: QA2-03. |
| Live selection/order/search | Initial load alone requests running-group auto-selection. Refresh and action reloads preserve manual selection for the same meeting; a different meeting clears it. Successful Start selects that group. Rank is running/upcoming/done/skipped, then numeric group number. Every search word must match; 1–3 digit-only words compare the exact group number, 4+ digits search the permitted fields, and `group 3` combines the textual group label with exact 3. One nullable id drives selection, another drives accordion expansion. |
| Live Pause/Resume | Enabled only on a running group in an active meeting and while neither loading nor busy nor errored. Paused group remains status running, so Resume remains available there. Group Start/End require a running meeting. Pause/Resume calls the meeting RPC without confirmation, reloads, displays the paused banner and freezes at meeting.pausedAt. No running group means use Home/Meetings to resume. |
| Live keyboard and states | Search controller/listener disposed; keyboard-visible heading suppression is implemented. Empty/error/no-match states are builder items with a minimum height and unbounded vertical growth, inside an always-scrollable list. Pull refresh is guarded while busy/loading. QA2-05 remains for the surrounding fixed header. Closing the keyboard uses normal platform behavior; device verification remains necessary. |
| Meetings | Coming includes upcoming/running/paused, active first then date/id; Previous includes done, date descending. Other meetings are faded and locked while one is active. Local handler rechecks eligibility, then holds busy through confirmation/RPC/reload. Start/End/Restart confirm; Pause/Resume does not. Exactly one periodic timer, no timers in cards. |
| Restart | Previous cards show Restart, disabled when another meeting is active or an action is busy. Handler also rejects it. RPC resets done meeting and every student row to upcoming and clears timing/progress fields transactionally. Reload removes it from Previous; selecting Coming shows it there (automatic filter switching is not implemented or required). Deployment of the separate restart SQL remains unverified. |
| Import | A1 is trimmed with filename fallback; valid date/time rows validate reg/student/supervisor/project in order and report index+1. Header/short rows are deliberately skipped as specified. Eight payload keys, duplicate-date lookup, full/partial already-added notices and importSchedule result handling are wired. Success resets state, unlocks navigation and opens Meetings. Picker/Confirm double taps are locally guarded. Date-block collision is QA2-01. |
| Busy/navigation | MainScreen.go ignores both tab taps and onNavigate while parent busy is true. Mutations notify busy before their RPC and reset it in finally even if unmounted. Import explicitly unlocks before its success navigation. Picking/reading/checking an Excel file holds only local busy, allowing safe tab abandonment; mounted guards discard its result and no import mutation has started. Modal confirmations block normal tab interaction. |
| Await/mounted/lifecycle | No unsafe setState/Navigator/ScaffoldMessenger continuation after await was identified. Error helper checks mounted. Each of Home/Live/Meetings creates one Timer.periodic in initState and cancels it in dispose; Login controllers and Live controller/listener are disposed. No timer increment counters or card timers. Loading flags clear in finally when mounted; discarded State does not require clearing its private flag. |
| Slow/failed network and actions | Local action busy flags are set synchronously before confirmation, preventing repeated RPCs from button double taps. Mutation catches display readable Postgrest messages (or generic error text), attempt reload and finally release parent busy; load failures replace data with an error view and release loading. Import errors disable Confirm and allow selecting the file again. Clock-response latency is QA2-04; logout failure is QA2-02. |
| UTC/Pakistan/midnight/reopen | TIMESTAMPTZ values parse as instants; DateTime.difference handles UTC/local representation and crossing midnight. Actual timestamps display through toLocal (Pakistan on a Pakistan-configured phone). Scheduled time-without-zone is deliberately parsed as local wall time, and date-only meeting dates preserve the day. Running/paused timers reload persisted timestamps after process death; finished cards use stored totals. Fractional pause drift is QA2-06. Full recovery/session persistence needs phone testing. |
| Logout then another account | Successful logout removes the old MainScreen route, login creates a fresh MainScreen, and screen-local meeting/search/import state is rebuilt. The service caches the client, not response rows; server offset is refreshed on load. Meetings are intentionally shared among authenticated users, so seeing the same backend meetings is not evidence of stale account data. Failed logout routing is the specific exception in QA2-02. |

## SQL/Supabase review

Reviewed every supplied function, index, grant and policy. No SQL was executed. Concurrency conclusions assume normal PostgreSQL Read Committed RPC transactions, where locking statements recheck updated row conditions; see [PostgreSQL 16 transaction isolation](https://www.postgresql.org/docs/16/transaction-iso.html).

| Function / schema element | Conclusion |
|---|---|
| meetings constraints/index | Allowed meeting statuses and unique title/date are enforced. Partial unique `one_active_meeting` covers both running and paused, preventing two active meetings even if simultaneous start checks both initially pass. The losing request may get a uniqueness error, which the UI displays. |
| meetings RLS and overview | Authenticated full access is explicit and matches the shared PA/no-owner model. The overview uses security_invoker and distinct group counts; rows with a valid uniform group status count correctly. The app mutates through RPCs, but full table UPDATE permission means arbitrary authenticated API writes are not constrained to those RPC transitions. No owner-only rule is proposed. |
| Existing meeting_schedule security | The migration depends on an existing table and does not define its original columns, RLS policies or authenticated table/sequence grants. Their actual correctness and anonymous denial are **unverified deployment prerequisites**, not asserted defects; inspect deployed policies before sign-off. RPCs are SECURITY INVOKER, so those grants matter. |
| server_now | Returns an instant from clock_timestamp; authenticated EXECUTE is granted and PUBLIC/anon EXECUTE revoked. Client offset estimation is QA2-04. |
| import_schedule | One transaction creates each missing title/date and student rows; existing dates are reported rather than overwritten. Unique title/date protects duplicates; a simultaneous import can fail with uniqueness rather than return already_added, with no partial transaction committed. The function trusts supplied group numbers, so it accepts QA2-01's collisions. |
| start_meeting | Only upcoming can start. Existing active check plus the unique partial index prevents a second active meeting. It does not impose a date restriction, as requested. |
| pause_meeting | Conditional update only permits running to paused and locks the meeting row through the update. Repeated or inappropriate Pause raises an error instead of resetting pause time. |
| resume_meeting | Locks the paused meeting row, rejects other states, adds pause duration to the meeting and currently running student rows, and clears paused_at. Repeated resume cannot add a pause twice. Fractional accumulation defect: QA2-06. |
| end_meeting | Locks active meeting, finishes running group, skips upcoming groups, accounts for an unfinished pause and stores totals atomically. It rejects upcoming/done; paused End is supported. Done/skipped group history is not rewritten. |
| group_start | Locks the running parent before checking another running group. Competing starts on that parent serialize; only upcoming rows of the requested group start. Paused/done/no meeting fails. No path through these RPCs was found that starts a second group concurrently. |
| group_end | Locks running parent, rejects paused/done/no meeting and updates only requested running group; duplicate End errors. It stores duration minus that group's pause accumulator. |
| restart_meeting | Table SHARE ROW EXCLUSIVE lock serializes its active check against meeting writes. Rejects any other active meeting and any target not done. Resets meeting and group statuses/timestamps/pauses/totals in the same transaction, without deleting the schedule. Execute restricted to authenticated. |
| Transaction/permission limits | Supplied policies do not implement owner separation, as requested. Invariants above describe the app/RPC paths plus the active-meeting index, not a claim that full authenticated direct table writes are transition-safe. Original table constraints and whether the two migrations are installed are not inferable from local files. |

## Summary and verdict

**Not ready.** Static analysis is clean, and the new controls, busy coordination, Live selection/search and Restart paths are largely implemented correctly. Fix silent import group collisions, logout failure routing and the missing Up next section before sign-off; improve clock sampling and verify the residual short-screen case. Persisted whole-second pause rounding is a smaller accuracy defect. No Critical issue was established.

## Device test checklist

### Verified from code

These are source conclusions, not claims of observed device passes.

1. Import extracts A1/fallback, validates required cells with Excel row numbers, builds eight payload keys and performs duplicate-date detection; QA2-01 affects interleaved dates.
2. Already-added disables Confirm; partial duplicate text and all-added RPC response are handled.
3. Start meeting confirms and locks other cards; meeting/group actions are locally guarded before dialogs.
4. Home lime card shows title, Live/Paused, meeting timer, running group/project/timer/start time, and no-group hints; counters use overview values. Up next fails: QA2-03.
5. Live initially selects the running group, preserves manual selection on refresh, sorts by rank/group number and selects a newly started group.
6. Live Pause/Resume targets the meeting, has no dialog, freezes timers via pausedAt and blocks group Start/End while paused.
7. Group End confirms, reloads, displays stored duration and sorts Done below Upcoming.
8. Running-group and active-meeting RPCs serialize relevant mutations; UI blocks conflicting Start actions.
9. End meeting confirms, finishes running group, skips upcoming groups and moves the meeting into Previous.
10. Restart confirms, locks while another meeting is active, clears progress atomically and reloads the lists so the meeting returns to Coming.
11. Exact short numeric / long numeric / multi-word search and single selection/accordion are implemented; empty/error lists scroll.
12. Logout confirms and clears the route stack on success; shared busy blocks navigation during requests and resets in finally. Failed logout routing needs QA2-02.
13. Three screen tickers and controllers are disposed; timers derive from stored instants across midnight/reopen and use local display times, subject to QA2-04/06 accuracy limits.

### Must test on the phone

1. Import the real workbook: expect 3 days / 104 groups / 389 students, three Coming meetings and success navigation. Separately try the interleaved-date workbook from QA2-01; it must be rejected or grouped correctly after a fix.
2. Reimport unchanged and partial-duplicate files; test A1 blank fallback, corrupt file, picker cancel and each missing required cell. Verify exact Excel row errors and no stuck busy state.
3. Start 13 Oct, cancel/confirm its dialog, and check other cards are faded/disabled. Verify Home initially shows Done 0 / Remaining 35 / Total 35 with the real data.
4. Inspect the new lime card at 384 dp with a very long meeting title/project/supervisor, no running group and all groups finished. Verify all three buttons and counters; verify the restored Up next list shows the first three upcoming groups.
5. Start group 4, leave/reopen Live and confirm auto-selection. Manually select/unselect another group, refresh and trigger a reload; manual selection must remain. Check Running/Upcoming/Done order and filters.
6. Pause/Resume directly in Live, then from Home and Meetings, timing measured pauses. Check banner, frozen meeting/group timers, correct Resume enablement and disabled group Start/End; include repeated short pauses for QA2-06.
7. End group 4 and inspect stored total/order; Home should show 1 done / 34 remaining. Start group 2 and verify group 3 Start cannot run concurrently.
8. Test search `3` against groups 3/13/30 and registration numbers containing 3, `group 3`, `003`, four-plus-digit registration fragments and multi-word name/project/tech queries. Open/close keyboard, running and paused, in portrait and short landscape with enlarged text; test QA2-05.
9. Expand one card then another; select another while expanded. Test long student/reg/tech text, no groups, no search matches and a long error; all relevant content must remain reachable and refreshable.
10. End meeting while running and paused; verify Previous shows stored total, expected Done/Skipped counts and another meeting can start. Restart: cancel then confirm, verify Previous removal, Coming membership, zero progress/timestamps and a fresh Start; while another meeting is active Restart must remain disabled.
11. Delay/fail each action and double-tap it; tap tabs/Open Live during the pending request. Errors must appear, navigation remain blocked, flags recover, and refreshed committed state appear. Add delayed clock responses for QA2-04; if available, use two devices for competing meeting/group starts and duplicate imports.
12. Cancel Logout, then confirm online and sign in as another account; Back must not reveal the old route. Repeat Logout offline: verify local-session removal still returns to Login after QA2-02 is fixed and no old screen remains visible.
13. Kill/reopen while running and paused; compare all timers with a stopwatch, including Pakistan midnight, background/resume and a deliberately incorrect phone clock. Verify persisted pauses/totals and recovery after reconnect. Confirm both SQL files and existing meeting_schedule policies/grants are installed correctly.

## Recommended fix order

- **Fix now:** QA2-01 (silent group merging), QA2-02 (logout/session routing), QA2-03 (missing required Home content), QA2-04 (slow-response timer error). Reproduce QA2-05 on the smallest supported keyboard/landscape viewport and fix before small-screen sign-off.
- **Can wait with an accepted accuracy limit:** QA2-06 (fractional pause accumulation). Normal timestamp recovery is sound, but repeated pauses can exceed one second of error.
- **Still deliberately deferred:** earlier QA-03 parser extraction. The unused Button.foreColor cleanup can also wait; it is not counted as a new functional finding.

## Output integrity

Only `lib/SQLandMDFileFolder/QA_REPORT_2.md` was authored. SHA-256 values for every pre-existing file under lib were recorded and compared after report creation. No pre-existing lib file changed. Existing source/SQL worktree changes predated this audit and were preserved.
