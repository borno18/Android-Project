import 'package:flutter/material.dart';
import 'package:smart_proximity_attendance/services/database_helper.dart';

class EnrollBySessionDialog extends StatefulWidget {
  final int courseId;
  final String courseCode;

  const EnrollBySessionDialog({
    super.key,
    required this.courseId,
    required this.courseCode,
  });

  @override
  State<EnrollBySessionDialog> createState() => _EnrollBySessionDialogState();
}

class _EnrollBySessionDialogState extends State<EnrollBySessionDialog> {
  final DatabaseHelper _dbHelper = DatabaseHelper();

  List<Map<String, dynamic>> _sessions = [];
  String? _selectedSession;
  List<Map<String, dynamic>> _studentsInSession = [];
  Set<String> _alreadyEnrolledRegs = {};
  final Set<String> _selectedRegs = {};
  String _searchQuery = '';
  bool _isLoading = true;
  bool _isEnrolling = false;

  @override
  void initState() {
    super.initState();
    _loadInitialData();
  }

  Future<void> _loadInitialData() async {
    setState(() => _isLoading = true);
    final sessions = await _dbHelper.getDistinctSessions();
    final alreadyEnrolled = await _dbHelper.getEnrolledRegNumbersForCourse(widget.courseId);

    String? defaultSession;
    if (sessions.isNotEmpty) {
      defaultSession = sessions.first['session'] as String;
    }

    if (mounted) {
      setState(() {
        _sessions = sessions;
        _alreadyEnrolledRegs = alreadyEnrolled;
        _selectedSession = defaultSession;
        _isLoading = false;
      });

      if (defaultSession != null) {
        _loadStudentsForSession(defaultSession);
      }
    }
  }

  Future<void> _loadStudentsForSession(String session) async {
    final students = await _dbHelper.getCentralStudents(
      sessionFilter: session,
      sortBy: 'regNumber_asc',
    );

    if (mounted) {
      setState(() {
        _studentsInSession = students;
        // Auto-select all students who are not already enrolled
        _selectedRegs.clear();
        for (final s in students) {
          final reg = (s['regNumber'] as String).trim();
          if (!_alreadyEnrolledRegs.contains(reg)) {
            _selectedRegs.add(reg);
          }
        }
      });
    }
  }

  void _onSessionChanged(String? newSession) {
    if (newSession != null && newSession != _selectedSession) {
      setState(() {
        _selectedSession = newSession;
      });
      _loadStudentsForSession(newSession);
    }
  }

  void _toggleSelectAll() {
    final availableToSelect = _filteredStudents
        .map((s) => (s['regNumber'] as String).trim())
        .where((reg) => !_alreadyEnrolledRegs.contains(reg))
        .toList();

    final allSelected = availableToSelect.every((reg) => _selectedRegs.contains(reg));

    setState(() {
      if (allSelected) {
        for (final reg in availableToSelect) {
          _selectedRegs.remove(reg);
        }
      } else {
        _selectedRegs.addAll(availableToSelect);
      }
    });
  }

  List<Map<String, dynamic>> get _filteredStudents {
    if (_searchQuery.trim().isEmpty) return _studentsInSession;
    final q = _searchQuery.toLowerCase().trim();
    return _studentsInSession.where((s) {
      final reg = (s['regNumber'] as String).toLowerCase();
      final name = (s['name'] as String).toLowerCase();
      return reg.contains(q) || name.contains(q);
    }).toList();
  }

