import 'package:flutter/material.dart';
import 'package:smart_proximity_attendance/services/database_helper.dart';
import 'package:smart_proximity_attendance/screens/student_dashboard.dart';

class StudentLoginScreen extends StatefulWidget {
  const StudentLoginScreen({super.key});

  @override
  State<StudentLoginScreen> createState() => _StudentLoginScreenState();
}

class _StudentLoginScreenState extends State<StudentLoginScreen> {
  final _regController = TextEditingController();
  final DatabaseHelper _dbHelper = DatabaseHelper();
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _checkExistingLogin();
  }

  Future<void> _checkExistingLogin() async {
    final regNumber = await _dbHelper.getConfig('student_reg');
    if (regNumber != null && mounted) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
            builder: (context) => StudentDashboard(regNumber: regNumber)),
      );
    } else {
      setState(() => _isLoading = false);
    }
  }

  void _login() async {
    final reg = _regController.text.trim();
    if (reg.isEmpty) return;

    await _dbHelper.setConfig('student_reg', reg);
    if (mounted) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (context) => StudentDashboard(regNumber: reg)),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Student Setup')),
      body: Padding(
        padding: const EdgeInsets.all(32.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Icon(Icons.badge_outlined, size: 72, color: Colors.indigo),
            const SizedBox(height: 24),
            const Text(
              'Enter Your Registration Number',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            const Text(
              'This is a one-time setup. Your registration number will be '
              'permanently saved on this device and cannot be changed.\n\n'
              'Contact your teacher if you need to reset your device binding.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, color: Colors.grey, height: 1.5),
            ),
            const SizedBox(height: 32),
            TextField(
              controller: _regController,
              decoration: InputDecoration(
                labelText: 'Registration Number',
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12)),
                prefixIcon: const Icon(Icons.numbers),
              ),
              keyboardType: TextInputType.number,
              textInputAction: TextInputAction.done,
              onSubmitted: (_) => _login(),
            ),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: _login,
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 16),
                backgroundColor: Colors.indigo,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
              child: const Text('Continue', style: TextStyle(fontSize: 16)),
            ),
          ],
        ),
      ),
    );
  }
}
