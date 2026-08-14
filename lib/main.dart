import 'package:flutter/material.dart';
import 'package:smart_proximity_attendance/screens/role_selection_screen.dart';
import 'package:smart_proximity_attendance/screens/teacher_dashboard.dart';
import 'package:smart_proximity_attendance/screens/student_login_screen.dart';

void main() {
  runApp(const AttendanceApp());
}

class AttendanceApp extends StatelessWidget {
  const AttendanceApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Proximity Attendance',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.indigo),
        useMaterial3: true,
        appBarTheme: const AppBarTheme(
          centerTitle: true,
          elevation: 0,
          backgroundColor: Colors.indigo,
          foregroundColor: Colors.white,
        ),
      ),
      home: const RoleSelectionScreen(),
      routes: {
        '/teacher': (context) => const TeacherDashboard(),
        '/student_login': (context) => const StudentLoginScreen(),
      },
    );
  }
}
