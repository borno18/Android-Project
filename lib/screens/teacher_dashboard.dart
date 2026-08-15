import 'package:flutter/material.dart';
import 'package:smart_proximity_attendance/services/database_helper.dart';
import 'package:smart_proximity_attendance/screens/course_management_screen.dart';
import 'package:smart_proximity_attendance/screens/central_students_screen.dart';
import 'package:smart_proximity_attendance/screens/live_session_screen.dart';
import 'package:smart_proximity_attendance/screens/report_screen.dart';
import 'package:smart_proximity_attendance/screens/course_report_screen.dart';
import 'package:intl/intl.dart';

class TeacherDashboard extends StatefulWidget {
  const TeacherDashboard({super.key});

  @override
  State<TeacherDashboard> createState() => _TeacherDashboardState();
}

class _TeacherDashboardState extends State<TeacherDashboard>
    with SingleTickerProviderStateMixin {
  final DatabaseHelper _dbHelper = DatabaseHelper();
  List<Map<String, dynamic>> _sessions = [];
  List<Map<String, dynamic>> _courses = [];
  List<Map<String, dynamic>> _activeSessions = [];

  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _loadData();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    final sessions = await _dbHelper.getSessionsWithCourse();
    final courses = await _dbHelper.getCourses();
    final active = await _dbHelper.getActiveSessions();
    if (mounted) {
      setState(() {
        _sessions = sessions;
        _courses = courses;
        _activeSessions = active;
      });
    }
  }

  void _startNewSession() async {
    if (_courses.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Please create a course first.')));
      return;
    }

    // Check if there is already an active session
    if (_activeSessions.isNotEmpty) {
      final active = _activeSessions.first;
      final proceed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
          title: const Row(
            children: [
              Icon(Icons.warning_amber_rounded, color: Colors.orange),
              SizedBox(width: 8),
              Text('Active Session Found'),
            ],
          ),
          content: Text(
            'You already have an active session for ${active['courseCode']} (Room ${active['roomNumber']}).\n\nWould you like to resume it, or start a new session anyway?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Start New Anyway'),
            ),
            ElevatedButton(
              onPressed: () {
                Navigator.pop(context, true);
                _resumeActiveSession(active);
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.indigo,
                foregroundColor: Colors.white,
              ),
              child: const Text('Resume Active Session'),
            ),
          ],
        ),
      );
      if (proceed == true) return;
    }

    if (!mounted) return;

    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (context) => _NewSessionDialog(courses: _courses),
    );

    if (result != null) {
      final codeDuration = (result['codeDuration'] as int?) ?? 60;
      final sessionId = await _dbHelper.startSession(
        result['courseId'],
        result['roomNumber'],
        codeDuration: codeDuration,
      );

      if (mounted) {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => LiveSessionScreen(
              sessionId: sessionId,
              courseId: result['courseId'],
              courseCode: result['courseCode'],
              codeDurationSeconds: codeDuration,
            ),
          ),
        ).then((_) => _loadData());
      }
    }
  }

  void _resumeActiveSession(Map<String, dynamic> session) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => LiveSessionScreen(
          sessionId: session['id'] as int,
          courseId: session['courseId'] as int,
          courseCode: session['courseCode'] as String,
          codeDurationSeconds: session['codeDuration'] as int? ?? 60,
        ),
      ),
    ).then((_) => _loadData());
  }

  Future<void> _finishActiveSession(Map<String, dynamic> session) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: const Text('Finish Attendance Session?'),
        content: Text('This will complete the session for ${session['courseCode']} and open its report.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.indigo, foregroundColor: Colors.white),
            child: const Text('Finish & View Report'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      final sessionId = session['id'] as int;
      await _dbHelper.endSession(sessionId);
      final updated = await _dbHelper.getSessionById(sessionId);
      if (mounted) {
        _loadData();
        if (updated != null) {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (context) => ReportScreen(session: updated)),
          );
        }
      }
    }
  }

  Future<void> _logout() async {
    if (_activeSessions.isNotEmpty) {
      final confirm = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
          title: const Row(
            children: [
              Icon(Icons.info_outline, color: Colors.indigo),
              SizedBox(width: 8),
              Text('Log Out'),
            ],
          ),
          content: const Text(
            'You have an attendance session in progress.\n\nYour session and recorded student attendance are safely saved. You can resume it anytime when you return.',
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
            ElevatedButton(
              onPressed: () => Navigator.pop(context, true),
              style: ElevatedButton.styleFrom(backgroundColor: Colors.indigo, foregroundColor: Colors.white),
              child: const Text('Log Out'),
            ),
          ],
        ),
      );
      if (confirm != true) return;
    }

    if (mounted) {
      Navigator.pushNamedAndRemoveUntil(context, '/', (route) => false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey.shade50,
      appBar: AppBar(
        title: const Text('Teacher Dashboard'),
        backgroundColor: Colors.indigo,
        foregroundColor: Colors.white,
        elevation: 0,
        actions: [
          IconButton(
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(
                  builder: (context) => const CentralStudentsScreen()),
            ).then((_) => _loadData()),
            icon: const Icon(Icons.people_alt_outlined),
            tooltip: 'Central Student Directory',
          ),
          IconButton(
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(
                  builder: (context) => const CourseManagementScreen()),
            ).then((_) => _loadData()),
            icon: const Icon(Icons.book_outlined),
            tooltip: 'Manage Courses',
          ),
          IconButton(
            onPressed: _logout,
            icon: const Icon(Icons.logout),
            tooltip: 'Logout',
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: Colors.white,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white70,
          tabs: const [
            Tab(icon: Icon(Icons.history), text: 'Session History'),
            Tab(icon: Icon(Icons.analytics_outlined), text: 'Course Reports'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildSessionHistoryTab(),
          _buildCourseReportsTab(),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _startNewSession,
        backgroundColor: Colors.indigo,
        foregroundColor: Colors.white,
        label: const Text('Start Attendance'),
        icon: const Icon(Icons.add),
      ),
    );
  }

  // ── Session History Tab ─────────────────────────────────────────────────────

  Widget _buildSessionHistoryTab() {
    return RefreshIndicator(
      onRefresh: _loadData,
      child: CustomScrollView(
        slivers: [
          // ── Active Sessions Section (Persistent Banner / Card) ────────────
          if (_activeSessions.isNotEmpty)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 10,
                          height: 10,
                          decoration: const BoxDecoration(
                            color: Colors.green,
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 8),
                        const Text(
                          'IN PROGRESS / ACTIVE SESSION',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 13,
                            color: Colors.green,
                            letterSpacing: 0.5,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    ..._activeSessions.map((session) {
                      final date = DateTime.parse(session['startTime'] as String);
                      final present = session['presentCount'] ?? 0;
                      final enrolled = session['enrolledCount'] ?? 0;
                      return Container(
                        margin: const EdgeInsets.only(bottom: 8),
                        decoration: BoxDecoration(
                          color: const Color(0xFFE8F5E9),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: Colors.green.shade300, width: 1.5),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.green.withValues(alpha: 0.1),
                              blurRadius: 10,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        session['courseCode'] as String,
                                        style: const TextStyle(
                                          fontWeight: FontWeight.bold,
                                          fontSize: 18,
                                          color: Colors.green,
                                        ),
                                      ),
                                      Text(
                                        '${session['courseName']} • Room ${session['roomNumber']}',
                                        style: TextStyle(
                                          color: Colors.grey.shade700,
                                          fontSize: 13,
                                        ),
                                      ),
                                      Text(
                                        'Started: ${DateFormat('hh:mm a').format(date)}',
                                        style: TextStyle(
                                          color: Colors.grey.shade600,
                                          fontSize: 12,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                  decoration: BoxDecoration(
                                    color: Colors.white,
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(color: Colors.green.shade200),
                                  ),
                                  child: Column(
                                    children: [
                                      Text(
                                        '$present / $enrolled',
                                        style: const TextStyle(
                                          fontWeight: FontWeight.bold,
                                          fontSize: 16,
                                          color: Colors.green,
                                        ),
                                      ),
                                      const Text(
                                        'Checked In',
                                        style: TextStyle(fontSize: 10, color: Colors.grey),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 14),
                            Row(
                              children: [
                                Expanded(
                                  child: ElevatedButton.icon(
                                    onPressed: () => _resumeActiveSession(session),
                                    icon: const Icon(Icons.play_arrow),
                                    label: const Text('Resume Attendance'),
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: Colors.green.shade700,
                                      foregroundColor: Colors.white,
                                      padding: const EdgeInsets.symmetric(vertical: 12),
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(10),
                                      ),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                OutlinedButton.icon(
                                  onPressed: () => _finishActiveSession(session),
                                  icon: const Icon(Icons.check_circle_outline),
                                  label: const Text('Finish'),
                                  style: OutlinedButton.styleFrom(
                                    foregroundColor: Colors.indigo,
                                    side: const BorderSide(color: Colors.indigo),
                                    padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      );
                    }),
                    const Divider(height: 24),
                  ],
                ),
              ),
            ),

          // ── Past Sessions Header ──────────────────────────────────────────
          const SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.fromLTRB(16, 8, 16, 8),
              child: Text(
                'Past Sessions',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 15,
                  color: Colors.indigo,
                ),
              ),
            ),
          ),

          // ── Sessions List ────────────────────────────────────────────────
          if (_sessions.isEmpty)
            const SliverFillRemaining(
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.history, size: 56, color: Colors.grey),
                    SizedBox(height: 12),
                    Text('No attendance sessions yet.',
                        style: TextStyle(color: Colors.grey)),
                  ],
                ),
              ),
            )
          else
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 80),
              sliver: SliverList(
                delegate: SliverChildBuilderDelegate(
                  (context, index) {
                    final session = _sessions[index];
                    final date = DateTime.parse(session['startTime'] as String);
                    final isSessionActive = session['isActive'] == 1;

                    return Card(
                      margin: const EdgeInsets.only(bottom: 10),
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        side: BorderSide(
                          color: isSessionActive ? Colors.green.shade300 : Colors.grey.shade200,
                          width: isSessionActive ? 1.5 : 1.0,
                        ),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: ListTile(
                        contentPadding:
                            const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        leading: Container(
                          width: 44,
                          height: 44,
                          decoration: BoxDecoration(
                            color: isSessionActive ? Colors.green.shade50 : Colors.indigo.shade50,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Icon(
                            isSessionActive ? Icons.sensors : Icons.class_outlined,
                            color: isSessionActive ? Colors.green : Colors.indigo,
                          ),
                        ),
                        title: Row(
                          children: [
                            Text(session['courseCode'] as String,
                                style: const TextStyle(fontWeight: FontWeight.bold)),
                            if (isSessionActive) ...[
                              const SizedBox(width: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: Colors.green.shade100,
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: const Text(
                                  'ACTIVE',
                                  style: TextStyle(
                                    color: Colors.green,
                                    fontSize: 10,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                        subtitle: Text(
                          '${session['courseName']}  •  Room ${session['roomNumber']}\n${DateFormat('EEE, MMM dd  •  hh:mm a').format(date)}',
                        ),
                        isThreeLine: true,
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () {
                          if (isSessionActive) {
                            _resumeActiveSession(session);
                          } else {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                  builder: (context) =>
                                      ReportScreen(session: session)),
                            ).then((_) => _loadData());
                          }
                        },
                      ),
                    );
                  },
                  childCount: _sessions.length,
                ),
              ),
            ),
        ],
      ),
    );
  }

  // ── Course Reports Tab ──────────────────────────────────────────────────────

  Widget _buildCourseReportsTab() {
    if (_courses.isEmpty) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.analytics_outlined, size: 56, color: Colors.grey),
            SizedBox(height: 12),
            Text('No courses yet. Create a course first.',
                style: TextStyle(color: Colors.grey)),
          ],
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: _loadData,
      child: ListView.builder(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 80),
        itemCount: _courses.length,
        itemBuilder: (context, index) {
          final course = _courses[index];
          return Card(
            margin: const EdgeInsets.only(bottom: 10),
            elevation: 0,
            shape: RoundedRectangleBorder(
              side: BorderSide(color: Colors.grey.shade200),
              borderRadius: BorderRadius.circular(14),
            ),
            child: ListTile(
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              leading: Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      Colors.indigo.shade400,
                      Colors.indigo.shade700,
                    ],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.bar_chart, color: Colors.white),
              ),
              title: Text(course['code'] as String,
                  style: const TextStyle(fontWeight: FontWeight.bold)),
              subtitle: Text(course['name'] as String),
              trailing: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('View Report',
                      style: TextStyle(
                          color: Colors.indigo,
                          fontSize: 12,
                          fontWeight: FontWeight.w600)),
                  SizedBox(width: 4),
                  Icon(Icons.chevron_right, color: Colors.indigo),
                ],
              ),
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) =>
                        CourseReportScreen(course: course),
                  ),
                );
              },
            ),
          );
        },
      ),
    );
  }
}

