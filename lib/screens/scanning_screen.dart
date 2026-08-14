import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:nearby_connections/nearby_connections.dart';
import 'package:smart_proximity_attendance/services/proximity_service.dart';

class ScanningScreen extends StatefulWidget {
  final String regNumber;
  const ScanningScreen({super.key, required this.regNumber});

  @override
  State<ScanningScreen> createState() => _ScanningScreenState();
}

class _ScanningScreenState extends State<ScanningScreen>
    with SingleTickerProviderStateMixin {
  final ProximityService _proximityService = ProximityService();

  String? _foundEndpointId;
  String? _foundCourseCode;
  bool _isConnecting = false;
  Timer? _connectionTimeoutTimer;

  // Pulse animation for the radar icon
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 1),
    )..repeat(reverse: true);
    _pulseAnimation =
        Tween<double>(begin: 0.85, end: 1.0).animate(_pulseController);
    _startScanning();
  }

  void _startScanning() async {
    await _proximityService.startDiscovery((id, name, serviceId) {
      // As soon as a class is detected, immediately prompt for PIN.
      if (_foundEndpointId == null && mounted) {
        setState(() {
          _foundEndpointId = id;
          _foundCourseCode = name;
        });
        _promptForPin();
      }
    });
  }

  void _promptForPin() async {
    final pin = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (context) => _PinEntryDialog(courseCode: _foundCourseCode!),
    );

    if (pin != null) {
      _checkIn(pin);
    } else {
      _resetScanning();
    }
  }

  void _resetScanning() {
    _connectionTimeoutTimer?.cancel();
    if (_foundEndpointId != null) {
      _proximityService.disconnectFromEndpoint(_foundEndpointId!);
    }
    _proximityService.stopDiscovery();
    if (mounted) {
      setState(() {
        _foundEndpointId = null;
        _foundCourseCode = null;
        _isConnecting = false;
      });
      _startScanning();
    }
  }

  void _checkIn(String pin) async {
    setState(() => _isConnecting = true);

    // Timeout guard so the UI does not hang if connection is dropped
    _connectionTimeoutTimer?.cancel();
    _connectionTimeoutTimer = Timer(const Duration(seconds: 15), () {
      if (mounted && _isConnecting) {
        if (_foundEndpointId != null) {
          _proximityService.disconnectFromEndpoint(_foundEndpointId!);
        }
        _showResultDialog(
          icon: Icons.timer_off_outlined,
          color: Colors.orange,
          title: 'Request Timed Out',
          message: 'The teacher\'s device did not respond. Please ensure you are close to the teacher and try again.',
          onOk: _resetScanning,
        );
      }
    });

    try {
      await _proximityService.requestConnection(
        endpointId: _foundEndpointId!,
        onConnectionInitiated: (id, info) {
          // Accept the connection and set up payload listener for the teacher's reply
          _proximityService.acceptConnection(id, (id, payload) {
            _connectionTimeoutTimer?.cancel();
            if (payload.type == PayloadType.BYTES && payload.bytes != null) {
              final response = String.fromCharCodes(payload.bytes!);
              _handleTeacherResponse(response);
            }
          });
        },
        onConnectionResult: (id, status) {
          if (status == Status.CONNECTED) {
            // Handshake completed and connection is ESTABLISHED. Now send attendance data!
            _sendAttendanceData(id, pin);
          } else {
            _connectionTimeoutTimer?.cancel();
            if (mounted && _isConnecting) {
              _showResultDialog(
                icon: Icons.error_outline,
                color: Colors.red,
                title: 'Connection Failed',
                message: 'Could not connect to teacher session ($status). Please try again.',
                onOk: _resetScanning,
              );
            }
          }
        },
        onDisconnected: (id) {
          // Disconnected callback
        },
      );
    } catch (e) {
      _connectionTimeoutTimer?.cancel();
      if (mounted && _isConnecting) {
        _showResultDialog(
          icon: Icons.error_outline,
          color: Colors.red,
          title: 'Connection Error',
          message: 'Failed to initiate connection: $e',
          onOk: _resetScanning,
        );
      }
    }
  }

  void _sendAttendanceData(String endpointId, String pin) async {
    try {
      final deviceId = await ProximityService.getDeviceId();
      final data = jsonEncode({
        'regNumber': widget.regNumber,
        'pin': pin,
        'deviceId': deviceId,
      });
      await _proximityService.sendPayload(endpointId, data);
    } catch (e) {
      _connectionTimeoutTimer?.cancel();
      if (mounted && _isConnecting) {
        _showResultDialog(
          icon: Icons.error_outline,
          color: Colors.red,
          title: 'Send Error',
          message: 'Failed to send attendance data: $e',
          onOk: _resetScanning,
        );
      }
    }
  }

  void _handleTeacherResponse(String response) {
    if (!mounted) return;
    _connectionTimeoutTimer?.cancel();
    setState(() => _isConnecting = false);

    if (_foundEndpointId != null) {
      _proximityService.disconnectFromEndpoint(_foundEndpointId!);
    }

    try {
      final result = jsonDecode(response);
      if (result['status'] == 'success') {
        _showResultDialog(
          icon: Icons.check_circle_outline,
          color: Colors.green,
          title: 'Attendance Marked!',
          message: 'Your attendance has been recorded successfully.',
          onOk: () => Navigator.pop(context), // back to dashboard
        );
      } else {
        _showResultDialog(
          icon: Icons.error_outline,
          color: Colors.red,
          title: 'Check-in Failed',
          message: result['message'] ?? 'Something went wrong. Please try again.',
          onOk: _resetScanning,
        );
      }
    } catch (e) {
      _showResultDialog(
        icon: Icons.error_outline,
        color: Colors.red,
        title: 'Error',
        message: 'Invalid response received from teacher.',
        onOk: _resetScanning,
      );
    }
  }

  void _showResultDialog({
    required IconData icon,
    required Color color,
    required String title,
    required String message,
    required VoidCallback onOk,
  }) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 8),
            Icon(icon, color: color, size: 72),
            const SizedBox(height: 16),
            Text(title,
                style:
                    const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Text(message,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.grey)),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () {
                  Navigator.pop(context); // close dialog
                  onOk();
                },
                style: ElevatedButton.styleFrom(
                    backgroundColor: color.withValues(alpha: 0.1),
                    foregroundColor: color,
                    padding: const EdgeInsets.symmetric(vertical: 14)),
                child: const Text('OK'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    _connectionTimeoutTimer?.cancel();
    _pulseController.dispose();
    if (_foundEndpointId != null) {
      _proximityService.disconnectFromEndpoint(_foundEndpointId!);
    }
    _proximityService.stopDiscovery();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Submit Attendance')),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (_isConnecting) ...[
                const CircularProgressIndicator(),
                const SizedBox(height: 24),
                const Text(
                  'Sending attendance data...',
                  style: TextStyle(fontSize: 18, color: Colors.grey),
                ),
              ] else ...[
                // Pulsing radar icon
                ScaleTransition(
                  scale: _pulseAnimation,
                  child: Container(
                    width: 140,
                    height: 140,
                    decoration: BoxDecoration(
                      color: Colors.indigo.shade50,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.radar, size: 80, color: Colors.indigo),
                  ),
                ),
                const SizedBox(height: 32),
                const Text(
                  'Searching for active class...',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 12),
                const Text(
                  'Make sure you are in the same room as your teacher\nand Bluetooth is enabled.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.grey, fontSize: 14),
                ),
                const SizedBox(height: 40),
                const CircularProgressIndicator(),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

// ─── PIN Entry Dialog ──────────────────────────────────────────────────────────

class _PinEntryDialog extends StatefulWidget {
  final String courseCode;
  const _PinEntryDialog({required this.courseCode});

  @override
  State<_PinEntryDialog> createState() => _PinEntryDialogState();
}

class _PinEntryDialogState extends State<_PinEntryDialog> {
  final _pinController = TextEditingController();
  bool _hasError = false;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: Column(
        children: [
          const Icon(Icons.lock_outline, size: 40, color: Colors.indigo),
          const SizedBox(height: 8),
          Text(
            'Enter PIN for\n${widget.courseCode}',
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
        ],
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text(
            'Enter the 6-digit PIN shown on your teacher\'s screen.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.grey, fontSize: 13),
          ),
          const SizedBox(height: 20),
          TextField(
            controller: _pinController,
            keyboardType: TextInputType.number,
            maxLength: 6,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 36,
              fontWeight: FontWeight.bold,
              letterSpacing: 10,
              fontFamily: 'monospace',
            ),
            decoration: InputDecoration(
              hintText: '000000',
              counterText: '',
              errorText: _hasError ? 'Please enter all 6 digits.' : null,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: Colors.indigo, width: 2),
              ),
            ),
            onChanged: (_) {
              if (_hasError) setState(() => _hasError = false);
            },
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: () {
            if (_pinController.text.length == 6) {
              Navigator.pop(context, _pinController.text);
            } else {
              setState(() => _hasError = true);
            }
          },
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.indigo,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
          child: const Text('Submit'),
        ),
      ],
    );
  }
}
