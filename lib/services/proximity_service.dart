import 'dart:typed_data';
import 'dart:io';
import 'package:nearby_connections/nearby_connections.dart';
import 'package:device_info_plus/device_info_plus.dart';

class ProximityService {
  final Strategy strategy = Strategy.P2P_STAR;

  static Future<String> getDeviceId() async {
    DeviceInfoPlugin deviceInfo = DeviceInfoPlugin();
    if (Platform.isAndroid) {
      AndroidDeviceInfo androidInfo = await deviceInfo.androidInfo;
      return androidInfo.id; // unique ID on Android
    } else if (Platform.isIOS) {
      IosDeviceInfo iosInfo = await deviceInfo.iosInfo;
      return iosInfo.identifierForVendor ?? "ios_unknown";
    }
    return "unknown_device";
  }

  // Teacher Side
  Future<bool> startAdvertising(
    String courseCode,
    Function(String endpointId, ConnectionInfo info) onConnectionInitiated, {
    Function(String endpointId, Status status)? onConnectionResult,
    Function(String endpointId)? onDisconnected,
  }) async {
    try {
      return await Nearby().startAdvertising(
        courseCode,
        strategy,
        onConnectionInitiated: onConnectionInitiated,
        onConnectionResult: onConnectionResult ?? (id, status) {},
        onDisconnected: onDisconnected ?? (id) {},
        serviceId: "com.example.attendance",
      );
    } catch (e) {
      return false;
    }
  }

  Future<void> stopAdvertising() async {
    await Nearby().stopAdvertising();
  }

  // Student Side
  Future<bool> startDiscovery(Function(String endpointId, String endpointName, String serviceId) onEndpointFound) async {
    try {
      return await Nearby().startDiscovery(
        "Student",
        strategy,
        onEndpointFound: onEndpointFound,
        onEndpointLost: (id) {},
        serviceId: "com.example.attendance",
      );
    } catch (e) {
      return false;
    }
  }

  Future<void> stopDiscovery() async {
    await Nearby().stopDiscovery();
  }

  Future<bool> requestConnection({
    required String endpointId,
    required Function(String endpointId, ConnectionInfo info) onConnectionInitiated,
    required Function(String endpointId, Status status) onConnectionResult,
    Function(String endpointId)? onDisconnected,
    String userNickName = "Student",
  }) async {
    try {
      return await Nearby().requestConnection(
        userNickName,
        endpointId,
        onConnectionInitiated: onConnectionInitiated,
        onConnectionResult: onConnectionResult,
        onDisconnected: onDisconnected ?? (id) {},
      );
    } catch (e) {
      return false;
    }
  }

  void acceptConnection(String endpointId, Function(String endpointId, Payload payload) onPayloadReceived) {
    Nearby().acceptConnection(
      endpointId,
      onPayLoadRecieved: onPayloadReceived,
    );
  }

  Future<void> disconnectFromEndpoint(String endpointId) async {
    try {
      await Nearby().disconnectFromEndpoint(endpointId);
    } catch (_) {}
  }

  Future<void> stopAllEndpoints() async {
    try {
      await Nearby().stopAllEndpoints();
    } catch (_) {}
  }

  Future<void> sendPayload(String endpointId, String message) async {
    await Nearby().sendBytesPayload(endpointId, Uint8List.fromList(message.codeUnits));
  }
}
