import 'package:flutter/material.dart';



class CustomBottomNav extends StatelessWidget {

  final int currentIndex;

  final Function(int) onTap;



  const CustomBottomNav({

    super.key,

    required this.currentIndex,

    required this.onTap,

  });



  @override

  Widget build(BuildContext context) {

    const Color tealAccent = Color(0xFF00C09E);



    return BottomNavigationBar(

      backgroundColor: const Color(0xFF0F142B),

      type: BottomNavigationBarType.fixed,

      currentIndex: currentIndex,

      onTap: onTap,

      selectedItemColor: tealAccent,

      unselectedItemColor: Colors.white38,

      selectedLabelStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),

      unselectedLabelStyle: const TextStyle(fontSize: 12),

      items: const [

        BottomNavigationBarItem(icon: Icon(Icons.home_filled), label: "Home"),

        BottomNavigationBarItem(icon: Icon(Icons.auto_awesome_rounded), label: "Sesh"),

        BottomNavigationBarItem(icon: Icon(Icons.people_alt_outlined), label: "Friends"),

        BottomNavigationBarItem(icon: Icon(Icons.calendar_today_outlined), label: "Calendar"),

        BottomNavigationBarItem(icon: Icon(Icons.person_outline), label: "Profile"),

      ],

    );

  }

}