  Future<void> _enrollSelected() async {
    if (_selectedRegs.isEmpty) return;

    setState(() => _isEnrolling = true);

    try {
      final enrolledCount = await _dbHelper.enrollStudentsFromCentralDb(
        widget.courseId,
        _selectedRegs.toList(),
      );

      if (mounted) {
        setState(() => _isEnrolling = false);
        Navigator.pop(context, enrolledCount);
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isEnrolling = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to enroll students: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Container(
        constraints: const BoxConstraints(maxHeight: 650, maxWidth: 500),
        child: Column(
          children: [
            // Header
            Container(
              padding: const EdgeInsets.fromLTRB(20, 16, 16, 16),
              decoration: BoxDecoration(
                color: Colors.indigo,
                borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.group_add, color: Colors.white),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Enroll by Session',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Text(
                          'Course: ${widget.courseCode}',
                          style: const TextStyle(color: Colors.white70, fontSize: 13),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close, color: Colors.white),
                  ),
                ],
              ),
            ),

            // Content
            Expanded(
              child: _isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : _sessions.isEmpty
                      ? Center(
                          child: Padding(
                            padding: const EdgeInsets.all(24),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(Icons.person_off_outlined, size: 48, color: Colors.grey),
                                const SizedBox(height: 12),
                                const Text(
                                  'Central Student Database is Empty',
                                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                                ),
                                const SizedBox(height: 8),
                                const Text(
                                  'Please add students in the Central Student Directory first (via Manual Add, CSV/Excel, or Camera OCR).',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(color: Colors.grey, fontSize: 13),
                                ),
                              ],
                            ),
                          ),
                        )
                      : Column(
                          children: [
                            // Session selector & Search
                            Padding(
                              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                              child: Column(
                                children: [
                                  DropdownButtonFormField<String>(
                                    initialValue: _selectedSession,
                                    decoration: InputDecoration(
                                      labelText: 'Select Student Session',
                                      prefixIcon: const Icon(Icons.calendar_month, color: Colors.indigo),
                                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                                    ),
                                    items: _sessions.map((s) {
                                      final sessionName = s['session'] as String;
                                      final count = s['studentCount'] ?? 0;
                                      return DropdownMenuItem(
                                        value: sessionName,
                                        child: Text('$sessionName ($count students)'),
                                      );
                                    }).toList(),
                                    onChanged: _onSessionChanged,
                                  ),
                                  const SizedBox(height: 10),
                                  TextField(
                                    decoration: InputDecoration(
                                      hintText: 'Search by name or reg number...',
                                      prefixIcon: const Icon(Icons.search, size: 20),
                                      isDense: true,
                                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                                    ),
                                    onChanged: (val) => setState(() => _searchQuery = val),
                                  ),
                                ],
                              ),
                            ),

                            // Stats & Select All Toolbar
                            Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                              child: Row(
                                children: [
                                  Text(
                                    '${_selectedRegs.length} of ${_filteredStudents.length} selected',
                                    style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                                  ),
                                  const Spacer(),
                                  TextButton.icon(
                                    onPressed: _toggleSelectAll,
                                    icon: const Icon(Icons.done_all, size: 16),
                                    label: const Text('Toggle All', style: TextStyle(fontSize: 12)),
                                  ),
                                ],
                              ),
                            ),
                            const Divider(height: 1),

                            // Students List
                            Expanded(
                              child: _filteredStudents.isEmpty
                                  ? const Center(
                                      child: Text(
                                        'No students found matching filters.',
                                        style: TextStyle(color: Colors.grey),
                                      ),
                                    )
                                  : ListView.separated(
                                      padding: const EdgeInsets.symmetric(vertical: 4),
                                      itemCount: _filteredStudents.length,
                                      separatorBuilder: (context, index) => const Divider(height: 1),
                                      itemBuilder: (context, index) {
                                        final s = _filteredStudents[index];
                                        final reg = (s['regNumber'] as String).trim();
                                        final name = s['name'] as String;
                                        final isAlreadyEnrolled = _alreadyEnrolledRegs.contains(reg);
                                        final isSelected = _selectedRegs.contains(reg);

                                        return CheckboxListTile(
                                          value: isAlreadyEnrolled ? true : isSelected,
                                          activeColor: isAlreadyEnrolled ? Colors.grey : Colors.indigo,
                                          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 0),
                                          title: Row(
                                            children: [
                                              Expanded(
                                                child: Text(
                                                  name,
                                                  style: TextStyle(
                                                    fontWeight: FontWeight.w600,
                                                    color: isAlreadyEnrolled ? Colors.grey : Colors.black87,
                                                  ),
                                                ),
                                              ),
                                              if (isAlreadyEnrolled)
                                                Container(
                                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                                  decoration: BoxDecoration(
                                                    color: Colors.green.shade50,
                                                    borderRadius: BorderRadius.circular(10),
                                                    border: Border.all(color: Colors.green.shade300),
                                                  ),
                                                  child: const Text(
                                                    'Enrolled',
                                                    style: TextStyle(
                                                      color: Colors.green,
                                                      fontSize: 11,
                                                      fontWeight: FontWeight.bold,
                                                    ),
                                                  ),
                                                ),
                                            ],
                                          ),
                                          subtitle: Text(
                                            'Reg: $reg',
                                            style: TextStyle(color: isAlreadyEnrolled ? Colors.grey : Colors.grey.shade700),
                                          ),
                                          onChanged: isAlreadyEnrolled
                                              ? null
                                              : (val) {
                                                  setState(() {
                                                    if (val == true) {
                                                      _selectedRegs.add(reg);
                                                    } else {
                                                      _selectedRegs.remove(reg);
                                                    }
                                                  });
                                                },
                                        );
                                      },
                                    ),
                            ),
                          ],
                        ),
            ),

            // Footer action
            if (_sessions.isNotEmpty)
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.grey.shade50,
                  borderRadius: const BorderRadius.vertical(bottom: Radius.circular(20)),
                  border: Border(top: BorderSide(color: Colors.grey.shade200)),
                ),
                child: Row(
                  children: [
                    TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('Cancel'),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: _isEnrolling || _selectedRegs.isEmpty ? null : _enrollSelected,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.indigo,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        icon: _isEnrolling
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                              )
                            : const Icon(Icons.person_add_alt_1),
                        label: Text(
                          'Enroll ${_selectedRegs.length} Student(s)',
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}
