# livemeet: Meetings feature and Live / Home / Import upgrade

Spec for Codex. Read this whole file first, then read the existing code before editing anything.

## 0. How to work

1. Read `lib/main.dart`, every file in `lib/screens/` and `lib/widgets/` before you change anything.
2. Do the tasks in the order of section 11, one at a time. After each task run `flutter analyze`. It must be clean before you continue.
3. Do NOT run SQL and do NOT touch Supabase. The user runs `supabase_meetings_migration.sql` in the Supabase SQL Editor. The Dart code assumes that migration is applied.
4. Do not add packages. Already available: `supabase_flutter`, `file_picker`, `excel`, and `dart:async`.
5. When something here is ambiguous, pick the simplest option that matches the existing code style and leave a one-line comment. Do not ask the user.

## 1. What the app is

FYP-1 evaluation tool for a PA (the only user, logged in with Supabase Auth). An Excel schedule lists student groups. On the meeting day the PA runs the meeting and starts/ends one group at a time while a timer runs. Finished meetings are kept as history.

Tabs (bottom bar): Home, Live, Meetings (NEW), Import.

## 2. Hard rules

1. **Do not change the existing visual design.** Same colors, radius, spacing, fonts and widgets (section 3). Improve logic only. New screens and widgets must look like the existing ones.
2. **setState only.** No Provider, Riverpod, Bloc, GetX or other state packages. Share data by constructor parameters and callbacks. Each screen loads its own data from Supabase in `initState` (MainScreen swaps screens, so each tab visit refetches).
3. **Every list uses `ListView.builder`.** Inside a scrolling page use `shrinkWrap: true` and `NeverScrollableScrollPhysics()`.
4. Use `.from()`, `.select()`, `.rpc()` only. No raw SQL from Flutter.
5. UI text in English. Remove all debug `print()` calls. Fix typos (for example "succeffluuy").
6. After every `await`, check `if (!mounted) return;` before using `context` or `setState`.
7. Keep files small. Put non-UI code in `lib/services`, `lib/models`, `lib/utils`.

## 3. Existing design (reuse, do not redesign)

| Item | Value |
|---|---|
| Scaffold background | `0xFFF4F4F1` |
| Main text / black | `0xFF111111` |
| Lime (selected, highlight) | `0xFFDDF35C` |
| White cards | white, `borderRadius` 20 (list cards) or 25 (big cards) |
| Grey chip | `Color.fromARGB(255,219,219,219)`, padding 8, radius 25 |
| Tech chip | `0xFFD6E6F7`, radius 25 |
| Error box | `Color.fromARGB(255,255,223,221)`, red text, radius 25 |
| Screen padding | `EdgeInsets.fromLTRB(18, 60, 18, 18)` |
| Screen header | small date line (`CustomText`), then big title `CustomText(fontSize: 38, fontWeight: FontWeight.w900)` |
| Vertical gaps | 10 to 15 |

Existing widgets in `lib/widgets/` (read each file for its exact signature):

- `Button({text, color, foreColor, onTap, enabled})`: pill, width infinity, height 60. `color == null` gives black background with white text. A given `color` gives that background with black text. `enabled: false` fades it and ignores taps.
- `CustomText` (text, fontSize, fontWeight, height, color), `TextBox` (controller, hintText), `Filter` (text, isSelected, onTap), `Livedetailmeetingcard`.
- Group number tiles on Home use pastel colors (blue, peach, lilac, yellow). Reuse whatever the Home code already does.

## 4. Decisions already made (keep unless the user says otherwise)

