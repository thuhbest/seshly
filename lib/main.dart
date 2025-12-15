import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:seshly/features/startpage/views/start_page_view.dart';

// Define the dark background color globally for consistency
const Color backgroundColor = Color(0xFF0F142B); 

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  
  // Set the system navigation bar color to match the app's dark background
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
      title: 'Seshly App',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        primarySwatch: Colors.teal,
        scaffoldBackgroundColor: backgroundColor, 
        visualDensity: VisualDensity.adaptivePlatformDensity,
      ),
      // Start with the initial screen
      home: const StartPageView(),
    );
  }
}