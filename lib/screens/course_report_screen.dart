import 'dart:io';
import 'package:flutter/material.dart';
import 'package:smart_proximity_attendance/services/database_helper.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

/// Full course-level attendance report screen.
/// Shows per-student totals, most-absent students, and per-session breakdown.
class CourseReportScreen extends StatefulWidget {
  final Map<String, dynamic> course; // {id, name, code}
  const CourseReportScreen({super.key, required this.course});

  @override
  State<CourseReportScreen> createState() => _CourseReportScreenState();
}

class _CourseReportScreenState extends State<CourseReportScreen>
    with SingleTickerProviderStateMixin {
  final DatabaseHelper _dbHelper = DatabaseHelper();

  List<Map<String, dynamic>> _studentReport = [];
  List<Map<String, dynamic>> _sessionSummaries = [];
  bool _isLoading = true;

  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _loadData();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    final courseId = widget.course['id'] as int;
    final students = await _dbHelper.getCourseStudentReport(courseId);
    final sessions = await _dbHelper.getCourseSessionSummaries(courseId);
    if (mounted) {
      setState(() {
        _studentReport = students;
        _sessionSummaries = sessions;
        _isLoading = false;
      });
    }
  }

  // ── Computed Stats ──────────────────────────────────────────────────────────

  int get _totalSessions => _sessionSummaries.length;
  int get _enrolledCount => _studentReport.length;

  double get _avgAttendance {
    if (_studentReport.isEmpty) return 0;
    final sum = _studentReport.fold<double>(
        0, (s, r) => s + (r['percentage'] as num).toDouble());
    return sum / _studentReport.length;
  }

  Map<String, dynamic>? get _bestSession {
    if (_sessionSummaries.isEmpty) return null;
    return _sessionSummaries.reduce((a, b) =>
        (a['presentCount'] as int) >= (b['presentCount'] as int) ? a : b);
  }

  Map<String, dynamic>? get _worstSession {
    if (_sessionSummaries.isEmpty) return null;
    return _sessionSummaries.reduce((a, b) =>
        (a['presentCount'] as int) <= (b['presentCount'] as int) ? a : b);
  }

  Color _pctColor(double pct) {
    if (pct >= 75) return Colors.green.shade600;
    if (pct >= 60) return Colors.orange.shade700;
    return Colors.red.shade600;
  }

  String _pctLabel(double pct) {
    if (pct >= 75) return 'Good';
    if (pct >= 60) return 'At Risk';
    return 'Critical';
  }

  // ── CSV Export ──────────────────────────────────────────────────────────────

  Future<void> _exportFullReport() async {
    final courseCode = widget.course['code'] ?? 'COURSE';
    final courseName = widget.course['name'] ?? '';
    final today = DateFormat('yyyy-MM-dd').format(DateTime.now());

    final buffer = StringBuffer();
    buffer.writeln('FULL COURSE ATTENDANCE REPORT');
    buffer.writeln('Course Code,$courseCode');
    buffer.writeln('Course Name,$courseName');
    buffer.writeln('Report Generated,$today');
    buffer.writeln('');
    buffer.writeln('COURSE OVERVIEW');
    buffer.writeln('Total Sessions Held,$_totalSessions');
    buffer.writeln('Total Students Enrolled,$_enrolledCount');
    buffer.writeln('Average Attendance,${_avgAttendance.toStringAsFixed(1)}%');
    buffer.writeln('');
    buffer.writeln('STUDENT ATTENDANCE SUMMARY (sorted by attendance %)');
    buffer.writeln(
        '#,Registration Number,Name,Sessions Attended,Total Sessions,Attendance %,Status');
    int i = 1;
    for (final s in _studentReport) {
      final pct = (s['percentage'] as num).toDouble();
      buffer.writeln(
          '${i++},${s['regNumber']},${s['name'] ?? 'N/A'},${s['attended']},${s['totalSessions']},${pct.toStringAsFixed(1)}%,${_pctLabel(pct)}');
    }
    buffer.writeln('');
    buffer.writeln('MOST ABSENT STUDENTS (bottom 10)');
    buffer.writeln('#,Registration Number,Name,Attendance %,Classes Missed');
    i = 1;
    final worst = List<Map<String, dynamic>>.from(_studentReport);
    // Already sorted by asc %, take first 10
    for (final s in worst.take(10)) {
      final pct = (s['percentage'] as num).toDouble();
      final missed =
          (s['totalSessions'] as int) - (s['attended'] as int);
      buffer.writeln(
          '${i++},${s['regNumber']},${s['name'] ?? 'N/A'},${pct.toStringAsFixed(1)}%,$missed');
    }
    buffer.writeln('');
    buffer.writeln('SESSION-BY-SESSION BREAKDOWN');
    buffer.writeln('#,Date,Room,Present,Enrolled,Attendance %');
    i = 1;
    for (final ses in _sessionSummaries.reversed) {
      final date = DateFormat('yyyy-MM-dd HH:mm').format(
          DateTime.parse(ses['startTime'] as String));
      final enrolled = ses['enrolledCount'] as int;
      final present = ses['presentCount'] as int;
      final pct = enrolled == 0 ? 0.0 : present / enrolled * 100;
      buffer.writeln(
          '${i++},$date,${ses['roomNumber']},$present,$enrolled,${pct.toStringAsFixed(1)}%');
    }

    final directory = await getApplicationDocumentsDirectory();
    final path =
        '${directory.path}/full_report_${courseCode}_$today.csv';
    await File(path).writeAsString(buffer.toString());

    if (mounted) {
      await Share.shareXFiles(
        [XFile(path)],
        text: 'Full Course Report – $courseCode',
      );
    }
  }

  // ── Build ────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('${widget.course['code']} Report'),
        backgroundColor: Colors.indigo,
        foregroundColor: Colors.white,
        elevation: 0,
        actions: [
          IconButton(
            onPressed: _isLoading ? null : _exportFullReport,
            icon: const Icon(Icons.download),
            tooltip: 'Export Full Report (CSV)',
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: Colors.white,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white70,
          tabs: const [
            Tab(icon: Icon(Icons.bar_chart), text: 'Overview'),
            Tab(icon: Icon(Icons.people), text: 'Students'),
            Tab(icon: Icon(Icons.calendar_month), text: 'Sessions'),
          ],
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : TabBarView(
              controller: _tabController,
              children: [
                _buildOverviewTab(),
                _buildStudentsTab(),
                _buildSessionsTab(),
              ],
            ),
    );
  }

  // ── Overview Tab ────────────────────────────────────────────────────────────

  Widget _buildOverviewTab() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // Course header
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [Colors.indigo.shade700, Colors.indigo.shade400],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(18),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(widget.course['code'] ?? '',
                  style: const TextStyle(
                      color: Colors.white70, fontSize: 13)),
              const SizedBox(height: 4),
              Text(widget.course['name'] ?? '',
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 20,
                      fontWeight: FontWeight.bold)),
              const SizedBox(height: 16),
              Row(
                children: [
                  _OverviewStat(
                      label: 'Sessions\nHeld',
                      value: '$_totalSessions',
                      icon: Icons.calendar_today),
                  _OverviewStat(
                      label: 'Students\nEnrolled',
                      value: '$_enrolledCount',
                      icon: Icons.people),
                  _OverviewStat(
                      label: 'Avg\nAttendance',
                      value: '${_avgAttendance.toStringAsFixed(1)}%',
                      icon: Icons.analytics_outlined),
                ],
              ),
            ],
          ),
        ),

        const SizedBox(height: 20),
        const Text('Distribution',
            style:
                TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
        const SizedBox(height: 12),

        // Attendance distribution bar chart (bucketed)
        _buildDistributionChart(),

        const SizedBox(height: 20),
        const Text('Session Highlights',
            style:
                TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
        const SizedBox(height: 12),

        if (_bestSession != null) ...[
          _SessionHighlightCard(
            label: 'Best Session',
            session: _bestSession!,
            color: Colors.green,
            icon: Icons.arrow_upward,
          ),
          const SizedBox(height: 10),
          _SessionHighlightCard(
            label: 'Lowest Session',
            session: _worstSession!,
            color: Colors.red,
            icon: Icons.arrow_downward,
          ),
        ] else
          const Center(
            child: Text('No sessions yet.',
                style: TextStyle(color: Colors.grey)),
          ),

        const SizedBox(height: 24),
        const Text('Most Absent Students',
            style:
                TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
        const SizedBox(height: 8),
        if (_studentReport.isEmpty)
          const Text('No student data.',
              style: TextStyle(color: Colors.grey))
        else
          ..._studentReport.take(5).map(
                (s) => _AbsenteeRow(student: s, pctColor: _pctColor),
              ),
      ],
    );
  }

  Widget _buildDistributionChart() {
    final buckets = {'0-40%': 0, '40-60%': 0, '60-75%': 0, '75-90%': 0, '90-100%': 0};
    for (final s in _studentReport) {
      final pct = (s['percentage'] as num).toDouble();
      if (pct < 40) {
        buckets['0-40%'] = (buckets['0-40%'] ?? 0) + 1;
      } else if (pct < 60) {
        buckets['40-60%'] = (buckets['40-60%'] ?? 0) + 1;
      } else if (pct < 75) {
        buckets['60-75%'] = (buckets['60-75%'] ?? 0) + 1;
      } else if (pct < 90) {
        buckets['75-90%'] = (buckets['75-90%'] ?? 0) + 1;
      } else {
        buckets['90-100%'] = (buckets['90-100%'] ?? 0) + 1;
      }
    }

    final colors = [
      Colors.red.shade600,
      Colors.orange.shade600,
      Colors.amber.shade600,
      Colors.lightGreen.shade600,
      Colors.green.shade600,
    ];
    final total = _studentReport.length;

    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      elevation: 0,
      color: Colors.grey.shade50,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: List.generate(buckets.length, (i) {
            final label = buckets.keys.elementAt(i);
            final count = buckets.values.elementAt(i);
            final frac = total == 0 ? 0.0 : count / total;
            return Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Row(
                children: [
                  SizedBox(
                    width: 60,
                    child: Text(label,
                        style: const TextStyle(fontSize: 11)),
                  ),
                  Expanded(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(
                        value: frac,
                        minHeight: 14,
                        color: colors[i],
                        backgroundColor: Colors.grey.shade200,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  SizedBox(
                    width: 28,
                    child: Text('$count',
                        style: const TextStyle(fontWeight: FontWeight.bold)),
                  ),
                ],
              ),
            );
          }),
        ),
      ),
    );
  }

  // ── Students Tab ────────────────────────────────────────────────────────────

  Widget _buildStudentsTab() {
    if (_studentReport.isEmpty) {
      return const Center(
          child: Text('No students enrolled.',
              style: TextStyle(color: Colors.grey)));
    }
    return ListView.separated(
      padding: const EdgeInsets.all(12),
      itemCount: _studentReport.length,
      separatorBuilder: (context, index) => const SizedBox(height: 6),
      itemBuilder: (_, index) {
        final s = _studentReport[index];
        final pct = (s['percentage'] as num).toDouble();
        final color = _pctColor(pct);
        final name = s['name'] as String?;
        final attended = s['attended'] as int;
        final total = s['totalSessions'] as int;

        return Card(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          elevation: 0,
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: Colors.grey.shade200),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Row(
              children: [
                // Rank badge
                Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.1),
                    shape: BoxShape.circle,
                  ),
                  child: Center(
                    child: Text('${index + 1}',
                        style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: color,
                            fontSize: 13)),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        name != null && name.isNotEmpty
                            ? name
                            : s['regNumber'] as String,
                        style: const TextStyle(
                            fontWeight: FontWeight.w600, fontSize: 14),
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (name != null && name.isNotEmpty)
                        Text(s['regNumber'] as String,
                            style: TextStyle(
                                color: Colors.grey.shade600, fontSize: 12)),
                      const SizedBox(height: 6),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(3),
                        child: LinearProgressIndicator(
                          value: pct / 100,
                          minHeight: 5,
                          color: color,
                          backgroundColor: Colors.grey.shade200,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      '${pct.toStringAsFixed(1)}%',
                      style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                          color: color),
                    ),
                    Text('$attended / $total',
                        style: TextStyle(
                            color: Colors.grey.shade600, fontSize: 11)),
                    Container(
                      margin: const EdgeInsets.only(top: 4),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 7, vertical: 2),
                      decoration: BoxDecoration(
                        color: color.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(_pctLabel(pct),
                          style: TextStyle(
                              color: color,
                              fontSize: 10,
                              fontWeight: FontWeight.bold)),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  // ── Sessions Tab ────────────────────────────────────────────────────────────

  Widget _buildSessionsTab() {
    if (_sessionSummaries.isEmpty) {
      return const Center(
          child: Text('No sessions held yet.',
              style: TextStyle(color: Colors.grey)));
    }
    return ListView.separated(
      padding: const EdgeInsets.all(12),
      itemCount: _sessionSummaries.length,
      separatorBuilder: (context, index) => const SizedBox(height: 6),
      itemBuilder: (_, index) {
        final ses = _sessionSummaries[index];
        final enrolled = ses['enrolledCount'] as int;
        final present = ses['presentCount'] as int;
        final pct = enrolled == 0 ? 0.0 : present / enrolled * 100;
        final color = _pctColor(pct);
        final date = DateTime.parse(ses['startTime'] as String);

        return Card(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          elevation: 0,
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: Colors.grey.shade200),
            ),
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.calendar_today_outlined,
                        size: 15, color: Colors.indigo),
                    const SizedBox(width: 6),
                    Text(
                      DateFormat('EEE, MMM dd yyyy  •  hh:mm a').format(date),
                      style: const TextStyle(
                          fontWeight: FontWeight.w600, fontSize: 13),
                    ),
                    const Spacer(),
                    Text('Room ${ses['roomNumber']}',
                        style: TextStyle(
                            color: Colors.grey.shade600, fontSize: 12)),
                  ],
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: LinearProgressIndicator(
                          value: pct / 100,
                          minHeight: 10,
                          color: color,
                          backgroundColor: Colors.grey.shade200,
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Text('${pct.toStringAsFixed(1)}%',
                        style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: color,
                            fontSize: 14)),
                  ],
                ),
                const SizedBox(height: 6),
                Text('$present present out of $enrolled enrolled',
                    style: TextStyle(
                        color: Colors.grey.shade600, fontSize: 12)),
              ],
            ),
          ),
        );
      },
    );
  }
}

