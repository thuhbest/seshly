import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'firebase_options.dart';

// Your feature imports
import 'package:seshly/features/startpage/views/start_page_view.dart';
import 'package:seshly/features/home/view/main_wrapper.dart';

const Color backgroundColor = Color(0xFF0F142B);

void main() async {
  // Ensure Flutter is initialized before calling Firebase
  WidgetsFlutterBinding.ensureInitialized();
  
  // Initialize Firebase with platform-specific options
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  // Match the navigation bar color to your app theme
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    systemNavigationBarColor: backgroundColor,
    systemNavigationBarIconBrightness: Brightness.light,
  ));

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Seshly',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        primarySwatch: Colors.teal,
        scaffoldBackgroundColor: backgroundColor,
        visualDensity: VisualDensity.adaptivePlatformDensity,
      ),
      // AuthWrapper acts as the gatekeeper for the session
      home: const AuthWrapper(),
    );
  }
}

class AuthWrapper extends StatelessWidget {
  const AuthWrapper({super.key});

  @override
  Widget build(BuildContext context) {
    // This stream listens to login/logout events in real-time
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, snapshot) {
        // 1. Handle the "checking session" state
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            backgroundColor: backgroundColor,
            body: Center(
              child: CircularProgressIndicator(
                color: Color(0xFF00C09E),
              ),
            ),
          );
        }

        // 2. If a user session exists, show the MainWrapper
        if (snapshot.hasData) {
          // This ensures the user sees the Nav Bar immediately after login
          return const MainWrapper(); 
        }

        // 3. If no user is authenticated, show the StartPageView
        return const StartPageView();
      },
    );
  }
}