import 'package:livekit_client/livekit_client.dart';

/// Shared LiveKit connection functionality for one-on-one calls.
class CallingService {
  Room? _room;

  Room? get room => _room;

  bool get isConnected => _room != null;

  Future<Room> connect({
    required String liveKitUrl,
    required String token,
  }) async {
    if (_room != null) {
      return _room!;
    }

    final newRoom = Room();

    await newRoom.connect(liveKitUrl, token);

    _room = newRoom;

    return newRoom;
  }

  Future<void> disconnect() async {
    final currentRoom = _room;

    _room = null;

    await currentRoom?.disconnect();
  }

  Future<void> enableCamera() async {
    final localParticipant = _room?.localParticipant;

    if (localParticipant == null) {
      throw Exception('Not connected to a LiveKit room.');
    }

    await localParticipant.setCameraEnabled(true);
  }

  Future<void> disableCamera() async {
    final localParticipant = _room?.localParticipant;

    if (localParticipant == null) {
      throw Exception('Not connected to a LiveKit room.');
    }

    await localParticipant.setCameraEnabled(false);
  }

  Future<void> enableMicrophone() async {
    final localParticipant = _room?.localParticipant;

    if (localParticipant == null) {
      throw Exception('Not connected to a LiveKit room.');
    }

    await localParticipant.setMicrophoneEnabled(true);
  }

  Future<void> disableMicrophone() async {
    final localParticipant = _room?.localParticipant;

    if (localParticipant == null) {
      throw Exception('Not connected to a LiveKit room.');
    }

    await localParticipant.setMicrophoneEnabled(false);
  }
}