// ─── Helper Widgets ───────────────────────────────────────────────────────────

class _OverviewStat extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;

  const _OverviewStat(
      {required this.label, required this.value, required this.icon});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        children: [
          Icon(icon, color: Colors.white70, size: 20),
          const SizedBox(height: 6),
          Text(value,
              style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 18)),
          Text(label,
              textAlign: TextAlign.center,
              style:
                  const TextStyle(color: Colors.white60, fontSize: 11)),
        ],
      ),
    );
  }
}

class _SessionHighlightCard extends StatelessWidget {
  final String label;
  final Map<String, dynamic> session;
  final Color color;
  final IconData icon;

  const _SessionHighlightCard({
    required this.label,
    required this.session,
    required this.color,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    final enrolled = session['enrolledCount'] as int;
    final present = session['presentCount'] as int;
    final pct = enrolled == 0 ? 0.0 : present / enrolled * 100;
    final date = DateTime.parse(session['startTime'] as String);

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label,
                    style: TextStyle(
                        color: color,
                        fontWeight: FontWeight.bold,
                        fontSize: 12)),
                Text(
                  DateFormat('EEE, MMM dd yyyy').format(date),
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                Text('Room ${session['roomNumber']}',
                    style: TextStyle(
                        color: Colors.grey.shade600, fontSize: 12)),
              ],
            ),
          ),
          Text(
            '${pct.toStringAsFixed(0)}%',
            style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 20,
                color: color),
          ),
        ],
      ),
    );
  }
}

class _AbsenteeRow extends StatelessWidget {
  final Map<String, dynamic> student;
  final Color Function(double) pctColor;

  const _AbsenteeRow({required this.student, required this.pctColor});

  @override
  Widget build(BuildContext context) {
    final pct = (student['percentage'] as num).toDouble();
    final color = pctColor(pct);
    final name = student['name'] as String?;
    final missed =
        (student['totalSessions'] as int) - (student['attended'] as int);

    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
      leading: CircleAvatar(
        backgroundColor: color.withValues(alpha: 0.15),
        child: Icon(Icons.person, color: color, size: 20),
      ),
      title: Text(
          name != null && name.isNotEmpty
              ? name
              : student['regNumber'] as String,
          style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
      subtitle: Text(student['regNumber'] as String,
          style: const TextStyle(fontSize: 12)),
      trailing: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text('${pct.toStringAsFixed(1)}%',
              style: TextStyle(
                  fontWeight: FontWeight.bold, color: color, fontSize: 14)),
          Text('$missed missed',
              style: TextStyle(color: Colors.grey.shade600, fontSize: 11)),
        ],
      ),
    );
  }
}