| # | Decision |
|---|---|
| D1 | **One meeting = one meeting day.** The Excel file has 3 dates (13, 19, 20 Oct 2026), so one import creates 3 meetings. The Import summary still says "3 days \| 104 groups \| 389 students". |
| D2 | **Meeting identity = (title, date).** Title = text of cell A1 of the sheet (for example "Meeting Schedule Fall 2026"), falling back to the file name without extension. Importing the same file again does not create duplicates. |
| D3 | Only **one meeting** can be `running` or `paused` at a time. The database enforces it and the UI disables other meetings. |
| D4 | Inside a running meeting, **groups can run in any order**, one at a time. Missing groups are fine. |
| D5 | Pause applies to the whole meeting (meeting timer and running group timer freeze). Pause and Resume have **no** confirm dialog. Start meeting, End meeting, Start group and End group **do** have one. |
| D6 | End meeting: the running group (if any) becomes `done`. Groups never held become `skipped`. |
| D7 | **Live list order: Running first, then Upcoming (group number order), then Done at the bottom.** This keeps the next action at the top. It is one `sortRank` map (section 8.3), so it is trivial to change. |
| D8 | Meetings tab "Coming" = status `upcoming`, `running`, `paused`. "Previous" = status `done`. It is status based, not date based. |
| D9 | A meeting can be started on any date (no date restriction), so testing is possible. |
| D10 | Tab order: Home, Live, Meetings, Import. |

## 5. Database (already written, do not edit)

File: `supabase_meetings_migration.sql`. Tested on PostgreSQL 16 with the real Excel data.

### Tables and view

`meetings`: `id, title, meeting_date, status (upcoming|running|paused|done), started_at, ended_at, paused_at, paused_seconds, total_seconds, created_at`. Unique on `(title, meeting_date)`.

`meeting_schedule` (existing flat table, one row per student) gained: `meeting_id`, `paused_seconds`, `duration_sec`. Existing columns: `id, group_no, meeting_date, meeting_time, project, supervisor, reg_no, student_name, tech, status (upcoming|running|done|skipped), started_at, ended_at`. All rows of a group share the same `group_no` and `status`.

View `meetings_overview` = `meetings` plus `groups_total, students_total, groups_done, groups_skipped, groups_remaining` (remaining = upcoming + running).

### RPC functions

All callable as `Supabase.instance.client.rpc(name, params: {...})`. They raise readable errors (show `PostgrestException.message` in a SnackBar).

| Function | Params | Effect |
|---|---|---|
| `server_now` | none | returns the server timestamp |
| `import_schedule` | `p_title` (text), `p_rows` (JSON array of the 8 row keys) | creates a meeting per date, skips dates already added. Returns `[{meeting_id, meeting_date, already_added, groups, students}]` |
| `start_meeting` | `p_id` | `upcoming` to `running`. Fails if another meeting is active |
| `pause_meeting` | `p_id` | `running` to `paused` |
| `resume_meeting` | `p_id` | `paused` to `running` (adds paused time) |
| `end_meeting` | `p_id` | sets `done`, computes `total_seconds`, finishes running group, marks unheld groups `skipped` |
| `group_start` | `p_meeting`, `p_group` | group `upcoming` to `running`. Needs meeting `running` and no other running group |
| `group_end` | `p_meeting`, `p_group` | group `running` to `done`, computes `duration_sec`. Needs meeting `running` (not paused) |

Row keys for `p_rows` (same as the current Import screen after the earlier fix): `group_no, meeting_date (yyyy-MM-dd), meeting_time (HH:mm), project, supervisor, reg_no, student_name, tech`.

### Dart service: `lib/services/meeting_service.dart`

Plain class with static methods (no UI, no state):

```dart
class MeetingService {
  static final _db = Supabase.instance.client;

  static Future<DateTime> fetchServerNow();                         // rpc server_now
  static Future<List<Meeting>> fetchMeetings();                     // from('meetings_overview'), all
  static Future<Meeting?> fetchActiveMeeting();                     // status in (running, paused), limit 1 -> .inFilter('status', [...])
  static Future<List<Map<String, dynamic>>> fetchRows(int meetingId); // from('meeting_schedule').eq('meeting_id', id).order('group_no').order('id')
  static Future<Set<String>> fetchExistingDates(String title, List<String> dates); // from('meetings').eq('title', t).inFilter('meeting_date', dates)
  static Future<List<dynamic>> importSchedule(String title, List<Map<String, dynamic>> rows);
  static Future<void> startMeeting(int id);
  static Future<void> pauseMeeting(int id);
  static Future<void> resumeMeeting(int id);
  static Future<void> endMeeting(int id);
  static Future<void> startGroup(int meetingId, int groupNo);
  static Future<void> endGroup(int meetingId, int groupNo);
}
```

