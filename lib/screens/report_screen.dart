import 'dart:io';
import 'package:flutter/material.dart';
import 'package:smart_proximity_attendance/services/database_helper.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

class ReportScreen extends StatefulWidget {
  final Map<String, dynamic> session;
  const ReportScreen({super.key, required this.session});

  @override
  State<ReportScreen> createState() => _ReportScreenState();
}

class _ReportScreenState extends State<ReportScreen>
    with SingleTickerProviderStateMixin {
  final DatabaseHelper _dbHelper = DatabaseHelper();
  List<Map<String, dynamic>> _presentList = [];
  List<Map<String, dynamic>> _absentList = [];
  bool _isLoading = true;

  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _tabController.addListener(() {
      if (!_tabController.indexIsChanging) {
        setState(() {});
      }
    });
    _loadData();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    final sessionId = widget.session['id'] as int;
    final courseId = widget.session['courseId'] as int;
    final present = await _dbHelper.getAttendanceForSession(sessionId);
    final absent = await _dbHelper.getAbsenteesForSession(sessionId, courseId);
    if (mounted) {
      setState(() {
        _presentList = present;
        _absentList = absent;
        _isLoading = false;
      });
    }
  }

  int get _enrolled => _presentList.length + _absentList.length;
  double get _pct =>
      _enrolled == 0 ? 0.0 : _presentList.length / _enrolled * 100;

  Color get _pctColor {
    if (_pct >= 75) return Colors.green.shade600;
    if (_pct >= 60) return Colors.orange.shade700;
    return Colors.red.shade600;
  }

  Future<void> _exportToCSV() async {
    final courseCode = widget.session['courseCode'] ?? 'COURSE';
    final sessionId = widget.session['id'];
    final dateStr = DateFormat('yyyy-MM-dd').format(
        DateTime.parse(widget.session['startTime'] as String));
    final startFmt = DateFormat('yyyy-MM-dd HH:mm:ss').format(
        DateTime.parse(widget.session['startTime'] as String));

    final buffer = StringBuffer();
    buffer.writeln('SESSION ATTENDANCE REPORT');
    buffer.writeln('Course,$courseCode – ${widget.session['courseName']}');
    buffer.writeln('Date,$dateStr');
    buffer.writeln('Room,${widget.session['roomNumber']}');
    buffer.writeln('Session Start,$startFmt');
    buffer.writeln('');
    buffer.writeln('SUMMARY');
    buffer.writeln('Total Enrolled,$_enrolled');
    buffer.writeln('Present,${_presentList.length}');
    buffer.writeln('Absent,${_absentList.length}');
    buffer.writeln('Attendance %,${_pct.toStringAsFixed(1)}%');
    buffer.writeln('');
    buffer.writeln('PRESENT STUDENTS');
    buffer.writeln('#,Registration Number,Name,Check-in Time');
    int i = 1;
    for (final r in _presentList) {
      final name = r['name'] ?? 'N/A';
      final time = DateFormat('HH:mm:ss')
          .format(DateTime.parse(r['timestamp'] as String));
      buffer.writeln('${i++},${r['regNumber']},$name,$time');
    }
    buffer.writeln('');
    buffer.writeln('ABSENT STUDENTS');
    buffer.writeln('#,Registration Number,Name');
    i = 1;
    for (final r in _absentList) {
      buffer.writeln('${i++},${r['regNumber']},${r['name'] ?? 'N/A'}');
    }

    final directory = await getApplicationDocumentsDirectory();
    final path =
        '${directory.path}/session_report_${courseCode}_${sessionId}_$dateStr.csv';
    await File(path).writeAsString(buffer.toString());

    if (mounted) {
      await Share.shareXFiles(
        [XFile(path)],
        text: 'Session Report – $courseCode ($dateStr)',
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final sessionDate = DateTime.parse(widget.session['startTime'] as String);

    return Scaffold(
      appBar: AppBar(
        title: Text('Session: ${widget.session['courseCode']}'),
        backgroundColor: Colors.indigo,
        foregroundColor: Colors.white,
        elevation: 0,
        actions: [
          IconButton(
            onPressed: _exportToCSV,
            icon: const Icon(Icons.download),
            tooltip: 'Export CSV',
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: Colors.white,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white70,
          tabs: [
            Tab(
              icon: const Icon(Icons.check_circle_outline),
              text: 'Present (${_presentList.length})',
            ),
            Tab(
              icon: const Icon(Icons.cancel_outlined),
              text: 'Absent (${_absentList.length})',
            ),
          ],
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                // ── Summary Header ───────────────────────────────────────
                Container(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
                  color: Colors.indigo.shade50,
                  width: double.infinity,
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
                                  widget.session['courseName'] ?? '',
                                  style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 16),
                                ),
                                Text(
                                  '${DateFormat('EEEE, MMM dd, yyyy').format(sessionDate)}  •  Room ${widget.session['roomNumber']}',
                                  style:
                                      const TextStyle(color: Colors.grey, fontSize: 13),
                                ),
                              ],
                            ),
                          ),
                          // Big percentage ring
                          Stack(
                            alignment: Alignment.center,
                            children: [
                              SizedBox(
                                width: 60,
                                height: 60,
                                child: CircularProgressIndicator(
                                  value: _pct / 100,
                                  strokeWidth: 7,
                                  color: _pctColor,
                                  backgroundColor: Colors.grey.shade300,
                                ),
                              ),
                              Text(
                                '${_pct.toStringAsFixed(0)}%',
                                style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 13,
                                    color: _pctColor),
                              ),
                            ],
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),
                      Row(
                        children: [
                          _SummaryPill(
                              label: 'Enrolled',
                              value: '$_enrolled',
                              color: Colors.indigo),
                          const SizedBox(width: 8),
                          _SummaryPill(
                              label: 'Present',
                              value: '${_presentList.length}',
                              color: Colors.green),
                          const SizedBox(width: 8),
                          _SummaryPill(
                              label: 'Absent',
                              value: '${_absentList.length}',
                              color: Colors.red),
                        ],
                      ),
                    ],
                  ),
                ),

                // ── Tab Content ──────────────────────────────────────────
                Expanded(
                  child: TabBarView(
                    controller: _tabController,
                    children: [
                      // Present tab
                      _buildStudentList(
                        list: _presentList,
                        emptyMessage: 'No students were present in this session.',
                        emptyIcon: Icons.people_outline,
                        itemBuilder: (record, index) {
                          final name = record['name'] as String?;
                          final reg = record['regNumber'] as String;
                          return ListTile(
                            leading: CircleAvatar(
                              backgroundColor: Colors.green.shade50,
                              child: Text('${index + 1}',
                                  style:
                                      const TextStyle(color: Colors.green)),
                            ),
                            title: Text(
                              name != null && name.isNotEmpty ? name : reg,
                              style: const TextStyle(fontWeight: FontWeight.w600),
                            ),
                            subtitle:
                                name != null && name.isNotEmpty
                                    ? Text('Reg: $reg')
                                    : null,
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(Icons.access_time,
                                    size: 14, color: Colors.grey),
                                const SizedBox(width: 4),
                                Text(
                                  DateFormat('hh:mm a').format(
                                      DateTime.parse(
                                          record['timestamp'] as String)),
                                  style:
                                      const TextStyle(color: Colors.grey),
                                ),
                              ],
                            ),
                          );
                        },
                      ),

                      // Absent tab
                      _buildStudentList(
                        list: _absentList,
                        emptyMessage: 'All enrolled students were present!',
                        emptyIcon: Icons.celebration,
                        itemBuilder: (record, index) {
                          final name = record['name'] as String?;
                          final reg = record['regNumber'] as String;
                          return ListTile(
                            leading: CircleAvatar(
                              backgroundColor: Colors.red.shade50,
                              child: Text('${index + 1}',
                                  style: const TextStyle(color: Colors.red)),
                            ),
                            title: Text(
                              name != null && name.isNotEmpty ? name : reg,
                              style: const TextStyle(fontWeight: FontWeight.w600),
                            ),
                            subtitle:
                                name != null && name.isNotEmpty
                                    ? Text('Reg: $reg')
                                    : null,
                            trailing: const Chip(
                              label: Text('Absent',
                                  style: TextStyle(
                                      color: Colors.red, fontSize: 11)),
                              backgroundColor: Color(0xFFFFEBEE),
                              side: BorderSide.none,
                              padding: EdgeInsets.zero,
                            ),
                          );
                        },
                      ),
                    ],
                  ),
                ),
              ],
            ),
    );
  }

  Widget _buildStudentList({
    required List<Map<String, dynamic>> list,
    required String emptyMessage,
    required IconData emptyIcon,
    required Widget Function(Map<String, dynamic> record, int index) itemBuilder,
  }) {
    if (list.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(emptyIcon, size: 56, color: Colors.grey.shade400),
            const SizedBox(height: 12),
            Text(emptyMessage,
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey.shade600)),
          ],
        ),
      );
    }
    return ListView.separated(
      itemCount: list.length,
      separatorBuilder: (context, index) => const Divider(height: 1),
      itemBuilder: (_, index) => itemBuilder(list[index], index),
    );
  }
}

// ─── Summary Pill ──────────────────────────────────────────────────────────────
class _SummaryPill extends StatelessWidget {
  final String label;
  final String value;
  final Color color;

  const _SummaryPill(
      {required this.label, required this.value, required this.color});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 8),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Column(
          children: [
            Text(value,
                style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 18,
                    color: color)),
            Text(label,
                style:
                    TextStyle(fontSize: 11, color: Colors.grey.shade600)),
          ],
        ),
      ),
    );
  }
}
