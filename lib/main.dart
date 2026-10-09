import 'package:flutter/material.dart';
import 'package:livekit_client/livekit_client.dart';

void main() {
  runApp(const VideoChatApp());
}

class VideoChatApp extends StatelessWidget {
  const VideoChatApp({super.key});

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      debugShowCheckedModeBanner: false,
      home: HomePage(),
    );
  }
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final roomNameController = TextEditingController();

  @override
  void dispose() {
    roomNameController.dispose();
    super.dispose();
  }

  void joinRoom() {
    final roomName = roomNameController.text.trim();

    if (roomName.isEmpty) {
      return;
    }

    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => VideoRoomPage(roomName: roomName)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: SizedBox(
          width: 350,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Text(
                'Video Chat MVP',
                style: TextStyle(fontSize: 32, fontWeight: FontWeight.bold),
              ),

              const SizedBox(height: 30),

              TextField(
                controller: roomNameController,
                decoration: const InputDecoration(
                  labelText: 'Room Name',
                  border: OutlineInputBorder(),
                ),
              ),

              const SizedBox(height: 20),

              ElevatedButton(
                onPressed: joinRoom,
                child: const Text('Join Room'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class VideoRoomPage extends StatefulWidget {
  final String roomName;

  const VideoRoomPage({super.key, required this.roomName});

  @override
  State<VideoRoomPage> createState() => _VideoRoomPageState();
}

class _VideoRoomPageState extends State<VideoRoomPage> {
  Room? room;
  bool isConnecting = false;
  String status = 'Not connected';

  Future<void> connectToRoom() async {
    setState(() {
      isConnecting = true;
      status = 'Connecting...';
    });

    try {
      final newRoom = Room();

      const liveKitUrl = 'wss://video-chat-mvp-raq8joq9.livekit.cloud';

      // Temporary placeholder: obtain a token from a trusted backend
      // before enabling LiveKit connections.
      const token = '';

      await newRoom.connect(liveKitUrl, token);

      final localParticipant = newRoom.localParticipant;

      if (localParticipant == null) {
        throw Exception('Local participant was not created');
      }

      await localParticipant.setCameraEnabled(true);
      await localParticipant.setMicrophoneEnabled(true);

      setState(() {
        room = newRoom;
        status = 'Connected to ${widget.roomName}';
      });
    } catch (error) {
      setState(() {
        status = 'Connection failed: $error';
      });
    } finally {
      setState(() {
        isConnecting = false;
      });
    }
  }

  Future<void> disconnect() async {
    await room?.disconnect();

    setState(() {
      room = null;
      status = 'Disconnected';
    });
  }

  @override
  void dispose() {
    room?.disconnect();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Room: ${widget.roomName}')),
      body: Column(
        children: [
          Expanded(
            child: Container(
              width: double.infinity,
              color: Colors.black,
              child: room != null
                  ? buildLocalVideo()
                  : const Center(
                      child: Text(
                        'Not connected',
                        style: TextStyle(color: Colors.white),
                      ),
                    ),
            ),
          ),

          Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              children: [
                Text(status),

                const SizedBox(height: 20),

                if (room == null)
                  ElevatedButton(
                    onPressed: isConnecting ? null : connectToRoom,
                    child: Text(
                      isConnecting ? 'Connecting...' : 'Connect Camera',
                    ),
                  ),

                if (room != null)
                  ElevatedButton(
                    onPressed: disconnect,
                    child: const Text('Leave Room'),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget buildLocalVideo() {
    final localParticipant = room?.localParticipant;

    if (localParticipant == null) {
      return const Center(child: Text('Camera not available'));
    }

    final publications = localParticipant.videoTrackPublications;

    if (publications.isEmpty) {
      return const Center(child: Text('Waiting for camera...'));
    }

    final videoTrack = publications.first.track;

    if (videoTrack is! LocalVideoTrack) {
      return const Center(child: Text('Waiting for camera...'));
    }

    return VideoTrackRenderer(videoTrack, fit: VideoViewFit.cover);
  }
}
