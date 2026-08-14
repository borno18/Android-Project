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

class _ReportScreenState extends State<ReportScreen> {
  final DatabaseHelper _dbHelper = DatabaseHelper();
  List<Map<String, dynamic>> _attendanceList = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadAttendance();
  }

  Future<void> _loadAttendance() async {
    final list =
        await _dbHelper.getAttendanceForSession(widget.session['id'] as int);
    setState(() {
      _attendanceList = list;
      _isLoading = false;
    });
  }

  Future<void> _exportToCSV() async {
    List<List<dynamic>> rows = [];
    // Header row
    rows.add(['#', 'Registration Number', 'Name', 'Timestamp']);

    int i = 1;
    for (var record in _attendanceList) {
      rows.add([
        i++,
        record['regNumber'] ?? '',
        record['name'] ?? 'N/A',
        DateFormat('yyyy-MM-dd HH:mm:ss')
            .format(DateTime.parse(record['timestamp'] as String)),
      ]);
    }

    final csvData = rows.map((row) => row.join(',')).join('\n');
    final directory = await getApplicationDocumentsDirectory();
    final path =
        '${directory.path}/attendance_${widget.session['courseCode']}_${widget.session['id']}.csv';
    final file = File(path);
    await file.writeAsString(csvData);

    if (mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Saved to $path')));
      await Share.shareXFiles(
        [XFile(path)],
        text: 'Attendance Report – ${widget.session['courseCode']}',
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Report: ${widget.session['courseCode']}'),
        actions: [
          IconButton(
            onPressed: _exportToCSV,
            icon: const Icon(Icons.download),
            tooltip: 'Export CSV',
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                // Session summary header
                Container(
                  padding: const EdgeInsets.all(20),
                  color: Colors.indigo.shade50,
                  width: double.infinity,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Room ${widget.session['roomNumber']}',
                        style: const TextStyle(
                            fontSize: 18, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        DateFormat('EEEE, MMM dd, yyyy').format(
                            DateTime.parse(
                                widget.session['startTime'] as String)),
                        style: const TextStyle(color: Colors.grey),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          const Icon(Icons.people, size: 18, color: Colors.indigo),
                          const SizedBox(width: 6),
                          Text(
                            'Total Present: ${_attendanceList.length}',
                            style: const TextStyle(
                                color: Colors.indigo,
                                fontWeight: FontWeight.bold),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),

                // Attendance records
                Expanded(
                  child: _attendanceList.isEmpty
                      ? const Center(
                          child: Text('No attendance records for this session.'))
                      : ListView.separated(
                          itemCount: _attendanceList.length,
                          separatorBuilder: (context, index) =>
                              const Divider(height: 1),
                          itemBuilder: (context, index) {
                            final record = _attendanceList[index];
                            final name = record['name'] as String?;
                            final reg = record['regNumber'] as String;
                            return ListTile(
                              leading: CircleAvatar(
                                backgroundColor: Colors.green.shade50,
                                child: Text(
                                  '${index + 1}',
                                  style:
                                      const TextStyle(color: Colors.green),
                                ),
                              ),
                              title: Text(
                                name != null && name.isNotEmpty ? name : reg,
                                style: const TextStyle(
                                    fontWeight: FontWeight.w600),
                              ),
                              subtitle: name != null && name.isNotEmpty
                                  ? Text('Reg: $reg')
                                  : null,
                              trailing: Text(
                                DateFormat('hh:mm a').format(DateTime.parse(
                                    record['timestamp'] as String)),
                                style:
                                    const TextStyle(color: Colors.grey),
                              ),
                            );
                          },
                        ),
                ),
              ],
            ),
    );
  }
}
