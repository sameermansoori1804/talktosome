import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:provider/provider.dart';
import 'webrtc_provider.dart';

class CallScreen extends StatefulWidget {
  const CallScreen({super.key});

  @override
  State<CallScreen> createState() => _CallScreenState();
}

class _CallScreenState extends State<CallScreen> {
  bool _isInitializing = true;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _initializeWebRTC();
  }

  Future<void> _initializeWebRTC() async {
    try {
      await context.read<WebRTCProvider>().initialize();
      if (mounted) {
        setState(() {
          _isInitializing = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isInitializing = false;
          _errorMessage = 'Failed to initialize: ${e.toString()}';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_errorMessage != null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Error')),
        body: Center(child: Text(_errorMessage!)),
      );
    }

    if (_isInitializing) {
      return Scaffold(
        appBar: AppBar(title: Text('Initializing...')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('WebRTC Demo'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _refreshConnection,
          ),
        ],
      ),
      body: Consumer<WebRTCProvider>(
        builder: (context, provider, _) {
          return Column(
            children: [
              _buildVideoSection(provider),
              _buildUserListSection(provider),
              _buildControlSection(provider),
            ],
          );
        },
      ),
    );
  }

  Widget _buildVideoSection(WebRTCProvider provider) {
    bool hasRemoteVideo = provider.remoteRenderers.isNotEmpty;
    final remoteRenderer = hasRemoteVideo ? provider.remoteRenderers.first : null;

    return Expanded(
      flex: 2,
      child: Stack(
        fit: StackFit.expand,
        children: [
          // Remote video
          if (hasRemoteVideo)
            LayoutBuilder(
              builder: (context, constraints) {
                // Dynamically choose fit based on aspect ratio
                num width = remoteRenderer?.videoWidth ?? 0;
                num height = remoteRenderer?.videoHeight ?? 0;
                bool isPortrait = height > width;

                return RTCVideoView(
                  remoteRenderer!,
                  objectFit: isPortrait
                      ? RTCVideoViewObjectFit.RTCVideoViewObjectFitContain
                      : RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
                );
              },
            )
          else
            const Center(
              child: Text(
                '📞 Waiting for remote video...',
                style: TextStyle(fontSize: 18, color: Colors.white70),
              ),
            ),

          // Local preview (small)
          if (provider.localRenderer.srcObject != null)
            Positioned(
              right: 16,
              bottom: 16,
              width: 120,
              height: 160,
              child: GestureDetector(
                onPanUpdate: (details) {
                  // Optional: make preview draggable
                },
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: Container(
                    decoration: BoxDecoration(
                      border: Border.all(color: Colors.white54, width: 2),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black26,
                          blurRadius: 8,
                        )
                      ],
                    ),
                    child: RTCVideoView(
                      provider.localRenderer,
                      mirror: true,
                      objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
                    ),
                  ),
                ),
              ),
            ),

          // Call control buttons at bottom
          // Positioned(
          //   bottom: 24,
          //   left: 0,
          //   right: 0,
          //   child: Row(
          //     mainAxisAlignment: MainAxisAlignment.center,
          //     children: [
          //       FloatingActionButton(
          //         backgroundColor: Colors.red,
          //         onPressed: () {
          //           provider.endCall();
          //         },
          //         child: const Icon(Icons.call_end),
          //       ),
          //       const SizedBox(width: 20),
          //       FloatingActionButton(
          //         backgroundColor: Colors.white,
          //         onPressed: () {
          //           provider.toggleCamera();
          //         },
          //         child: const Icon(Icons.cameraswitch, color: Colors.black),
          //       ),
          //       const SizedBox(width: 20),
          //       FloatingActionButton(
          //         backgroundColor: Colors.white,
          //         onPressed: () {
          //           provider.toggleMic();
          //         },
          //         child: const Icon(Icons.mic, color: Colors.black),
          //       ),
          //     ],
          //   ),
          // ),
        ],
      ),
    );
  }


  Widget _buildUserListSection(WebRTCProvider provider) {
    return Expanded(
      flex: 1,
      child: Column(
        children: [
          const Padding(
            padding: EdgeInsets.all(8.0),
            child: Text(
              'Online Users',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
          Expanded(
            child: provider.users.isEmpty
                ? const Center(child: Text('No other users online'))
                : ListView.builder(
              itemCount: provider.users.length,
              itemBuilder: (context, index) {
                final user = provider.users[index];
                return ListTile(
                  leading: const Icon(Icons.person),
                  title: Text(user['id']),
                  onTap: () => provider.callUser(user['id']),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildControlSection(WebRTCProvider provider) {
    return Padding(
      padding: const EdgeInsets.all(8.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          ElevatedButton.icon(
            icon: const Icon(Icons.mic),
            label: const Text('Audio'),
            onPressed: provider.startAudioOnlyStream,
          ),
          ElevatedButton.icon(
            icon: const Icon(Icons.videocam),
            label: const Text('Video'),
            onPressed: provider.startVideoStream,
          ),
          ElevatedButton.icon(
            icon: const Icon(Icons.call),
            label: const Text('Ca'),
            onPressed: provider.users.isNotEmpty
                ? () => provider.callUser(provider.users.first['id'])
                : null,
          ),
        ],
      ),
    );
  }

  Future<void> _refreshConnection() async {
    setState(() {
      _isInitializing = true;
      _errorMessage = null;
    });
    await _initializeWebRTC();
  }
}