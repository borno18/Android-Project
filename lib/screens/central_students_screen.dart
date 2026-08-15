import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:smart_proximity_attendance/services/database_helper.dart';
import 'package:smart_proximity_attendance/services/student_import_service.dart';
import 'package:smart_proximity_attendance/screens/ocr_scan_review_screen.dart';

class CentralStudentsScreen extends StatefulWidget {
  const CentralStudentsScreen({super.key});

  @override
  State<CentralStudentsScreen> createState() => _CentralStudentsScreenState();
}

class _CentralStudentsScreenState extends State<CentralStudentsScreen> {
  final DatabaseHelper _dbHelper = DatabaseHelper();

  List<Map<String, dynamic>> _students = [];
  List<Map<String, dynamic>> _sessions = [];
  String _selectedSession = 'All';
  String _sortBy = 'regNumber_asc';
  String _searchQuery = '';
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    final sessions = await _dbHelper.getDistinctSessions();
    final students = await _dbHelper.getCentralStudents(
      sessionFilter: _selectedSession,
      searchQuery: _searchQuery,
      sortBy: _sortBy,
    );

    if (mounted) {
      setState(() {
        _sessions = sessions;
        _students = students;
        _isLoading = false;
      });
    }
  }

  // ── Manual Add Student ───────────────────────────────────────────────────

  void _manualAddStudent() async {
    final regController = TextEditingController();
    final nameController = TextEditingController();
    final sessionController = TextEditingController();

    regController.addListener(() {
      final reg = regController.text.trim();
      sessionController.text = DatabaseHelper.deriveSessionFromRegNumber(reg);
    });

    final result = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
          title: const Row(
            children: [
              Icon(Icons.person_add, color: Colors.indigo),
              SizedBox(width: 8),
              Text('Add Student to Central DB'),
            ],
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: regController,
                  decoration: const InputDecoration(
                    labelText: 'Registration Number *',
                    hintText: 'e.g. 2023831004',
                    prefixIcon: Icon(Icons.numbers, color: Colors.indigo),
                    border: OutlineInputBorder(),
                  ),
                  keyboardType: TextInputType.number,
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: nameController,
                  decoration: const InputDecoration(
                    labelText: 'Student Name *',
                    hintText: 'e.g. Rahim Ahmed',
                    prefixIcon: Icon(Icons.person_outline, color: Colors.indigo),
                    border: OutlineInputBorder(),
                  ),
                  textCapitalization: TextCapitalization.words,
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: sessionController,
                  decoration: const InputDecoration(
                    labelText: 'Session (Auto-derived)',
                    hintText: 'e.g. 2023-24',
                    prefixIcon: Icon(Icons.calendar_month, color: Colors.indigo),
                    border: OutlineInputBorder(),
                    helperText: 'Auto-calculated from Reg No, or edit manually',
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () {
                if (regController.text.trim().isNotEmpty && nameController.text.trim().isNotEmpty) {
                  Navigator.pop(context, true);
                }
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.indigo,
                foregroundColor: Colors.white,
              ),
              child: const Text('Add Student'),
            ),
          ],
        ),
      ),
    );

    if (result == true && regController.text.trim().isNotEmpty) {
      final reg = regController.text.trim();
      final name = nameController.text.trim();
      final session = sessionController.text.trim();

      await _dbHelper.insertOrUpdateCentralStudent(
        regNumber: reg,
        name: name,
        session: session.isNotEmpty ? session : null,
      );
      _loadData();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Added $name ($reg) to Central Database.')),
        );
      }
    }
  }

  // ── Edit Student ─────────────────────────────────────────────────────────

  void _editStudent(Map<String, dynamic> student) async {
    final id = student['id'] as int;
    final regController = TextEditingController(text: student['regNumber'] as String);
    final nameController = TextEditingController(text: student['name'] as String);
    final sessionController = TextEditingController(text: student['session'] as String);

    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: const Row(
          children: [
            Icon(Icons.edit, color: Colors.indigo),
            SizedBox(width: 8),
            Text('Edit Student Profile'),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: regController,
                decoration: const InputDecoration(
                  labelText: 'Registration Number *',
                  border: OutlineInputBorder(),
                ),
                keyboardType: TextInputType.number,
              ),
              const SizedBox(height: 12),
              TextField(
                controller: nameController,
                decoration: const InputDecoration(
                  labelText: 'Student Name *',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: sessionController,
                decoration: const InputDecoration(
                  labelText: 'Session',
                  border: OutlineInputBorder(),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () {
              if (regController.text.trim().isNotEmpty && nameController.text.trim().isNotEmpty) {
                Navigator.pop(context, true);
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.indigo,
              foregroundColor: Colors.white,
            ),
            child: const Text('Save Changes'),
          ),
        ],
      ),
    );

    if (result == true) {
      await _dbHelper.updateCentralStudent(
        id: id,
        regNumber: regController.text.trim(),
        name: nameController.text.trim(),
        session: sessionController.text.trim(),
      );
      _loadData();
    }
  }

  // ── Delete Student ───────────────────────────────────────────────────────

  void _deleteStudent(Map<String, dynamic> student) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: const Text('Delete Student?'),
        content: Text('Remove ${student['name']} (${student['regNumber']}) from the Central Database?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      await _dbHelper.deleteCentralStudent(student['id'] as int);
      _loadData();
    }
  }

  // ── Import CSV / Excel File ──────────────────────────────────────────────

  void _importSpreadsheetFile() async {
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

        if (!mounted) return;

        // Show preview & confirmation modal
        final confirmed = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
            title: Row(
              children: [
                const Icon(Icons.file_present, color: Colors.indigo),
                const SizedBox(width: 8),
                Text('Import ${parsed.length} Students?'),
              ],
            ),
            content: SizedBox(
              width: double.maxFinite,
              height: 300,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Found ${parsed.length} student(s) in spreadsheet. Preview:'),
                  const SizedBox(height: 8),
                  Expanded(
                    child: ListView.builder(
                      itemCount: parsed.length,
                      itemBuilder: (context, index) {
                        final s = parsed[index];
                        return ListTile(
                          dense: true,
                          title: Text(s['name'] ?? ''),
                          subtitle: Text('Reg: ${s['regNumber']} • Session: ${s['session']}'),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
              ElevatedButton(
                onPressed: () => Navigator.pop(context, true),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.indigo,
                  foregroundColor: Colors.white,
                ),
                child: Text('Import All (${parsed.length})'),
              ),
            ],
          ),
        );

        if (confirmed == true) {
          final count = await _dbHelper.bulkInsertCentralStudents(parsed);
          _loadData();
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Successfully imported $count student(s) into Central Database.')),
            );
          }
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Failed to read spreadsheet file: $e')),
          );
        }
      }
    }
  }

  // ── OCR Camera Scan ──────────────────────────────────────────────────────

  void _scanWithCameraOcr() async {
    final result = await Navigator.push<Map<String, dynamic>>(
      context,
      MaterialPageRoute(builder: (context) => const OcrScanReviewScreen()),
    );

    if (result != null) {
      _loadData();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Saved ${result['savedCentral']} student(s) from OCR scan to Central DB.'),
          ),
        );
      }
    }
  }

  // ── Show Add / Import Menu Bottom Sheet ──────────────────────────────────

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
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              child: Text(
                'Add Students to Central Database',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
            ),
            const SizedBox(height: 12),
            ListTile(
              leading: Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(color: Colors.indigo.shade50, borderRadius: BorderRadius.circular(10)),
                child: const Icon(Icons.camera_alt, color: Colors.indigo),
              ),
              title: const Text('Scan Student List (Camera OCR)', style: TextStyle(fontWeight: FontWeight.w600)),
              subtitle: const Text('Scan paper attendance sheets using Google ML Kit offline OCR'),
              onTap: () {
                Navigator.pop(context);
                _scanWithCameraOcr();
              },
            ),
            const Divider(height: 1),
            ListTile(
              leading: Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(color: Colors.teal.shade50, borderRadius: BorderRadius.circular(10)),
                child: const Icon(Icons.upload_file, color: Colors.teal),
              ),
              title: const Text('Import CSV / Excel Spreadsheet', style: TextStyle(fontWeight: FontWeight.w600)),
              subtitle: const Text('Import .xlsx, .xls, or .csv student nominal rolls'),
              onTap: () {
                Navigator.pop(context);
                _importSpreadsheetFile();
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
              subtitle: const Text('Type registration number and name directly'),
              onTap: () {
                Navigator.pop(context);
                _manualAddStudent();
              },
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final totalStudents = _sessions.fold<int>(0, (sum, s) => sum + (s['studentCount'] as int? ?? 0));

    return Scaffold(
      backgroundColor: Colors.grey.shade50,
      appBar: AppBar(
        title: const Text('Central Student Directory'),
        backgroundColor: Colors.indigo,
        foregroundColor: Colors.white,
        elevation: 0,
        actions: [
          PopupMenuButton<String>(
            icon: const Icon(Icons.sort),
            tooltip: 'Sort Options',
            onSelected: (val) {
              setState(() => _sortBy = val);
              _loadData();
            },
            itemBuilder: (context) => const [
              PopupMenuItem(value: 'regNumber_asc', child: Text('Reg Number (Ascending)')),
              PopupMenuItem(value: 'regNumber_desc', child: Text('Reg Number (Descending)')),
              PopupMenuItem(value: 'name_asc', child: Text('Name (A → Z)')),
              PopupMenuItem(value: 'name_desc', child: Text('Name (Z → A)')),
            ],
          ),
          IconButton(
            onPressed: _showAddOptionsSheet,
            icon: const Icon(Icons.add_circle_outline),
            tooltip: 'Add / Import Students',
          ),
        ],
      ),
      body: Column(
        children: [
          // Top Stats Bar & Search
          Container(
            color: Colors.white,
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
            child: Column(
              children: [
                // Search Input
                TextField(
                  decoration: InputDecoration(
                    hintText: 'Search by student name or reg number...',
                    prefixIcon: const Icon(Icons.search, color: Colors.indigo),
                    suffixIcon: _searchQuery.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.clear),
                            onPressed: () {
                              setState(() => _searchQuery = '');
                              _loadData();
                            },
                          )
                        : null,
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                    filled: true,
                    fillColor: Colors.grey.shade50,
                  ),
                  onChanged: (val) {
                    setState(() => _searchQuery = val);
                    _loadData();
                  },
                ),
                const SizedBox(height: 10),

                // Sessions Filter Horizontal Chips
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      Padding(
                        padding: const EdgeInsets.only(right: 6),
                        child: FilterChip(
                          label: Text('All ($totalStudents)'),
                          selected: _selectedSession == 'All',
                          selectedColor: Colors.indigo.shade100,
                          labelStyle: TextStyle(
                            color: _selectedSession == 'All' ? Colors.indigo.shade900 : Colors.black87,
                            fontWeight: _selectedSession == 'All' ? FontWeight.bold : FontWeight.normal,
                          ),
                          onSelected: (selected) {
                            setState(() => _selectedSession = 'All');
                            _loadData();
                          },
                        ),
                      ),
                      ..._sessions.map((s) {
                        final sessionName = s['session'] as String;
                        final count = s['studentCount'] ?? 0;
                        final isSelected = _selectedSession == sessionName;
                        return Padding(
                          padding: const EdgeInsets.only(right: 6),
                          child: FilterChip(
                            label: Text('$sessionName ($count)'),
                            selected: isSelected,
                            selectedColor: Colors.indigo.shade100,
                            labelStyle: TextStyle(
                              color: isSelected ? Colors.indigo.shade900 : Colors.black87,
                              fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                            ),
                            onSelected: (selected) {
                              setState(() => _selectedSession = sessionName);
                              _loadData();
                            },
                          ),
                        );
                      }),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // Students List
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _students.isEmpty
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.all(24),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.people_outline, size: 64, color: Colors.grey),
                              const SizedBox(height: 16),
                              Text(
                                _searchQuery.isNotEmpty
                                    ? 'No students found matching "$_searchQuery"'
                                    : 'No students in Central Database yet',
                                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                              ),
                              const SizedBox(height: 8),
                              const Text(
                                'Add students once to your central database, and easily enroll them into any course by session.',
                                textAlign: TextAlign.center,
                                style: TextStyle(color: Colors.grey),
                              ),
                              const SizedBox(height: 20),
                              ElevatedButton.icon(
                                onPressed: _showAddOptionsSheet,
                                icon: const Icon(Icons.add),
                                label: const Text('Add / Import Students'),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.indigo,
                                  foregroundColor: Colors.white,
                                ),
                              ),
                            ],
                          ),
                        ),
                      )
                    : RefreshIndicator(
                        onRefresh: _loadData,
                        child: ListView.separated(
                          padding: const EdgeInsets.fromLTRB(16, 12, 16, 80),
                          itemCount: _students.length,
                          separatorBuilder: (context, index) => const SizedBox(height: 8),
                          itemBuilder: (context, index) {
                            final student = _students[index];
                            final reg = student['regNumber'] as String;
                            final name = student['name'] as String;
                            final session = student['session'] as String? ?? 'General';

                            return Card(
                              elevation: 0,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                                side: BorderSide(color: Colors.grey.shade200),
                              ),
                              child: ListTile(
                                contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                                leading: CircleAvatar(
                                  backgroundColor: Colors.indigo.shade50,
                                  child: Text(
                                    name.isNotEmpty ? name.substring(0, 1).toUpperCase() : 'S',
                                    style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                      color: Colors.indigo,
                                    ),
                                  ),
                                ),
                                title: Text(
                                  name,
                                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                                ),
                                subtitle: Row(
                                  children: [
                                    Text('Reg: $reg', style: TextStyle(color: Colors.grey.shade700, fontSize: 13)),
                                    const SizedBox(width: 8),
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                      decoration: BoxDecoration(
                                        color: Colors.indigo.shade50,
                                        borderRadius: BorderRadius.circular(4),
                                      ),
                                      child: Text(
                                        session,
                                        style: TextStyle(
                                          fontSize: 11,
                                          fontWeight: FontWeight.w600,
                                          color: Colors.indigo.shade800,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                trailing: PopupMenuButton<String>(
                                  icon: const Icon(Icons.more_vert, color: Colors.grey),
                                  onSelected: (action) {
                                    if (action == 'edit') {
                                      _editStudent(student);
                                    } else if (action == 'delete') {
                                      _deleteStudent(student);
                                    }
                                  },
                                  itemBuilder: (context) => [
                                    const PopupMenuItem(
                                      value: 'edit',
                                      child: Row(
                                        children: [
                                          Icon(Icons.edit_outlined, size: 18, color: Colors.indigo),
                                          SizedBox(width: 8),
                                          Text('Edit Profile'),
                                        ],
                                      ),
                                    ),
                                    const PopupMenuItem(
                                      value: 'delete',
                                      child: Row(
                                        children: [
                                          Icon(Icons.delete_outline, size: 18, color: Colors.red),
                                          SizedBox(width: 8),
                                          Text('Delete Student', style: TextStyle(color: Colors.red)),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                      ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _showAddOptionsSheet,
        backgroundColor: Colors.indigo,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.person_add),
        label: const Text('Add / Import'),
      ),
    );
  }
}
