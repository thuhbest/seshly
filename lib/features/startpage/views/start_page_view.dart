import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart'; 
import '../controllers/start_page_controller.dart';

// Dummy screen to navigate to
class NextScreen extends StatelessWidget {
  const NextScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Next Screen')),
      body: const Center(
        child: Text('You made it to the next screen!', style: TextStyle(fontSize: 24)),
      ),
    );
  }
}

class StartPageView extends StatelessWidget {
  // Use a simple constructor key
  const StartPageView({super.key});

  @override
  Widget build(BuildContext context) {
    // Instantiate the controller for business logic (navigation)
    final controller = StartPageController(context);

    // Define the colors from the screenshot
    const Color primaryColor = Color(0xFF00C09E); // The teal/turquoise color
    const Color backgroundColor = Color(0xFF0F142B); // The dark background

    return Scaffold(
      backgroundColor: backgroundColor,
      body: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 40.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              // 1. App Logo / Icon (ONLY CHANGE MADE HERE)
              SvgPicture.asset(
                'assets/images/seshly_logo_full.svg',
                height: 120, // Adjusted height for visibility
                semanticsLabel: 'Seshly Logo',
              ),
              const SizedBox(height: 30),

              // 2. App Name
              const Text(
                'Seshly',
                style: TextStyle(
                  fontFamily: 'Roboto', // Or another elegant font
                  fontSize: 48,
                  fontWeight: FontWeight.w500,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 5),

              // 3. Powered By
              const Text(
                'Powered by AutoXyrium',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w400,
                  color: Colors.white70,
                ),
              ),
              const SizedBox(height: 20),

              // 4. Tagline
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
              const SizedBox(height: 100), // Adjust spacing as needed

              // 5. Get Started Button
              SizedBox(
                width: double.infinity,
                height: 50,
                child: ElevatedButton(
                  onPressed: controller.navigateToNextScreen,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: primaryColor, // Button background color
                    foregroundColor: backgroundColor, // Button text/icon color
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10), // Rounded corners
                    ),
                    elevation: 5,
                  ),
                  child: const Text(
                    'Get Started',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Colors.white, // Text is white on the screenshot
                    ),
                  ),
                ),
              ),
              // Add a small spacer at the bottom for the hidden bar area
              const SizedBox(height: 30),
            ],
          ),
        ),
      ),
    );
  }
}