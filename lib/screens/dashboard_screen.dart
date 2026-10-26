import 'dart:async';

import 'package:flutter/material.dart';
import 'package:livemeet/models/meeting.dart';
import 'package:livemeet/screens/main_screen.dart';
import 'package:livemeet/services/meeting_service.dart';
import 'package:livemeet/utils/time_utils.dart';
import 'package:livemeet/widgets/Button.dart';
import 'package:livemeet/widgets/CustomText.dart';
import 'package:livemeet/widgets/confirm_dialog.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class DashboardScreen extends StatefulWidget {
  final void Function(int) onNavigate;
  final ValueChanged<bool> onBusyChanged;

  const DashboardScreen({
    super.key,
    required this.onNavigate,
    required this.onBusyChanged,
  });

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  Meeting? meeting;
  List<Map<String, dynamic>> groups = [];
  bool isLoading = false;
  bool busy = false;
  String errorMessage = '';
  late final Timer ticker;

  @override
  void initState() {
    super.initState();
    loadMeeting();
    ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted && meeting?.status == 'running' && runningGroup != null) {
        setState(() {});
      }
    });
  }

  @override
  void dispose() {
    ticker.cancel();
    super.dispose();
  }

  Future<void> loadMeeting() async {
    setState(() {
      isLoading = true;
      errorMessage = '';
    });
    try {
      await syncServerClock();
      if (!mounted) return;
      final active = await MeetingService.fetchActiveMeeting();
      if (!mounted) return;
      final Map<int, Map<String, dynamic>> loaded = {};
      if (active != null) {
        final rows = await MeetingService.fetchRows(active.id);
        if (!mounted) return;
        for (final row in rows) {
          loaded.putIfAbsent((row['group_no'] as num).toInt(), () => row);
        }
      }
      setState(() {
        meeting = active;
        groups = loaded.values.toList();
      });
    } on PostgrestException catch (e) {
      if (!mounted) return;
      setState(() => errorMessage = e.message);
    } catch (e) {
      if (!mounted) return;
      setState(() => errorMessage = 'Unable to load meeting: $e');
    } finally {
      if (mounted) setState(() => isLoading = false);
    }
  }

  Map<String, dynamic>? get runningGroup =>
      groups.where((row) => row['status'] == 'running').firstOrNull;

  Future<void> changeMeeting({required bool end}) async {
    final active = meeting;
    if (busy ||
        isLoading ||
        errorMessage.isNotEmpty ||
        active == null ||
        !active.isActive) {
      return;
    }
    setState(() => busy = true);
    try {
      if (end) {
        final confirmed = await showConfirmDialog(
          context,
          title: 'End meeting?',
          message:
              'The running group will be finished and groups that were not held will be marked as skipped.',
        );
        if (!mounted) return;
        if (!confirmed) return;
        widget.onBusyChanged(true);
        await MeetingService.endMeeting(active.id);
      } else if (active.status == 'paused') {
        widget.onBusyChanged(true);
        await MeetingService.resumeMeeting(active.id);
      } else {
        widget.onBusyChanged(true);
        await MeetingService.pauseMeeting(active.id);
      }
      if (!mounted) return;
      if (end) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Meeting ended')));
      }
      await loadMeeting();
      if (!mounted) return;
    } on PostgrestException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(e.message)));
      await loadMeeting();
      if (!mounted) return;
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Meeting action failed: $e')));
      await loadMeeting();
      if (!mounted) return;
    } finally {
      widget.onBusyChanged(false);
      if (mounted) setState(() => busy = false);
    }
  }

  Widget counter(String label, int count) => Expanded(
    child: Container(
      padding: const EdgeInsets.all(12),
      height: 90,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(25),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          FittedBox(
            fit: BoxFit.scaleDown,
            child: CustomText(
              height: 1,
              text: '$count',
              fontSize: 42,
              fontWeight: FontWeight.w900,
            ),
          ),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: CustomText(text: label),
          ),
        ],
      ),
    ),
  );

  Widget liveCard(Meeting active) {
    final running = runningGroup;
    final started = running?['started_at'] as String?;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFFDDF35C),
        borderRadius: BorderRadius.circular(25),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CustomText(
            text: running == null ? 'No group is running' : 'Now running',
            fontWeight: FontWeight.w600,
          ),
          const SizedBox(height: 5),
          if (running != null) ...[
            CustomText(
              text: running['project'] as String,
              fontWeight: FontWeight.bold,
              fontSize: 28,
              height: 1,
            ),
            const SizedBox(height: 10),
            CustomText(
              text:
                  '${running['supervisor']} · Started ${started == null ? '—' : formatTime(DateTime.parse(started))}',
            ),
            CustomText(
              text: started == null
                  ? '—'
                  : formatClock(
                      elapsedSec(
                        startedAt: DateTime.parse(started),
                        pausedSeconds:
                            (running['paused_seconds'] as num?)?.toInt() ?? 0,
                        frozenAt: active.pausedAt,
                      ),
                    ),
              fontSize: 28,
              fontWeight: FontWeight.bold,
            ),
          ] else
            CustomText(
              text: active.groupsRemaining > 0
                  ? 'Open Live to start the next group'
                  : 'All groups are finished. You can end the meeting.',
            ),
          const SizedBox(height: 15),
          SizedBox(
            width: 130,
            height: 50,
            child: Button(
              text: 'Open Live',
              onTap: () => widget.onNavigate(kLive),
            ),
          ),
        ],
      ),
    );
  }

  Widget upNextList() {
    final upcoming = groups.where((row) => row['status'] == 'upcoming').toList()
      ..sort((a, b) => (a['group_no'] as num).compareTo(b['group_no'] as num));
    // The original dashboard has no number tiles; use the spec's pastel palette.
    // const colors = [
    //   Color(0xFFD6E6F7),
    //   Color(0xFFF8DDC8),
    //   Color(0xFFE6DDF5),
    //   Color(0xFFF6EDBA),
    // ];
    return ListView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      padding: EdgeInsets.zero,
      itemCount: upcoming.length > 3 ? 3 : upcoming.length,
      itemBuilder: (context, index) {
        final row = upcoming[index];
        return Container(
          margin: const EdgeInsets.only(bottom: 10),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  // color: colors[index % colors.length],
                  borderRadius: BorderRadius.circular(12),
                ),
                child: CustomText(
                  text: '${row['group_no']}',
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    CustomText(
                      text: row['project'] as String,
                      fontWeight: FontWeight.bold,
                    ),
                    CustomText(
                      text:
                          '${formatTime(DateTime.parse('2000-01-01T${row['meeting_time']}'))} · ${row['supervisor']}',
                      fontSize: 12,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 5),
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: const Color.fromARGB(255, 219, 219, 219),
                  borderRadius: BorderRadius.circular(25),
                ),
                child: const CustomText(text: 'Upcoming', fontSize: 12),
              ),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final active = meeting;
    final ready = !isLoading && errorMessage.isEmpty;
    return Scaffold(
      body: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 60, 18, 18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              CustomText(
                text: formatDate(active?.meetingDate ?? DateTime.now()),
              ),
              CustomText(
                text: !ready
                    ? 'Home'
                    : active == null
                    ? 'No meeting is running'
                    : active.status == 'paused'
                    ? 'Meeting is paused'
                    : 'Meeting is live',
                fontSize: 38,
                fontWeight: FontWeight.w900,
                height: 1,
              ),
              const SizedBox(height: 10),
              if (isLoading)
                const Center(child: CircularProgressIndicator())
              else if (errorMessage.isNotEmpty) ...[
                CustomText(text: errorMessage, color: Colors.red),
                const SizedBox(height: 10),
                Button(text: 'Retry', onTap: loadMeeting),
              ] else if (active == null) ...[
                const CustomText(
                  text:
                      'Start a meeting from the Meetings tab to see its live status here.',
                ),
                const SizedBox(height: 10),
                Button(
                  text: 'Go to Meetings',
                  onTap: () => widget.onNavigate(kMeetings),
                ),
              ] else ...[
                liveCard(active),
                const SizedBox(height: 10),
                Row(
                  spacing: 10,
                  children: [
                    counter('Done', active.groupsDone),
                    counter('Remaining', active.groupsRemaining),
                    counter('Total', active.groupsTotal),
                  ],
                ),
                // const SizedBox(height: 10),
                // Row(
                //   children: [
                //     const Expanded(
                //       child: CustomText(
                //         text: 'Up next',
                //         fontSize: 18,
                //         fontWeight: FontWeight.bold,
                //       ),
                //     ),
                //     TextButton(
                //       onPressed: () => widget.onNavigate(kLive),
                //       style: TextButton.styleFrom(
                //         foregroundColor: Colors.black,
                //       ),
                //       child: const Text('See all'),
                //     ),
                //   ],
                // ),
                // upNextList(),
                const SizedBox(height: 10),
                Row(
                  spacing: 10,
                  children: [
                    Expanded(
                      child: Button(
                        text: 'End meeting',
                        enabled: !busy,
                        onTap: () => changeMeeting(end: true),
                      ),
                    ),
                    Expanded(
                      child: Button(
                        text: active.status == 'paused' ? 'Resume' : 'Pause',
                        color: Colors.white,
                        enabled: !busy,
                        onTap: () => changeMeeting(end: false),
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