// ─── New Session Dialog ────────────────────────────────────────────────────────

class _NewSessionDialog extends StatefulWidget {
  final List<Map<String, dynamic>> courses;
  const _NewSessionDialog({required this.courses});

  @override
  State<_NewSessionDialog> createState() => _NewSessionDialogState();
}

class _NewSessionDialogState extends State<_NewSessionDialog> {
  int? _selectedCourseId;
  final _roomController = TextEditingController();
  int _selectedDuration = 60; // default 60 seconds
  late TextEditingController _durationController;
  bool _isCustomDuration = false;

  final List<int> _presetDurations = [30, 45, 60, 90, 120, 180, 300];

  @override
  void initState() {
    super.initState();
    _durationController = TextEditingController(text: '$_selectedDuration');
  }

  @override
  void dispose() {
    _roomController.dispose();
    _durationController.dispose();
    super.dispose();
  }

  String _formatDurationLabel(int seconds) {
    if (seconds < 60) return '${seconds}s';
    final mins = seconds ~/ 60;
    final rem = seconds % 60;
    return rem == 0 ? '${mins}m' : '${mins}m ${rem}s';
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      title: const Row(
        children: [
          Icon(Icons.add_task, color: Colors.indigo),
          SizedBox(width: 8),
          Text('New Attendance Session'),
        ],
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            DropdownButtonFormField<int>(
              decoration: InputDecoration(
                labelText: 'Select Course',
                prefixIcon: const Icon(Icons.school_outlined, color: Colors.indigo),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              ),
              items: widget.courses
                  .map((c) => DropdownMenuItem(
                        value: c['id'] as int,
                        child: Text('${c['code']} - ${c['name']}'),
                      ))
                  .toList(),
              onChanged: (val) => setState(() => _selectedCourseId = val),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: _roomController,
              decoration: InputDecoration(
                labelText: 'Room Number',
                hintText: 'e.g. 302 or Lab 4',
                prefixIcon: const Icon(Icons.room_outlined, color: Colors.indigo),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
            const SizedBox(height: 20),

            // ── Class Code Change Duration ──────────────────────────────────
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.indigo.shade50.withValues(alpha: 0.5),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: Colors.indigo.shade100),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.timer_outlined, size: 18, color: Colors.indigo),
                      const SizedBox(width: 6),
                      const Text(
                        'Class Code Changing Duration',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
                          color: Colors.indigo,
                        ),
                      ),
                      const Spacer(),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: Colors.indigo,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          _formatDurationLabel(_selectedDuration),
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 12,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'The PIN changes automatically every ${_selectedDuration}s to prevent proxy attendance.',
                    style: TextStyle(fontSize: 11, color: Colors.grey.shade700),
                  ),
                  const SizedBox(height: 10),

