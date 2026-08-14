import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:nearby_connections/nearby_connections.dart';
import 'package:smart_proximity_attendance/services/proximity_service.dart';
import 'package:smart_proximity_attendance/services/database_helper.dart';
import 'package:intl/intl.dart';

class LiveSessionScreen extends StatefulWidget {
  final int sessionId;
  final int courseId;
  final String courseCode;

  const LiveSessionScreen({
    super.key,
    required this.sessionId,
    required this.courseId,
    required this.courseCode,
  });

  @override
  State<LiveSessionScreen> createState() => _LiveSessionScreenState();
}

class _LiveSessionScreenState extends State<LiveSessionScreen>
    with SingleTickerProviderStateMixin {
  final ProximityService _proximityService = ProximityService();
  final DatabaseHelper _dbHelper = DatabaseHelper();

  List<Map<String, dynamic>> _presentStudents = [];
  List<Map<String, dynamic>> _courseRoster = [];

  // ── Rolling PIN state ──────────────────────────────────────────────────────
  String _currentPin = '';
  String _previousPin = ''; // grace-period window: accepts old PIN for 1 cycle
  int _secondsRemaining = 30;
  Timer? _pinTimer;

  // ── Animation controller for PIN refresh flash ─────────────────────────────
  late AnimationController _flashController;
  late Animation<Color?> _flashAnimation;

  @override
  void initState() {
    super.initState();

    _flashController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    _flashAnimation = ColorTween(
      begin: Colors.greenAccent.shade100,
      end: Colors.indigo.shade50,
    ).animate(CurvedAnimation(parent: _flashController, curve: Curves.easeOut));

    _loadRoster();
    _generateNewPin(); // generate first PIN immediately
    _startPinTimer();
    _startBroadcasting();
  }

  // ── PIN Generation ─────────────────────────────────────────────────────────

  String _newPinString() {
    // 6-digit PIN: 100000 – 999999
    return (100000 + Random().nextInt(900000)).toString();
  }

  void _generateNewPin() {
    _previousPin = _currentPin;
    _currentPin = _newPinString();
    _secondsRemaining = 30;
    _dbHelper.updateSessionPin(widget.sessionId, _currentPin);
    if (mounted) {
      setState(() {});
      _flashController.forward(from: 0);
    }
  }

  void _startPinTimer() {
    _pinTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() {
        if (_secondsRemaining > 1) {
          _secondsRemaining--;
        } else {
          _generateNewPin();
        }
      });
    });
  }

  // ── Nearby Connections ─────────────────────────────────────────────────────

  Future<void> _loadRoster() async {
    final roster = await _dbHelper.getRosterForCourse(widget.courseId);
    if (mounted) setState(() => _courseRoster = roster);
  }

  void _startBroadcasting() async {
    await _proximityService.startAdvertising(
      widget.courseCode,
      (endpointId, info) {
        _proximityService.acceptConnection(endpointId, (id, payload) {
          if (payload.type == PayloadType.BYTES) {
            final data = String.fromCharCodes(payload.bytes!);
            _handleIncomingAttendance(id, data);
          }
        });
      },
    );
  }

  // ── Attendance Validation ──────────────────────────────────────────────────

  void _handleIncomingAttendance(String endpointId, String data) async {
    try {
      final studentData = jsonDecode(data);
      final String regNumber = studentData['regNumber'];
      final String pin = studentData['pin'];
      final String deviceId = studentData['deviceId'];

      String status = 'fail';
      String message = '';

      // ① Verify rolling PIN (accept current OR previous for grace period)
      if (pin != _currentPin && (_previousPin.isEmpty || pin != _previousPin)) {
        message = 'Incorrect PIN. Please look at the teacher\'s screen.';
      } else {
        // ② Check global device registry for proxy fraud
        final isFraud = await _dbHelper.checkDeviceFraud(deviceId, regNumber);
        if (isFraud) {
          message =
              'This device is already registered to a different student. Proxy attendance is not allowed.';
        } else {
          // ③ Check if student is on the course roster
          final student = _courseRoster.firstWhere(
            (s) => s['regNumber'] == regNumber,
            orElse: () => {},
          );

          if (student.isEmpty) {
            message = 'You are not enrolled in this course.';
          } else {
            // ④ Check per-course device binding
            final String? boundId = student['boundDeviceId'];
            if (boundId != null && boundId != deviceId) {
              message =
                  'This registration number is bound to a different device. Contact your teacher.';
            } else {
              // ⑤ Prevent duplicate in same session
              final alreadyPresent =
                  _presentStudents.any((s) => s['regNumber'] == regNumber);
              if (alreadyPresent) {
                message = 'Attendance already recorded for this session.';
              } else {
                // ✅ SUCCESS
                if (boundId == null) {
                  // First time this student submits — bind device
                  await _dbHelper.bindDeviceToStudent(
                      widget.courseId, regNumber, deviceId);
                  await _dbHelper.registerDevice(
                      deviceId, regNumber); // global registry
                  await _loadRoster(); // refresh local roster
                }
                await _dbHelper.markAttendance(
                    widget.sessionId, regNumber, deviceId);
                await _loadAttendance();
                status = 'success';
              }
            }
          }
        }
      }

      // Send response back to student app
      await _proximityService.sendPayload(
        endpointId,
        jsonEncode({'status': status, 'message': message}),
      );
    } catch (_) {
      // Malformed payload — ignore
    }
  }

  Future<void> _loadAttendance() async {
    final list = await _dbHelper.getAttendanceForSession(widget.sessionId);
    if (mounted) setState(() => _presentStudents = list);
  }

  @override
  void dispose() {
    _pinTimer?.cancel();
    _flashController.dispose();
    _proximityService.stopAdvertising();
    super.dispose();
  }

  // ── UI ─────────────────────────────────────────────────────────────────────

  Color get _countdownColor {
    if (_secondsRemaining <= 5) return Colors.red;
    if (_secondsRemaining <= 10) return Colors.orange;
    return Colors.indigo;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Live: ${widget.courseCode}'),
        actions: [
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Center(
              child: Text(
                'Present: ${_presentStudents.length}/${_courseRoster.length}',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          // ── PIN Panel ──────────────────────────────────────────────────────
          AnimatedBuilder(
            animation: _flashAnimation,
            builder: (context, child) => Container(
              padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 20),
              color: _flashAnimation.value,
              width: double.infinity,
              child: child,
            ),
            child: Column(
              children: [
                const Text(
                  'Show this PIN to students',
                  style: TextStyle(color: Colors.indigo, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    // 6-digit PIN display
                    Text(
                      _currentPin.isEmpty ? '------' : _currentPin,
                      style: const TextStyle(
                        fontSize: 52,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 10,
                        fontFamily: 'monospace',
                      ),
                    ),
                    const SizedBox(width: 24),
                    // Circular countdown ring
                    SizedBox(
                      width: 72,
                      height: 72,
                      child: Stack(
                        alignment: Alignment.center,
                        children: [
                          CircularProgressIndicator(
                            value: _secondsRemaining / 30,
                            strokeWidth: 7,
                            color: _countdownColor,
                            backgroundColor: Colors.grey.shade200,
                          ),
                          Text(
                            '$_secondsRemaining',
                            style: TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                              color: _countdownColor,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  'PIN refreshes in $_secondsRemaining seconds',
                  style: TextStyle(
                    fontStyle: FontStyle.italic,
                    fontSize: 12,
                    color: Colors.indigo.shade400,
                  ),
                ),
              ],
            ),
          ),

          // ── Attendance List ────────────────────────────────────────────────
          Expanded(
            child: _presentStudents.isEmpty
                ? const Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.group_outlined, size: 56, color: Colors.grey),
                        SizedBox(height: 12),
                        Text('Waiting for students to check in...',
                            style: TextStyle(color: Colors.grey)),
                      ],
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.all(8),
                    itemCount: _presentStudents.length,
                    itemBuilder: (context, index) {
                      final s = _presentStudents[index];
                      final displayName =
                          (s['name'] != null && (s['name'] as String).isNotEmpty)
                              ? s['name'] as String
                              : s['regNumber'] as String;
                      return ListTile(
                        leading: CircleAvatar(
                          backgroundColor: Colors.indigo.shade50,
                          child: Text(
                            '${index + 1}',
                            style: const TextStyle(
                                color: Colors.indigo, fontWeight: FontWeight.bold),
                          ),
                        ),
                        title: Text(displayName,
                            style: const TextStyle(fontWeight: FontWeight.w600)),
                        subtitle: Text(s['regNumber'] as String),
                        trailing: Text(
                          DateFormat('hh:mm a')
                              .format(DateTime.parse(s['timestamp'] as String)),
                          style: const TextStyle(color: Colors.grey),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
      bottomNavigationBar: Padding(
        padding: const EdgeInsets.all(16.0),
        child: ElevatedButton(
          onPressed: () async {
            await _dbHelper.endSession(widget.sessionId);
            if (!context.mounted) return;
            Navigator.pop(context);
          },
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.red.shade50,
            foregroundColor: Colors.red,
            padding: const EdgeInsets.symmetric(vertical: 16),
          ),
          child: const Text('End Session'),
        ),
      ),
    );
  }
}
