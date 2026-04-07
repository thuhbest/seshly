import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import '../controllers/start_page_controller.dart';

class StartPageView extends StatefulWidget {
  const StartPageView({super.key});

  @override
  State<StartPageView> createState() => _StartPageViewState();
}

class _StartPageViewState extends State<StartPageView> {
  @override
  Widget build(BuildContext context) {
    final controller = StartPageController(context);
    const Color primaryColor = Color(0xFF00C09E);
    const Color backgroundColor = Color(0xFF0F142B);

    return Scaffold(
      backgroundColor: backgroundColor,
      body: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 40.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              SvgPicture.asset(
                'assets/images/seshly_logo_full.svg',
                height: 120,
                semanticsLabel: 'Seshly Logo',
              ),
              const SizedBox(height: 30),

              const Text(
                'Seshly',
                style: TextStyle(
                  fontFamily: 'Roboto',
                  fontSize: 48,
                  fontWeight: FontWeight.w500,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 5),

              const Text(
                'Powered by AutoXyrium',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w400,
                  color: Colors.white70,
                ),
              ),
              const SizedBox(height: 20),

              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 20.0),
                child: Text(
                  '"AI as your teacher, not your academic slave"',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 16,
                    fontStyle: FontStyle.italic,
                    color: Colors.white70,
                  ),
                ),
              ),
              const SizedBox(height: 100),
              SizedBox(
                width: double.infinity,
                height: 50,
                child: ElevatedButton(
                  onPressed: controller.navigateToNextScreen,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: primaryColor,
                    foregroundColor: backgroundColor,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                    elevation: 5,
                  ),
                  child: const Text(
                    'Get Started',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 30),
            ],
          ),
        ),
      ),
    );
  }
}