                  // Preset Chips
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      ..._presetDurations.map((d) {
                        final isSelected = !_isCustomDuration && _selectedDuration == d;
                        return ChoiceChip(
                          label: Text(
                            d == 60 ? '60s (Recommended)' : _formatDurationLabel(d),
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                              color: isSelected ? Colors.white : Colors.indigo.shade900,
                            ),
                          ),
                          selected: isSelected,
                          selectedColor: Colors.indigo,
                          backgroundColor: Colors.white,
                          onSelected: (selected) {
                            if (selected) {
                              setState(() {
                                _isCustomDuration = false;
                                _selectedDuration = d;
                                _durationController.text = '$d';
                              });
                            }
                          },
                        );
                      }),
                      ChoiceChip(
                        label: Text(
                          'Custom',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: _isCustomDuration ? FontWeight.bold : FontWeight.normal,
                            color: _isCustomDuration ? Colors.white : Colors.indigo.shade900,
                          ),
                        ),
                        selected: _isCustomDuration,
                        selectedColor: Colors.indigo,
                        backgroundColor: Colors.white,
                        onSelected: (selected) {
                          setState(() {
                            _isCustomDuration = true;
                          });
                        },
                      ),
                    ],
                  ),

                  // Custom duration input or quick adjustment buttons
                  if (_isCustomDuration) ...[
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        IconButton.filledTonal(
                          icon: const Icon(Icons.remove, size: 16),
                          onPressed: () {
                            if (_selectedDuration > 10) {
                              setState(() {
                                _selectedDuration = (_selectedDuration - 5).clamp(10, 1800);
                                _durationController.text = '$_selectedDuration';
                              });
                            }
                          },
                        ),
                        Expanded(
                          child: TextField(
                            controller: _durationController,
                            keyboardType: TextInputType.number,
                            textAlign: TextAlign.center,
                            decoration: InputDecoration(
                              isDense: true,
                              suffixText: 'sec',
                              contentPadding: const EdgeInsets.symmetric(vertical: 8, horizontal: 8),
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                            ),
                            onChanged: (val) {
                              final parsed = int.tryParse(val);
                              if (parsed != null && parsed >= 5 && parsed <= 1800) {
                                setState(() {
                                  _selectedDuration = parsed;
                                });
                              }
                            },
                          ),
                        ),
                        IconButton.filledTonal(
                          icon: const Icon(Icons.add, size: 16),
                          onPressed: () {
                            setState(() {
                              _selectedDuration = (_selectedDuration + 5).clamp(10, 1800);
                              _durationController.text = '$_selectedDuration';
                            });
                          },
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: () {
            if (_selectedCourseId != null && _roomController.text.trim().isNotEmpty) {
              final course = widget.courses.firstWhere((c) => c['id'] == _selectedCourseId);
              Navigator.pop(context, {
                'courseId': _selectedCourseId,
                'courseCode': course['code'],
                'roomNumber': _roomController.text.trim(),
                'codeDuration': _selectedDuration,
              });
            } else {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Please select a course and enter a room number.')),
              );
            }
          },
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.indigo,
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
          child: const Text('Start Attendance'),
        ),
      ],
    );
  }
}