### Model: `lib/models/meeting.dart`

```dart
class Meeting {
  final int id;
  final String title;
  final DateTime meetingDate;
  final String status;                 // upcoming | running | paused | done
  final DateTime? startedAt, endedAt, pausedAt;   // parse with DateTime.parse
  final int pausedSeconds;
  final int? totalSeconds;
  final int groupsTotal, studentsTotal, groupsDone, groupsSkipped, groupsRemaining;
  bool get isActive => status == 'running' || status == 'paused';
  factory Meeting.fromMap(Map<String, dynamic> m) => ...;
}
```

## 6. Shared time logic: `lib/utils/time_utils.dart`

The phone clock can differ from the server clock. Timestamps are written by the server, so correct for the difference once per screen load.

```dart
Duration serverOffset = Duration.zero;               // serverNow - DateTime.now()
Future<void> syncServerClock() async {
  serverOffset = (await MeetingService.fetchServerNow()).difference(DateTime.now());
}
DateTime nowServer() => DateTime.now().add(serverOffset);

// Seconds a timer should show.
int elapsedSec({
  required DateTime startedAt,
  int pausedSeconds = 0,
  DateTime? frozenAt,     // meeting.pausedAt while the meeting is paused
  DateTime? endedAt,      // for finished items
}) {
  final end = endedAt ?? frozenAt ?? nowServer();
  final s = end.difference(startedAt).inSeconds - pausedSeconds;
  return s < 0 ? 0 : s;
}

String formatClock(int sec);   // 14:07  or  1:02:07 when >= 1 hour
String formatTotal(int sec);   // '<1 min', '13 min', '1h 12m'
String formatTime(DateTime t); // t.toLocal() -> '11:22 AM'
String formatDate(DateTime d); // 'Tue, 13 Oct 2026'
```

Rules:

- Meeting timer: `elapsedSec(startedAt: m.startedAt, pausedSeconds: m.pausedSeconds, frozenAt: m.pausedAt)`.
- Group timer (group is running): `elapsedSec(startedAt: row.started_at, pausedSeconds: row.paused_seconds, frozenAt: meeting.pausedAt)`.
- Finished meeting or group: show the stored `total_seconds` or `duration_sec` (do not recompute).
- **Ticker:** each screen that shows a live timer owns one `Timer.periodic(const Duration(seconds: 1), ...)` created in `initState`, cancelled in `dispose`. It calls `setState(() {})` only when something is `running` (not paused). Never create a timer per card.
- Call `syncServerClock()` once in each screen's load method.

## 7. Navigation: `lib/screens/main_screen.dart`

- Replace the bools `isHome / isLive / isImport` with `int index`. Constants: `kHome = 0, kLive = 1, kMeetings = 2, kImport = 3`.
- Body: `[DashboardScreen(onNavigate: go), LiveScreen(onNavigate: go), MeetingsScreen(onNavigate: go), ImportScreen(onNavigate: go)][index]` where `void go(int i) => setState(() => index = i);`. Pass the callback as `final void Function(int) onNavigate` to each screen.
- Keep the bottom bar's current look and selected/unselected behaviour. Add the 4th item "Meetings" in the same pattern. With four items, reduce `spacing` from 15 to about 6 and use a smaller font.
- Add optional `fontSize` (default 18) and `height` (default 60) parameters to `Button`. Existing usages must not change. The nav bar uses `fontSize: 14`. The meeting cards use `height: 48, fontSize: 15`.

## 8. Screens

### 8.1 Meetings (NEW): `lib/screens/meetings_screen.dart`

Layout, same style as Live:

- Small date line (today), title **Meetings** (38, w900).
- Two `Filter` pills: **Coming meetings** and **Previous meetings** (`int tab`).
- `Expanded` + `RefreshIndicator` + `ListView.builder` of `MeetingCard`.
- Data: `MeetingService.fetchMeetings()`, split by status.
  - Coming: active (running/paused) first, then `meetingDate` ascending, then id.
  - Previous: `meetingDate` descending.
- Empty states (centered `CustomText`):
  - Coming empty: "No coming meetings. Import a schedule first." with a `Button('Go to Import')` that calls `onNavigate(kImport)`.
  - Previous empty: "No previous meetings yet."
