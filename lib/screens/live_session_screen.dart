import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:nearby_connections/nearby_connections.dart';
import 'package:smart_proximity_attendance/services/proximity_service.dart';
import 'package:smart_proximity_attendance/services/database_helper.dart';
import 'package:smart_proximity_attendance/screens/report_screen.dart';
import 'package:intl/intl.dart';

class LiveSessionScreen extends StatefulWidget {
  final int sessionId;
  final int courseId;
  final String courseCode;
  final int codeDurationSeconds;

  const LiveSessionScreen({
    super.key,
    required this.sessionId,
    required this.courseId,
    required this.courseCode,
    this.codeDurationSeconds = 60,
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

  // ── Session Control State ──────────────────────────────────────────────────
  bool _isPaused = false;

  // ── Rolling PIN state ──────────────────────────────────────────────────────
  String _currentPin = '';
  String _previousPin = ''; // grace-period window: accepts old PIN for 1 cycle
  late int _codeDuration;
  int _secondsRemaining = 60;
  Timer? _pinTimer;

  // ── Animation controller for PIN refresh flash ─────────────────────────────
  late AnimationController _flashController;
  late Animation<Color?> _flashAnimation;

  @override
  void initState() {
    super.initState();

    _codeDuration = widget.codeDurationSeconds > 0 ? widget.codeDurationSeconds : 60;
    _secondsRemaining = _codeDuration;

    _flashController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    _flashAnimation = ColorTween(
      begin: Colors.greenAccent.shade100,
      end: Colors.indigo.shade50,
    ).animate(CurvedAnimation(parent: _flashController, curve: Curves.easeOut));

    _loadRoster();
    _loadAttendance();
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
    if (_isPaused) return;
    _previousPin = _currentPin;
    _currentPin = _newPinString();
    _secondsRemaining = _codeDuration;
    _dbHelper.updateSessionPin(widget.sessionId, _currentPin);
    if (mounted) {
      setState(() {});
      _flashController.forward(from: 0);
    }
  }

  void _startPinTimer() {
    _pinTimer?.cancel();
    _pinTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted || _isPaused) return;
      setState(() {
        if (_secondsRemaining > 1) {
          _secondsRemaining--;
        } else {
          _generateNewPin();
        }
      });
    });
  }

  // ── Pause / Resume Controls ────────────────────────────────────────────────

  void _pauseAttendance() {
    _pinTimer?.cancel();
    _proximityService.stopAdvertising();
    setState(() {
      _isPaused = true;
    });
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Attendance taking is PAUSED. Students cannot check in.'),
        backgroundColor: Colors.amber,
        duration: Duration(seconds: 2),
      ),
    );
  }

  void _resumeAttendance() {
    setState(() {
      _isPaused = false;
    });
    _generateNewPin();
    _startPinTimer();
    _startBroadcasting();
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Attendance taking RESUMED with a new PIN.'),
        backgroundColor: Colors.green,
        duration: Duration(seconds: 2),
      ),
    );
  }

  String _formatDurationLabel(int seconds) {
    if (seconds < 60) return '${seconds}s';
    final mins = seconds ~/ 60;
    final rem = seconds % 60;
    return rem == 0 ? '${mins}m' : '${mins}m ${rem}s';
  }

  Future<void> _showChangeDurationDialog() async {
    int tempDuration = _codeDuration;
    final textController = TextEditingController(text: '$tempDuration');
    final presetDurations = [30, 45, 60, 90, 120, 180, 300];

    final newDuration = await showDialog<int>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
          title: const Row(
            children: [
              Icon(Icons.timer_outlined, color: Colors.indigo),
              SizedBox(width: 8),
              Text('Change PIN Timer'),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Set how often the class code rotates automatically:',
                style: TextStyle(color: Colors.grey, fontSize: 13),
              ),
              const SizedBox(height: 14),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: presetDurations.map((d) {
                  final isSelected = tempDuration == d;
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
                        setDialogState(() {
                          tempDuration = d;
                          textController.text = '$d';
                        });
                      }
                    },
                  );
                }).toList(),
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  IconButton.filledTonal(
                    icon: const Icon(Icons.remove, size: 16),
                    onPressed: () {
                      if (tempDuration > 10) {
                        setDialogState(() {
                          tempDuration = (tempDuration - 5).clamp(10, 1800);
                          textController.text = '$tempDuration';
                        });
                      }
                    },
                  ),
                  Expanded(
                    child: TextField(
                      controller: textController,
                      keyboardType: TextInputType.number,
                      textAlign: TextAlign.center,
                      decoration: InputDecoration(
                        isDense: true,
                        labelText: 'Duration (seconds)',
                        suffixText: 'sec',
                        contentPadding: const EdgeInsets.symmetric(vertical: 8, horizontal: 8),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                      onChanged: (val) {
                        final parsed = int.tryParse(val);
                        if (parsed != null && parsed >= 5 && parsed <= 1800) {
                          setDialogState(() {
                            tempDuration = parsed;
                          });
                        }
                      },
                    ),
                  ),
                  IconButton.filledTonal(
                    icon: const Icon(Icons.add, size: 16),
                    onPressed: () {
                      setDialogState(() {
                        tempDuration = (tempDuration + 5).clamp(10, 1800);
                        textController.text = '$tempDuration';
                      });
                    },
                  ),
                ],
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(context, tempDuration),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.indigo,
                foregroundColor: Colors.white,
              ),
              child: const Text('Save & Apply'),
            ),
          ],
        ),
      ),
    );

    if (newDuration != null && newDuration >= 5) {
      setState(() {
        _codeDuration = newDuration;
        _secondsRemaining = newDuration;
      });
      await _dbHelper.updateSessionDuration(widget.sessionId, newDuration);
      _startPinTimer();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Class code timer updated to ${_formatDurationLabel(newDuration)} per cycle.'),
            backgroundColor: Colors.indigo,
          ),
        );
      }
    }
  }

  // ── Restart Attendance Controls ────────────────────────────────────────────

  Future<void> _showRestartDialog() async {
    final action = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: const Row(
          children: [
            Icon(Icons.refresh, color: Colors.indigo),
            SizedBox(width: 8),
            Text('Restart Options'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Choose how you want to restart or adjust attendance:',
              style: TextStyle(color: Colors.grey, fontSize: 13),
            ),
            const SizedBox(height: 16),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const CircleAvatar(
                backgroundColor: Color(0xFFE8EAF6),
                child: Icon(Icons.timer, color: Colors.indigo),
              ),
              title: const Text('Reset PIN & Timer',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
              subtitle: Text(
                  'Keeps current records and starts with a new PIN and fresh ${_formatDurationLabel(_codeDuration)} timer.',
                  style: const TextStyle(fontSize: 12)),
              onTap: () => Navigator.pop(context, 'pin_only'),
            ),
            const Divider(height: 16),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const CircleAvatar(
                backgroundColor: Color(0xFFE0F2FE),
                child: Icon(Icons.tune, color: Colors.blue),
              ),
              title: const Text('Change Timer Duration',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Colors.blue)),
              subtitle: Text(
                  'Current duration: ${_formatDurationLabel(_codeDuration)}. Adjust how often code refreshes.',
                  style: const TextStyle(fontSize: 12)),
              onTap: () => Navigator.pop(context, 'change_duration'),
            ),
            const Divider(height: 16),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const CircleAvatar(
                backgroundColor: Color(0xFFFFEBEE),
                child: Icon(Icons.delete_sweep, color: Colors.red),
              ),
              title: const Text('Clear All & Restart Fresh',
                  style: TextStyle(fontWeight: FontWeight.bold, color: Colors.red, fontSize: 14)),
              subtitle: const Text('Clears attendance records for this session and starts over from 0.',
                  style: TextStyle(fontSize: 12)),
              onTap: () => Navigator.pop(context, 'clear_all'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
        ],
      ),
    );

    if (action == 'change_duration') {
      _showChangeDurationDialog();
    } else if (action == 'pin_only') {
      if (_isPaused) {
        _resumeAttendance();
      } else {
        _generateNewPin();
        _startPinTimer();
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('PIN and countdown timer restarted!')),
        );
      }
    } else if (action == 'clear_all') {
      await _dbHelper.clearAttendanceForSession(widget.sessionId);
      await _loadAttendance();
      if (_isPaused) {
        _resumeAttendance();
      } else {
        _generateNewPin();
        _startPinTimer();
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('All attendance records for this session cleared.'),
            backgroundColor: Colors.orange,
          ),
        );
      }
    }
  }

  // ── Finish Attendance Session ──────────────────────────────────────────────

  Future<void> _finishAttendance() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: const Text('Finish Attendance?'),
        content: Text(
          'This will complete attendance for ${widget.courseCode}.\n\nTotal Present: ${_presentStudents.length} / ${_courseRoster.length} students.\n\nYou will be redirected to the detailed report.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.green.shade700,
              foregroundColor: Colors.white,
            ),
            child: const Text('Finish & View Report'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      await _dbHelper.endSession(widget.sessionId);
      final session = await _dbHelper.getSessionById(widget.sessionId);
      if (!mounted) return;
      if (session != null) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (context) => ReportScreen(session: session)),
        );
      } else {
        Navigator.pop(context);
      }
    }
  }

  // ── Back Navigation Protection ─────────────────────────────────────────────

  Future<void> _handleBackPress() async {
    final action = await showModalBottomSheet<String>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.info_outline, color: Colors.indigo),
                  const SizedBox(width: 8),
                  Text(
                    'Session in Progress (${widget.courseCode})',
                    style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              const Text(
                'Leaving this screen will not delete your data. Choose an action:',
                style: TextStyle(color: Colors.grey, fontSize: 13),
              ),
              const SizedBox(height: 20),
              ListTile(
                leading: const CircleAvatar(
                  backgroundColor: Color(0xFFFFF8E1),
                  child: Icon(Icons.pause, color: Colors.amber),
                ),
                title: const Text('Pause & Return to Dashboard',
                    style: TextStyle(fontWeight: FontWeight.w600)),
                subtitle: const Text('Keeps session active. You can resume anytime from the dashboard.'),
                onTap: () => Navigator.pop(context, 'pause_and_exit'),
              ),
              ListTile(
                leading: const CircleAvatar(
                  backgroundColor: Color(0xFFE8F5E9),
                  child: Icon(Icons.check_circle_outline, color: Colors.green),
                ),
                title: const Text('Finish Session & View Report',
                    style: TextStyle(fontWeight: FontWeight.w600, color: Colors.green)),
                subtitle: const Text('Marks the session as completed and opens the report.'),
                onTap: () => Navigator.pop(context, 'finish_and_exit'),
              ),
              ListTile(
                leading: const CircleAvatar(
                  backgroundColor: Color(0xFFEDE7F6),
                  child: Icon(Icons.arrow_back, color: Colors.indigo),
                ),
                title: const Text('Stay in Live Session',
                    style: TextStyle(fontWeight: FontWeight.w600)),
                subtitle: const Text('Continue taking attendance right now.'),
                onTap: () => Navigator.pop(context, 'stay'),
              ),
            ],
          ),
        ),
      ),
    );

    if (action == 'pause_and_exit') {
      _pauseAttendance();
      if (mounted) Navigator.pop(context);
    } else if (action == 'finish_and_exit') {
      await _dbHelper.endSession(widget.sessionId);
      final session = await _dbHelper.getSessionById(widget.sessionId);
      if (!mounted) return;
      if (session != null) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (context) => ReportScreen(session: session)),
        );
      } else {
        Navigator.pop(context);
      }
    }
  }

  // ── Nearby Connections ─────────────────────────────────────────────────────

  Future<void> _loadRoster() async {
    final roster = await _dbHelper.getRosterForCourse(widget.courseId);
    if (mounted) setState(() => _courseRoster = roster);
  }

  void _startBroadcasting() async {
    if (_isPaused) return;
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
    if (_isPaused) {
      await _proximityService.sendPayload(
        endpointId,
        jsonEncode({'status': 'fail', 'message': 'Attendance taking is currently paused.'}),
      );
      return;
    }

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
    if (_isPaused) return Colors.grey;
    final ratio = _codeDuration > 0 ? (_secondsRemaining / _codeDuration) : 1.0;
    if (ratio <= 0.2 || _secondsRemaining <= 5) return Colors.red;
    if (ratio <= 0.4 || _secondsRemaining <= 10) return Colors.orange;
    return Colors.indigo;
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) _handleBackPress();
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text('Live: ${widget.courseCode}'),
          backgroundColor: _isPaused ? Colors.blueGrey.shade800 : Colors.indigo,
          foregroundColor: Colors.white,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            tooltip: 'Leave Session Options',
            onPressed: _handleBackPress,
          ),
          actions: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14.0, vertical: 8.0),
              child: Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.white24,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    'Present: ${_presentStudents.length}/${_courseRoster.length}',
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                  ),
                ),
              ),
            ),
          ],
        ),
        body: Column(
          children: [
            // ── Paused Banner or Active PIN Panel ─────────────────────────────
            if (_isPaused)
              Container(
                padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 20),
                color: Colors.amber.shade50,
                width: double.infinity,
                child: Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.pause_circle_filled, size: 36, color: Colors.amber.shade800),
                        const SizedBox(width: 10),
                        Text(
                          'ATTENDANCE PAUSED',
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                            color: Colors.amber.shade900,
                            letterSpacing: 1.2,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'No students can check in while paused.',
                      style: TextStyle(color: Colors.amber.shade800, fontSize: 13),
                    ),
                    const SizedBox(height: 16),
                    ElevatedButton.icon(
                      onPressed: _resumeAttendance,
                      icon: const Icon(Icons.play_arrow),
                      label: const Text('Resume Attendance Now'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.green.shade700,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                    ),
                  ],
                ),
              )
            else
              AnimatedBuilder(
                animation: _flashAnimation,
                builder: (context, child) => Container(
                  padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 20),
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
                    const SizedBox(height: 12),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        // 6-digit PIN display
                        Text(
                          _currentPin.isEmpty ? '------' : _currentPin,
                          style: const TextStyle(
                            fontSize: 48,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 8,
                            fontFamily: 'monospace',
                          ),
                        ),
                        const SizedBox(width: 20),
                        // Circular countdown ring (tap to change timer)
                        Tooltip(
                          message: 'Tap to change timer duration',
                          child: InkWell(
                            onTap: _showChangeDurationDialog,
                            borderRadius: BorderRadius.circular(32),
                            child: SizedBox(
                              width: 64,
                              height: 64,
                              child: Stack(
                                alignment: Alignment.center,
                                children: [
                                  CircularProgressIndicator(
                                    value: _codeDuration > 0 ? (_secondsRemaining / _codeDuration) : 1.0,
                                    strokeWidth: 6,
                                    color: _countdownColor,
                                    backgroundColor: Colors.grey.shade200,
                                  ),
                                  Text(
                                    '$_secondsRemaining',
                                    style: TextStyle(
                                      fontSize: 18,
                                      fontWeight: FontWeight.bold,
                                      color: _countdownColor,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          'PIN refreshes automatically in $_secondsRemaining s (${_formatDurationLabel(_codeDuration)} cycle)',
                          style: TextStyle(
                            fontStyle: FontStyle.italic,
                            fontSize: 12,
                            color: Colors.indigo.shade400,
                          ),
                        ),
                        const SizedBox(width: 6),
                        InkWell(
                          onTap: _showChangeDurationDialog,
                          borderRadius: BorderRadius.circular(8),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.edit_outlined, size: 13, color: Colors.indigo.shade700),
                                const SizedBox(width: 2),
                                Text(
                                  'Change',
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.indigo.shade700,
                                    decoration: TextDecoration.underline,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),

            // ── Live Attendance Records Header ───────────────────────────────
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              color: Colors.grey.shade100,
              child: Row(
                children: [
                  Icon(
                    _isPaused ? Icons.pause_circle_outline : Icons.sensors,
                    size: 18,
                    color: _isPaused ? Colors.amber.shade800 : Colors.green.shade700,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    _isPaused ? 'Attendance Paused' : 'Live Check-in Feed',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                      color: _isPaused ? Colors.amber.shade900 : Colors.indigo.shade900,
                    ),
                  ),
                  const Spacer(),
                  Text(
                    '${_presentStudents.length} Recorded',
                    style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
                  ),
                ],
              ),
            ),

            // ── Attendance List ──────────────────────────────────────────────
            Expanded(
              child: _presentStudents.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.group_outlined, size: 56, color: Colors.grey.shade400),
                          const SizedBox(height: 12),
                          Text(
                            _isPaused
                                ? 'Attendance is paused.'
                                : 'Waiting for students to check in...',
                            style: TextStyle(color: Colors.grey.shade600),
                          ),
                        ],
                      ),
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.all(8),
                      itemCount: _presentStudents.length,
                      separatorBuilder: (context, index) => const Divider(height: 1),
                      itemBuilder: (context, index) {
                        final s = _presentStudents[index];
                        final displayName =
                            (s['name'] != null && (s['name'] as String).isNotEmpty)
                                ? s['name'] as String
                                : s['regNumber'] as String;
                        return ListTile(
                          leading: CircleAvatar(
                            backgroundColor: Colors.green.shade50,
                            child: Text(
                              '${index + 1}',
                              style: const TextStyle(
                                  color: Colors.green, fontWeight: FontWeight.bold),
                            ),
                          ),
                          title: Text(displayName,
                              style: const TextStyle(fontWeight: FontWeight.w600)),
                          subtitle: Text('Reg: ${s['regNumber']}'),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.access_time, size: 14, color: Colors.grey),
                              const SizedBox(width: 4),
                              Text(
                                DateFormat('hh:mm a')
                                    .format(DateTime.parse(s['timestamp'] as String)),
                                style: const TextStyle(color: Colors.grey, fontSize: 13),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
            ),

            // ── Action Controls Bar (Pause/Resume, Restart, Finish) ──────────
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.05),
                    blurRadius: 8,
                    offset: const Offset(0, -2),
                  ),
                ],
              ),
              child: SafeArea(
                child: Row(
                  children: [
                    // Pause / Resume Button
                    Expanded(
                      flex: 3,
                      child: ElevatedButton.icon(
                        onPressed: _isPaused ? _resumeAttendance : _pauseAttendance,
                        icon: Icon(_isPaused ? Icons.play_arrow : Icons.pause),
                        label: Text(_isPaused ? 'Resume' : 'Pause'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: _isPaused ? Colors.green.shade600 : Colors.amber.shade700,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),

                    // Restart Button
                    Expanded(
                      flex: 3,
                      child: OutlinedButton.icon(
                        onPressed: _showRestartDialog,
                        icon: const Icon(Icons.refresh),
                        label: const Text('Restart'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.indigo,
                          side: const BorderSide(color: Colors.indigo),
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),

                    // Finish Session Button
                    Expanded(
                      flex: 4,
                      child: ElevatedButton.icon(
                        onPressed: _finishAttendance,
                        icon: const Icon(Icons.check_circle_outline),
                        label: const Text('Finish'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.indigo,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
