import 'package:flutter/material.dart';
import 'package:smart_proximity_attendance/services/database_helper.dart';
import 'package:smart_proximity_attendance/screens/course_management_screen.dart';
import 'package:smart_proximity_attendance/screens/live_session_screen.dart';
import 'package:smart_proximity_attendance/screens/report_screen.dart';
import 'package:intl/intl.dart';

class TeacherDashboard extends StatefulWidget {
  const TeacherDashboard({super.key});

  @override
  State<TeacherDashboard> createState() => _TeacherDashboardState();
}

class _TeacherDashboardState extends State<TeacherDashboard> {
  final DatabaseHelper _dbHelper = DatabaseHelper();
  List<Map<String, dynamic>> _sessions = [];
  List<Map<String, dynamic>> _courses = [];

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    final sessions = await _dbHelper.getSessionsWithCourse();
    final courses = await _dbHelper.getCourses();
    setState(() {
      _sessions = sessions;
      _courses = courses;
    });
  }

  void _startNewSession() async {
    if (_courses.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please create a course first.')));
      return;
    }

    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (context) => _NewSessionDialog(courses: _courses),
    );

    if (result != null) {
      // PIN is now generated and rotated every 30 seconds inside LiveSessionScreen.
      final sessionId = await _dbHelper.startSession(
        result['courseId'],
        result['roomNumber'],
      );

      if (mounted) {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => LiveSessionScreen(
              sessionId: sessionId,
              courseId: result['courseId'],
              courseCode: result['courseCode'],
            ),
          ),
        ).then((_) => _loadData());
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Teacher Dashboard'),
        actions: [
          IconButton(
            onPressed: () => Navigator.push(
              context, 
              MaterialPageRoute(builder: (context) => const CourseManagementScreen())
            ).then((_) => _loadData()),
            icon: const Icon(Icons.book_outlined),
            tooltip: 'Manage Courses',
          )
        ],
      ),
      body: _sessions.isEmpty
          ? const Center(child: Text('No attendance history yet.'))
          : ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: _sessions.length,
              itemBuilder: (context, index) {
                final session = _sessions[index];
                final date = DateTime.parse(session['startTime']);
                return Card(
                  margin: const EdgeInsets.only(bottom: 12),
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    side: BorderSide(color: Colors.grey.shade200),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: ListTile(
                    title: Text(session['courseCode'], style: const TextStyle(fontWeight: FontWeight.bold)),
                    subtitle: Text('${session['courseName']} • Room ${session['roomNumber']}\n${DateFormat('MMM dd, hh:mm a').format(date)}'),
                    isThreeLine: true,
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(builder: (context) => ReportScreen(session: session)),
                      );
                    },
                  ),
                );
              },
            ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _startNewSession,
        label: const Text('Start Attendance'),
        icon: const Icon(Icons.add),
      ),
    );
  }
}

class _NewSessionDialog extends StatefulWidget {
  final List<Map<String, dynamic>> courses;
  const _NewSessionDialog({required this.courses});

  @override
  State<_NewSessionDialog> createState() => _NewSessionDialogState();
}

class _NewSessionDialogState extends State<_NewSessionDialog> {
  int? _selectedCourseId;
  final _roomController = TextEditingController();

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('New Attendance Session'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          DropdownButtonFormField<int>(
            decoration: const InputDecoration(labelText: 'Select Course'),
            items: widget.courses.map((c) => DropdownMenuItem(
              value: c['id'] as int,
              child: Text(c['code']),
            )).toList(),
            onChanged: (val) => setState(() => _selectedCourseId = val),
          ),
          TextField(
            controller: _roomController,
            decoration: const InputDecoration(labelText: 'Room Number'),
          ),
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        ElevatedButton(
          onPressed: () {
            if (_selectedCourseId != null && _roomController.text.isNotEmpty) {
              final course = widget.courses.firstWhere((c) => c['id'] == _selectedCourseId);
              Navigator.pop(context, {
                'courseId': _selectedCourseId,
                'courseCode': course['code'],
                'roomNumber': _roomController.text,
              });
            }
          },
          child: const Text('Start'),
        ),
      ],
    );
  }
}