- `activeMeeting` = the meeting where `isActive`, else null. Every other card is `locked`.
- Ticker as in section 6.
- `bool busy` guards double taps while an RPC is running (all card buttons disabled while `busy`).

**`MeetingCard`** (new, `lib/widgets/MeetingCard.dart`), white card radius 20 like `Livedetailmeetingcard`, lime background when the meeting is active:

- Title (bold 18, may wrap).
- Row: status chip (grey chip: Upcoming / Running / Paused / Done) and the date text.
- Info line: `35 groups · 133 students`.
- Time block by status:
  - upcoming: "Not started"
  - running/paused: `Started 11:22` and the **live meeting timer** (bold, larger). Frozen when paused.
  - done: `Started 11:00 · Ended 12:12`, a chip `Total 1h 12m` (from `total_seconds`) and `Done 33 · Skipped 2`.
- Buttons row (not shown for done): `Start`, `Pause` (becomes `Resume` when paused), `End`. Use `Button` with `height: 48`. Each in an `Expanded`, `spacing: 10`.

| Meeting status | Start | Pause / Resume | End |
|---|---|---|---|
| upcoming, nothing else active | enabled | disabled | disabled |
| running | disabled | Pause enabled | enabled |
| paused | disabled | Resume enabled | enabled |
| locked (another meeting active) | disabled, whole card at `Opacity(0.5)` | disabled | disabled |

Actions:

- Start: confirm dialog "Start meeting?" with the title and date. Then `startMeeting`. Only one meeting can run at a time.
- Pause / Resume: no dialog.
- End: confirm dialog "End meeting?" with "The running group will be finished and groups that were not held will be marked as skipped." Then `endMeeting`.
- After any action: reload. On `PostgrestException` show `e.message` in a SnackBar and reload.

### 8.2 Import: `lib/screens/import_screen.dart`

Keep the layout. Logic changes:

1. Add `onNavigate`. Remove debug prints. Keep `canImport` (enable/disable) as it is now.
2. **Title:** `meetingTitle` = trimmed text of the first cell of the sheet (A1). Fallback: file name without `.xlsx`.
3. **Row validation while parsing.** Data rows are those with a valid date and time (header and title rows are skipped, as now). Excel row number = loop index + 1. If a data row has a blank reg #, student, supervisor or project, stop with the existing red error box, for example `Row 9 is missing a reg #.`, and keep `canImport = false`. Report the first problem only.
4. Keep the client-side `group_no` logic: a new group starts when `date|time|project|supervisor` changes, and the counter resets on a new date.
5. Fix the summary keys. Rows are sent with the key `meeting_date`, not `date`. Days = distinct `meeting_date`. Groups = distinct `meeting_date|meeting_time|project|supervisor`.
6. **Already-added detection (after picking the file).** Call `fetchExistingDates(meetingTitle, distinctDates)`.
   - Show it **inside the upload card**, as a third text line under the summary:
     - all dates exist: "Already added" (red). `canImport = false`.
     - some dates exist: "2 of 3 days already added. The rest will be imported."
     - none: no extra line.
7. **Confirm:** `importSchedule(meetingTitle, rows)` (send only the 8 row keys). Read the result.
   - every item `already_added == true`: show "Already added", `canImport = false`.
   - otherwise SnackBar "N meeting(s) added", reset the screen to its initial state (`step = 'Step 1 of 2'`, `isUploaded = false`, `canImport = false`), then `onNavigate(kMeetings)`.
   - on `PostgrestException` show `e.message` in the error box.

### 8.3 Live: `lib/screens/live_screen.dart` and `lib/widgets/LiveDetailMeetingCard.dart`

The screen currently loads a fixed date from `meeting_schedule`. Change it to work on the active meeting.

**Loading**

1. `syncServerClock()`, then `fetchActiveMeeting()`.
2. No active meeting: show the header, then "No meeting is running" with a short hint and `Button('Go to Meetings')` calling `onNavigate(kMeetings)`.
3. Active meeting: `fetchRows(meeting.id)` and group the rows by `group_no` as the current code does. Group fields (status, started_at, ended_at, paused_seconds, duration_sec) come from the group's first row.
4. Header date line = meeting date. If the meeting is paused show a line "Meeting is paused" under the title. Resume is done from Home or Meetings.

