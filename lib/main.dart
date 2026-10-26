import 'package:flutter/material.dart';
import 'package:livemeet/screens/login_screen.dart';
import 'package:livemeet/screens/main_screen.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Supabase.initialize(
    url: 'https://kgfmeyypggnwwmpfvygv.supabase.co',
    // Keep the existing Supabase initialization outside this feature's scope.
    // ignore: deprecated_member_use
    anonKey:
        'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImtnZm1leXlwZ2dud3dtcGZ2eWd2Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3OTI3Mjg1MTMsImV4cCI6MjEwODMwNDUxM30.5FAcKGQFn9TUG1Ex2a5cRptDQau_9mc-NNyG9o1hG9c',
  );

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  // This widget is the root of your application.
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Live Meet',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        // This is the theme of your application.
        //
        // TRY THIS: Try running your application with "flutter run". You'll see
        // the application has a purple toolbar. Then, without quitting the app,
        // try changing the seedColor in the colorScheme below to Colors.green
        // and then invoke "hot reload" (save your changes or press the "hot
        // reload" button in a Flutter-supported IDE, or press "r" if you used
        // the command line to start the app).
        //
        // Notice that the counter didn't reset back to zero; the application
        // state is not lost during the reload. To reset the state, use hot
        // restart instead.
        //
        // This works for code too, not just values: Most code changes can be
        // tested with just a hot reload.
        scaffoldBackgroundColor: const Color(0xFFF4F4F1),
        colorScheme: .fromSeed(seedColor: Color(0xFF111111)),
      ),
      home: Supabase.instance.client.auth.currentSession == null
          ? const LoginScreen()
          : const MainScreen(),
    );
  }
}
