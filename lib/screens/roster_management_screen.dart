import 'dart:io';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:smart_proximity_attendance/services/database_helper.dart';

class RosterManagementScreen extends StatefulWidget {
  final int courseId;
  final String courseCode;
  const RosterManagementScreen(
      {super.key, required this.courseId, required this.courseCode});

  @override
  State<RosterManagementScreen> createState() => _RosterManagementScreenState();
}

class _RosterManagementScreenState extends State<RosterManagementScreen> {
  final DatabaseHelper _dbHelper = DatabaseHelper();
  List<Map<String, dynamic>> _roster = [];

  @override
  void initState() {
    super.initState();
    _loadRoster();
  }

  Future<void> _loadRoster() async {
    final roster = await _dbHelper.getRosterForCourse(widget.courseId);
    setState(() => _roster = roster);
  }

  void _importCSV() async {
    FilePickerResult? result = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['csv'],
    );

    if (result != null) {
      final file = File(result.files.single.path!);
      final input = await file.readAsString();
      final lines = input.split('\n');

      int imported = 0;
      for (var line in lines) {
        final fields = line.split(',');
        if (fields.isNotEmpty) {
          final regNumber = fields[0].trim();
          // Name is optional (2nd column if present)
          final name = fields.length >= 2 ? fields[1].trim() : null;
          if (regNumber.isNotEmpty) {
            await _dbHelper.insertRosterEntry(
                widget.courseId, regNumber, name?.isEmpty == true ? null : name);
            imported++;
          }
        }
      }
      await _loadRoster();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Imported $imported student(s) from CSV.')),
        );
      }
    }
  }

  void _manualAdd() async {
    final regController = TextEditingController();
    final nameController = TextEditingController();

    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Add Student'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: regController,
              decoration: const InputDecoration(
                labelText: 'Registration Number *',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.numbers),
              ),
              keyboardType: TextInputType.number,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: nameController,
              decoration: const InputDecoration(
                labelText: 'Student Name (optional)',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.person_outline),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Add'),
          ),
        ],
      ),
    );

    if (result == true && regController.text.trim().isNotEmpty) {
      final name = nameController.text.trim();
      await _dbHelper.insertRosterEntry(
        widget.courseId,
        regController.text.trim(),
        name.isEmpty ? null : name,
      );
      _loadRoster();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Roster: ${widget.courseCode}'),
        actions: [
          IconButton(
            onPressed: _importCSV,
            icon: const Icon(Icons.upload_file),
            tooltip: 'Import CSV (reg_number, name)',
          ),
        ],
      ),
      body: _roster.isEmpty
          ? Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.group_add_outlined,
                      size: 64, color: Colors.grey),
                  const SizedBox(height: 16),
                  const Text('No students added yet.',
                      style: TextStyle(color: Colors.grey)),
                  const SizedBox(height: 8),
                  const Text(
                    'Add students manually or import a CSV file.\nCSV format: reg_number, name (name is optional)',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.grey, fontSize: 12),
                  ),
                ],
              ),
            )
          : ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: _roster.length,
              separatorBuilder: (context, index) => const Divider(height: 1),
              itemBuilder: (context, index) {
                final student = _roster[index];
                final name = student['name'] as String?;
                final reg = student['regNumber'] as String;
                return ListTile(
                  leading: CircleAvatar(
                    backgroundColor: Colors.indigo.shade50,
                    child: Text(
                      '${index + 1}',
                      style: const TextStyle(color: Colors.indigo),
                    ),
                  ),
                  title: Text(
                    name != null && name.isNotEmpty ? name : reg,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  subtitle: name != null && name.isNotEmpty
                      ? Text('Reg: $reg')
                      : null,
                  trailing: student['boundDeviceId'] != null
                      ? const Tooltip(
                          message: 'Device bound',
                          child: Icon(Icons.phonelink_lock,
                              color: Colors.green, size: 20),
                        )
                      : const Tooltip(
                          message: 'Not yet bound',
                          child: Icon(Icons.phonelink_setup,
                              color: Colors.grey, size: 20),
                        ),
                );
              },
            ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _manualAdd,
        icon: const Icon(Icons.person_add),
        label: const Text('Add Student'),
      ),
    );
  }
}
