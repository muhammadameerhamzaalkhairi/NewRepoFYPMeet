import 'package:flutter/material.dart';
import 'package:livemeet/screens/dashboard_screen.dart';
import 'package:livemeet/screens/import_screen.dart';
import 'package:livemeet/screens/live_screen.dart';
import 'package:livemeet/screens/meetings_screen.dart';
import 'package:livemeet/widgets/Button.dart';

const kHome = 0;
const kLive = 1;
const kMeetings = 2;
const kImport = 3;

class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  int index = kHome;
  bool busy = false;

  void go(int i) {
    if (!mounted || busy) return;
    setState(() => index = i);
  }

  void setBusy(bool value) {
    if (!mounted) return;
    setState(() => busy = value);
  }

  Widget navigationButton(String label, int tabIndex) {
    return Expanded(
      child: Button(
        text: label,
        fontSize: 14,
        color: index == tabIndex ? const Color(0xFFDDF35C) : Colors.white,
        foreColor: index == tabIndex ? Colors.black : Colors.white,
        onTap: () => go(tabIndex),
        fontWeight: FontWeight.bold,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: [
        DashboardScreen(onNavigate: go, onBusyChanged: setBusy),
        LiveScreen(onNavigate: go, onBusyChanged: setBusy),
        MeetingsScreen(onNavigate: go, onBusyChanged: setBusy),
        ImportScreen(onNavigate: go, onBusyChanged: setBusy),
      ][index],
      bottomNavigationBar: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.all(12),
        margin: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(50),
          color: Colors.black,
        ),
        width: double.infinity,
        child: Row(
          spacing: 6,
          children: [
            navigationButton('Home', kHome),
            navigationButton('Live', kLive),
            navigationButton('Meetings', kMeetings),
            navigationButton('Import', kImport),
          ],
        ),
      ),
    );
  }
}
