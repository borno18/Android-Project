import 'package:flutter/material.dart';
import 'package:smart_proximity_attendance/services/database_helper.dart';
import 'package:smart_proximity_attendance/screens/roster_management_screen.dart';

class CourseManagementScreen extends StatefulWidget {
  const CourseManagementScreen({super.key});

  @override
  State<CourseManagementScreen> createState() => _CourseManagementScreenState();
}

class _CourseManagementScreenState extends State<CourseManagementScreen> {
  final DatabaseHelper _dbHelper = DatabaseHelper();
  List<Map<String, dynamic>> _courses = [];

  @override
  void initState() {
    super.initState();
    _loadCourses();
  }

  Future<void> _loadCourses() async {
    final courses = await _dbHelper.getCourses();
    setState(() => _courses = courses);
  }

  void _addCourse() async {
    final result = await showDialog<Map<String, String>>(
      context: context,
      builder: (context) => const _AddCourseDialog(),
    );

    if (result != null) {
      await _dbHelper.insertCourse(result['name']!, result['code']!);
      _loadCourses();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Manage Courses')),
      body: _courses.isEmpty
          ? const Center(child: Text('No courses added yet.'))
          : ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: _courses.length,
              itemBuilder: (context, index) {
                final course = _courses[index];
                return Card(
                  child: ListTile(
                    title: Text(course['code'], style: const TextStyle(fontWeight: FontWeight.bold)),
                    subtitle: Text(course['name']),
                    trailing: const Icon(Icons.people_alt_outlined),
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => RosterManagementScreen(courseId: course['id'], courseCode: course['code']),
                        ),
                      );
                    },
                  ),
                );
              },
            ),
      floatingActionButton: FloatingActionButton(
        onPressed: _addCourse,
        child: const Icon(Icons.add),
      ),
    );
  }
}

class _AddCourseDialog extends StatefulWidget {
  const _AddCourseDialog();

  @override
  State<_AddCourseDialog> createState() => _AddCourseDialogState();
}

class _AddCourseDialogState extends State<_AddCourseDialog> {
  final _nameController = TextEditingController();
  final _codeController = TextEditingController();

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Add New Course'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(controller: _codeController, decoration: const InputDecoration(labelText: 'Course Code (e.g. CS101)')),
          TextField(controller: _nameController, decoration: const InputDecoration(labelText: 'Course Name')),
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        ElevatedButton(
          onPressed: () {
            if (_nameController.text.isNotEmpty && _codeController.text.isNotEmpty) {
              Navigator.pop(context, {'name': _nameController.text, 'code': _codeController.text});
            }
          },
          child: const Text('Add'),
        ),
      ],
    );
  }
}