**List**

- `ListView.builder` inside `Expanded` + `RefreshIndicator` (keep as now).
- Sorting (D7): `const sortRank = {'running': 0, 'upcoming': 1, 'done': 2, 'skipped': 3};` order by rank, then `group_no`.
- Filter pills: `All, Running, Upcoming, Done`. Fix the old labels ("Add", "Upcomming"). `selectedFilter` stays one int.
- **Search (flexible):** lowercase, split the text on spaces, and require every word to match. A digits-only word of 1–3 digits matches only the exact group number (`3` or `group 3` matches group 3, not group 13 or a reg #). A digits-only word of 4 or more digits matches by substring in reg #, student name, project, supervisor, or tech. Other words match by substring in those fields, status, or `group N`. Empty search shows everything.
- **Selection:** one `selectedGroup` (tap card to select, tap again to unselect). After a successful Start, select that group.
- **Expansion (accordion):** replace the `Set<int> expanded` with `int? expandedGroup`. Opening a card closes the previously open one.
- Expanded content (already built): student name as title, reg # as subtitle, tech chip on the right.

**Card (`Livedetailmeetingcard`) new optional parameters**

`String? timerText`, `String? totalText`, `VoidCallback? onStart`, `VoidCallback? onEnd`, `bool canStart = false`, `bool canEnd = false`.

- Running card: show the live group timer (`formatClock`) in the status row, for example a small chip after the supervisor text.
- Done card: show `totalText` ("13 min") in the same place.
- Selected card shows the two buttons exactly as now (keep the current button order). Hide the buttons row when the group is `done` or `skipped`.
- `Start` has `enabled: canStart`, `End` has `enabled: canEnd`.

**Rules**

- `canStart` = meeting is `running` (not paused) AND group is `upcoming` AND no group is `running`.
- `canEnd` = meeting is `running` AND this group is `running`.
- Start group: confirm dialog "Start group N?" with the project title. Then `startGroup`.
- End group: confirm dialog "End group N?" with the elapsed time. Then `endGroup`. The card then shows its total time and moves down the list.
- After each action reload the data. On errors show `e.message` in a SnackBar and reload.
- Ticker (section 6). Frozen while the meeting is paused.

### 8.4 Home: `lib/screens/dashboard_screen.dart`

Keep the current layout and styling. Read the file first and keep what already works.

**Loading:** `syncServerClock()`, `fetchActiveMeeting()`, and when active `fetchRows(id)` (for the running group and the Up next list). Counters come from the active `Meeting` (`groupsDone`, `groupsRemaining`, `groupsTotal`).

**No active meeting**

- Header: date line and title "No meeting is running".
- A short text: "Start a meeting from the Meetings tab to see its live status here."
- `Button('Go to Meetings')` calling `onNavigate(kMeetings)`.

**Active meeting**

1. Header: small date line = meeting date. Title: "Meeting is live", or "Meeting is paused" when paused.
2. **Lime card**
   - A group is running: label "Now running", project title, `Supervisor · Started 11:22`, and the **live group timer** (bold, larger, `formatClock`) in place of the old static "14 min elapsed". Frozen when paused. Black pill `Open Live` calls `onNavigate(kLive)`.
   - No group running: label "No group is running". If groups remain, the hint "Open Live to start the next group". If none remain, "All groups are finished. You can end the meeting." Keep the `Open Live` button.
3. **Counter row:** three white cards in one `Row`, each `Expanded`, `spacing: 10`: **Done**, **Remaining**, **Total** (number big, label small, same style as the current two cards).
4. **Up next:** title, "See all" (calls `onNavigate(kLive)`), then up to 3 upcoming groups ordered by `group_no`, built with `ListView.builder` (`shrinkWrap`, `NeverScrollableScrollPhysics`). Row style as it is now: number tile, project title, `time · supervisor`, grey "Upcoming" chip.
5. **Bottom row:** `End meeting` and `Pause` side by side, each `Expanded`, `spacing: 10`.
   - `End meeting` keeps its current style (black). It shows the confirm dialog. After confirming call `endMeeting`, show the SnackBar "Meeting ended", then reload (the empty state appears).
   - `Pause` uses `Button(color: Colors.white)`. **No confirm dialog.** The label changes to `Resume` while paused. It calls `pauseMeeting` / `resumeMeeting`.
6. Ticker (section 6).

## 9. Confirm dialog: `lib/widgets/confirm_dialog.dart`

```dart
Future<bool> showConfirmDialog(
  BuildContext context, {
  required String title,
  required String message,
  String confirmText = 'Confirm',
  String cancelText = 'Cancel',
});
```

- `AlertDialog`, white background, `RoundedRectangleBorder` radius 25, `barrierDismissible: false`.
- Title bold, message normal (use `CustomText`).
- Actions: `Cancel` as a plain text button (black text) and `confirmText` as a black pill button with white text.
- Returns `true` only when the confirm button is pressed.

Used for: Start meeting, End meeting (Meetings card and Home), Start group, End group. Not used for Pause or Resume.

## 10. Edge cases

- **Errors from RPC** (for example "Another meeting is already running" when a second device started one): show `e.message` in a SnackBar, then reload.
- **App closed during a meeting:** nothing is lost. Timers are recomputed from the stored timestamps.
- **Paused meeting:** group Start/End are disabled everywhere and all timers are frozen.
- **Double taps:** use a `busy` flag around every RPC call and disable the buttons while it is true.
- **Same file imported again:** nothing is inserted, the Import screen says "Already added".
- **Empty or short rows:** skip rows with fewer than 8 cells, as the current code does.
- **Long text:** project and supervisor names can be long. Use `Flexible` or `Expanded` so rows never overflow.
- **Time zone:** show times with `.toLocal()`.

## 11. Task order

1. `lib/utils/time_utils.dart`, `lib/models/meeting.dart`, `lib/services/meeting_service.dart`.
2. `Button`: optional `fontSize` and `height`.
3. `lib/widgets/confirm_dialog.dart`.
4. `MainScreen`: 4 tabs, `onNavigate`, add the callback parameter to all four screens.
5. `ImportScreen` (section 8.2).
6. `MeetingCard` and `MeetingsScreen` (section 8.1).
7. `LiveScreen` and `Livedetailmeetingcard` (section 8.3).
8. `DashboardScreen` (section 8.4).
9. Cleanup: remove prints, unused imports and variables. `flutter analyze` is clean.

## 12. Acceptance checklist (run on a device after the migration)

1. Import the Excel file: message says 3 days, 104 groups, 389 students. Confirm adds 3 meetings and opens the Meetings tab, "Coming" shows 3 cards (13, 19, 20 Oct).
2. Import the same file again: the upload card shows "Already added" and Confirm is disabled.
3. Start the 13 Oct meeting (a dialog appears). The other two cards become faded and disabled. Home shows "Meeting is live".
4. Home shows Done 0, Remaining 35, Total 35. Live shows all groups with Upcoming status.
5. In Live, select group 4 and start it (dialog). Group 4 moves to the top as Running, its timer ticks, and Start is disabled on every other group.
6. Pause from Home (no dialog): timers freeze, Live shows "Meeting is paused" and Start/End are disabled. Resume: timers continue, and the paused time is not counted.
7. End group 4 (dialog). It shows its total time and moves to the bottom. Home Done = 1, Remaining = 34.
8. Start group 2, then try to start group 3: Start is disabled while 2 runs.
9. End meeting from Home (dialog). Home shows "No meeting is running". The meeting is under "Previous" with a total time, Done 2, Skipped 33.
10. Another meeting can now be started.
11. Search in Live: `3`, a student name, a reg #, a supervisor and a tech word each find the right groups. Filters All/Running/Upcoming/Done work together with search.
12. Open one expanded card, then expand another: the first closes.
13. Kill and reopen the app during a running meeting: timers resume from the correct values.

## 13. Out of scope (do not build)

Skip button, history detail screen, realtime subscriptions, editing or deleting meetings, multiple users or roles, PDF/Excel export, push notifications, state-management packages.
