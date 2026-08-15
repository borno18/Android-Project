import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:smart_proximity_attendance/services/database_helper.dart';
import 'package:smart_proximity_attendance/services/student_import_service.dart';
import 'package:smart_proximity_attendance/screens/enroll_by_session_dialog.dart';
import 'package:smart_proximity_attendance/screens/ocr_scan_review_screen.dart';

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
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadRoster();
  }

  Future<void> _loadRoster() async {
    setState(() => _isLoading = true);
    final roster = await _dbHelper.getRosterForCourse(widget.courseId);
    if (mounted) {
      setState(() {
        _roster = roster;
        _isLoading = false;
      });
    }
  }

  // ── 1. Enroll from Central Database by Session ────────────────────────────

  void _enrollFromCentralDb() async {
    final enrolledCount = await showDialog<int>(
      context: context,
      builder: (context) => EnrollBySessionDialog(
        courseId: widget.courseId,
        courseCode: widget.courseCode,
      ),
    );

    if (enrolledCount != null && enrolledCount > 0) {
      await _loadRoster();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Enrolled $enrolledCount student(s) from Central Database.'),
            backgroundColor: Colors.green.shade700,
          ),
        );
      }
    }
  }

  // ── 2. Scan with Camera OCR ───────────────────────────────────────────────

  void _scanRosterOcr() async {
    final result = await Navigator.push<Map<String, dynamic>>(
      context,
      MaterialPageRoute(
        builder: (context) => OcrScanReviewScreen(
          targetCourseId: widget.courseId,
          targetCourseCode: widget.courseCode,
        ),
      ),
    );

    if (result != null) {
      await _loadRoster();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Enrolled ${result['enrolled']} student(s) from OCR scan into ${widget.courseCode}.',
            ),
            backgroundColor: Colors.green.shade700,
          ),
        );
      }
    }
  }

  // ── 3. Import Excel / CSV File ────────────────────────────────────────────

  void _importSpreadsheet() async {
    FilePickerResult? result = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['csv', 'xlsx', 'xls', 'txt'],
    );

    if (result != null && result.files.single.path != null) {
      final filePath = result.files.single.path!;
      try {
        final parsed = await StudentImportService.parseSpreadsheetOrCsv(filePath);

        if (parsed.isEmpty) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('No valid student records found in file.')),
            );
          }
          return;
        }

        // Also save all parsed students to Central Database
        await _dbHelper.bulkInsertCentralStudents(parsed);

        // Enroll all into this course roster
        int imported = 0;
        for (var s in parsed) {
          final reg = s['regNumber'] ?? '';
          final name = s['name'];
          if (reg.isNotEmpty) {
            await _dbHelper.insertRosterEntry(
              widget.courseId,
              reg,
              name?.isEmpty == true ? null : name,
            );
            imported++;
          }
        }

        await _loadRoster();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'Imported & enrolled $imported student(s) into ${widget.courseCode} (and saved to Central DB).',
              ),
              backgroundColor: Colors.green.shade700,
            ),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error importing file: $e')),
          );
        }
      }
    }
  }

  // ── 4. Manual Add ─────────────────────────────────────────────────────────

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
                hintText: 'e.g. 2023831004',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.numbers),
              ),
              keyboardType: TextInputType.number,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: nameController,
              decoration: const InputDecoration(
                labelText: 'Student Name',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.person_outline),
              ),
              textCapitalization: TextCapitalization.words,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.indigo, foregroundColor: Colors.white),
            child: const Text('Add & Enroll'),
          ),
        ],
      ),
    );

    if (result == true && regController.text.trim().isNotEmpty) {
      final reg = regController.text.trim();
      final name = nameController.text.trim();
      final finalName = name.isEmpty ? null : name;

      // 1. Add to course roster
      await _dbHelper.insertRosterEntry(widget.courseId, reg, finalName);

      // 2. Also save to Central Database
      await _dbHelper.insertOrUpdateCentralStudent(
        regNumber: reg,
        name: finalName ?? reg,
      );

      _loadRoster();
    }
  }

  void _showAddOptionsSheet() {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => Container(
        padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              child: Text(
                'Enroll Students into ${widget.courseCode}',
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
            ),
            const SizedBox(height: 12),
            ListTile(
              leading: Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(color: Colors.indigo.shade50, borderRadius: BorderRadius.circular(10)),
                child: const Icon(Icons.school, color: Colors.indigo),
              ),
              title: const Text('Enroll from Central Database (by Session)', style: TextStyle(fontWeight: FontWeight.w600)),
              subtitle: const Text('Pick students already registered in sessions like 2023-24'),
              onTap: () {
                Navigator.pop(context);
                _enrollFromCentralDb();
              },
            ),
            const Divider(height: 1),
            ListTile(
              leading: Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(color: Colors.green.shade50, borderRadius: BorderRadius.circular(10)),
                child: const Icon(Icons.camera_alt, color: Colors.green),
              ),
              title: const Text('Scan Student List (Camera OCR)', style: TextStyle(fontWeight: FontWeight.w600)),
              subtitle: const Text('Scan paper attendance list offline with phone camera'),
              onTap: () {
                Navigator.pop(context);
                _scanRosterOcr();
              },
            ),
            const Divider(height: 1),
            ListTile(
              leading: Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(color: Colors.teal.shade50, borderRadius: BorderRadius.circular(10)),
                child: const Icon(Icons.upload_file, color: Colors.teal),
              ),
              title: const Text('Import CSV / Excel File', style: TextStyle(fontWeight: FontWeight.w600)),
              subtitle: const Text('Import .xlsx, .xls, or .csv nominal rolls'),
              onTap: () {
                Navigator.pop(context);
                _importSpreadsheet();
              },
            ),
            const Divider(height: 1),
            ListTile(
              leading: Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(color: Colors.purple.shade50, borderRadius: BorderRadius.circular(10)),
                child: const Icon(Icons.person_add, color: Colors.purple),
              ),
              title: const Text('Manual Entry', style: TextStyle(fontWeight: FontWeight.w600)),
              subtitle: const Text('Type registration number and name manually'),
              onTap: () {
                Navigator.pop(context);
                _manualAdd();
              },
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Roster: ${widget.courseCode}'),
        backgroundColor: Colors.indigo,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            onPressed: _enrollFromCentralDb,
            icon: const Icon(Icons.group_add),
            tooltip: 'Enroll from Central DB (by Session)',
          ),
          IconButton(
            onPressed: _scanRosterOcr,
            icon: const Icon(Icons.camera_alt),
            tooltip: 'Scan List (Camera OCR)',
          ),
          IconButton(
            onPressed: _importSpreadsheet,
            icon: const Icon(Icons.upload_file),
            tooltip: 'Import Spreadsheet / CSV',
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _roster.isEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24.0),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.group_add_outlined, size: 64, color: Colors.grey),
                        const SizedBox(height: 16),
                        const Text(
                          'No students enrolled in this course yet.',
                          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                        ),
                        const SizedBox(height: 8),
                        const Text(
                          'Select students from your Central Database by session, or scan a paper list with your phone\'s camera.',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: Colors.grey, fontSize: 13),
                        ),
                        const SizedBox(height: 24),
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton.icon(
                            onPressed: _enrollFromCentralDb,
                            icon: const Icon(Icons.school),
                            label: const Text('Enroll by Session from Central DB'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.indigo,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            ),
                          ),
                        ),
                        const SizedBox(height: 10),
                        Row(
                          children: [
                            Expanded(
                              child: OutlinedButton.icon(
                                onPressed: _scanRosterOcr,
                                icon: const Icon(Icons.camera_alt, size: 18),
                                label: const Text('Camera OCR'),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: OutlinedButton.icon(
                                onPressed: _importSpreadsheet,
                                icon: const Icon(Icons.upload_file, size: 18),
                                label: const Text('Import File'),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                )
              : ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 80),
                  itemCount: _roster.length,
                  separatorBuilder: (context, index) => const Divider(height: 1),
                  itemBuilder: (context, index) {
                    final student = _roster[index];
                    final name = student['name'] as String?;
                    final reg = student['regNumber'] as String;
                    final session = DatabaseHelper.deriveSessionFromRegNumber(reg);

                    return ListTile(
                      leading: CircleAvatar(
                        backgroundColor: Colors.indigo.shade50,
                        child: Text(
                          '${index + 1}',
                          style: const TextStyle(color: Colors.indigo, fontWeight: FontWeight.bold),
                        ),
                      ),
                      title: Text(
                        name != null && name.isNotEmpty ? name : reg,
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                      subtitle: Row(
                        children: [
                          Text('Reg: $reg'),
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                            decoration: BoxDecoration(
                              color: Colors.indigo.shade50,
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              session,
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w600,
                                color: Colors.indigo.shade800,
                              ),
                            ),
                          ),
                        ],
                      ),
                      trailing: student['boundDeviceId'] != null
                          ? const Tooltip(
                              message: 'Device bound',
                              child: Icon(Icons.phonelink_lock, color: Colors.green, size: 20),
                            )
                          : const Tooltip(
                              message: 'Not yet bound',
                              child: Icon(Icons.phonelink_setup, color: Colors.grey, size: 20),
                            ),
                    );
                  },
                ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _showAddOptionsSheet,
        backgroundColor: Colors.indigo,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.person_add),
        label: const Text('Add / Enroll'),
      ),
    );
  }
}
