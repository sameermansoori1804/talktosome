import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:socket_io_client/socket_io_client.dart' as io;

// Define signaling state enum at the top level
enum SignalingState { stable, haveLocalOffer, haveRemoteOffer, closed }

class WebRTCProvider with ChangeNotifier {
  late io.Socket socket;
  final Map<String, RTCPeerConnection> _peerConnections = {};
  final List<RTCVideoRenderer> _remoteRenderers = [];
  RTCVideoRenderer _localRenderer = RTCVideoRenderer();
  List<Map<String, dynamic>> _users = [];
  MediaStream? _localStream;
  SignalingState _signalingState = SignalingState.stable;

  // ICE Configuration
  final Map<String, dynamic> _iceConfig = {
    'iceServers': [
      {'urls': 'stun:stun.l.google.com:19302'},
      {'urls': 'stun:stun1.l.google.com:19302'},
      {'urls': 'stun:stun2.l.google.com:19302'},
      // Add a TURN server (critical for mobile networks)
      {
        'urls': 'turn:talktosome.flexonsoft.com:3478',
        'username': 'testuser',
        'credential': 'SuperSecretKey123'
      }
    ],
    'iceTransportPolicy': 'all', // Try both relay and host candidates
    'bundlePolicy': 'max-bundle',
    'rtcpMuxPolicy': 'require',
    'sdpSemantics': 'unified-plan'
  };

  RTCVideoRenderer get localRenderer => _localRenderer;
  List<RTCVideoRenderer> get remoteRenderers => _remoteRenderers;
  List<Map<String, dynamic>> get users => _users;

  Future<void> initialize() async {
    try {
      await _localRenderer.initialize();
      await _initWebRTC();
      _setupSocket();
    } catch (e) {
      print('Initialization error: $e');
      rethrow;
    }
  }

  Future<void> _initWebRTC() async {
    try {
      await WebRTC.initialize();
      print('WebRTC initialized successfully');
    } on PlatformException catch (e) {
      print('Failed to initialize WebRTC: ${e.message}');
      rethrow;
    }
  }

  Future<void> startLocalStream() async {
    try {
      final mediaConstraints = {
        'audio': {
          'echoCancellation': true,
          'noiseSuppression': true,
          'autoGainControl': true
        },
        'video': {
          'width': {'ideal': 1240},
          'height': {'ideal': 720},
          'facingMode': 'user',
          'frameRate': {'ideal': 24}
        }
      };

      _localStream = await navigator.mediaDevices.getUserMedia(mediaConstraints);
      _localRenderer.srcObject = _localStream;
      notifyListeners();
    } on PlatformException catch (e) {
      print('Failed to get media: ${e.message}');
      rethrow;
    }
  }

  Future<void> startAudioOnlyStream() async {
    try {
      final mediaConstraints = {
        'audio': {
          'echoCancellation': true,
          'noiseSuppression': true,
          'autoGainControl': true,
          'channelCount': 2,
        },
        'video': false,
      };

      _localStream = await navigator.mediaDevices.getUserMedia(mediaConstraints);
      _localRenderer.srcObject = _localStream;
      notifyListeners();
    } on PlatformException catch (e) {
      print('Failed to get audio: ${e.message}');
      rethrow;
    }
  }

  Future<void> startVideoStream() async {
    try {
      final mediaConstraints = {
        'audio': {
          'echoCancellation': true,
          'noiseSuppression': true,
          'autoGainControl': true,
          'channelCount': 2,
        },
        'video': {
          'mandatory': {
            'minWidth': 1280,
            'minHeight': 720,
            'minFrameRate': 30,
          },
          'facingMode': 'user',
          'optional': [],
        }
      };

      _localStream = await navigator.mediaDevices.getUserMedia(mediaConstraints);
      _localRenderer.srcObject = _localStream;
      notifyListeners();
    } on PlatformException catch (e) {
      print('Failed to get video: ${e.message}');
      rethrow;
    }
  }

  void _setupSocket() {
    socket = io.io(
      'https://talktosome.flexonsoft.com',
      io.OptionBuilder()
          .setTransports(['websocket'])
          .enableForceNewConnection()  // Add this
          .setPath('/socket.io')
          .setQuery({'platform': 'flutter'})  // Explicit platform identification
          .build(),
    );

    socket.on('connect', (_) {
      print('✅ Mobile Connected with ID: ${socket.id}');
      socket.emit('register-client', {
        'id': socket.id,
        'platform': 'flutter',
        'userAgent': 'flutter-webrtc'
      });
    });

    socket.on('user-list', (users) {
      _users = List<Map<String, dynamic>>.from(users)
          .where((user) => user['id'] != socket.id)
          .toList();
      notifyListeners();
    });

    socket.on('webrtc-offer', _handleOffer);
    socket.on('webrtc-answer', _handleAnswer);
    socket.on('webrtc-candidate', _handleCandidate);
    socket.on('user-disconnected', _handleDisconnect);

    socket.on('error', (err) => print('Socket error: $err'));
    socket.on('disconnect', (reason) => print('Disconnected: $reason'));
  }

  Future<void> _handleOffer(dynamic data) async {
    try {
      final sender = data['sender'];
      final offer = RTCSessionDescription(data['offer']['sdp'], data['offer']['type']);

      if (_signalingState != SignalingState.stable) {
        print('Cannot handle offer - not in stable state');
        return;
      }

      final pc = await _createPeerConnection(sender);
      await pc.setRemoteDescription(offer);
      _signalingState = SignalingState.haveRemoteOffer;

      final answer = await pc.createAnswer();
      await pc.setLocalDescription(answer);
      _signalingState = SignalingState.stable;

      socket.emit('webrtc-answer', {
        'answer': {'sdp': answer.sdp, 'type': answer.type},
        'target': sender
      });
    } catch (e) {
      print('Offer handling error: $e');
    }
  }

  Future<void> _handleAnswer(dynamic data) async {
    try {
      final pc = _peerConnections[data['sender']];
      if (pc == null || _signalingState != SignalingState.haveLocalOffer) {
        print('Cannot set answer - no pending offer');
        return;
      }

      final answer = RTCSessionDescription(data['answer']['sdp'], data['answer']['type']);
      await pc.setRemoteDescription(answer);
      _signalingState = SignalingState.stable;
    } catch (e) {
      print('Answer handling error: $e');
    }
  }

  Future<void> _handleCandidate(dynamic data) async {
    try {
      final pc = _peerConnections[data['sender']];
      if (pc == null) return;

      await pc.addCandidate(RTCIceCandidate(
        data['candidate']['candidate'],
        data['candidate']['sdpMid'],
        data['candidate']['sdpMlineIndex'],
      ));
    } catch (e) {
      print('Candidate handling error: $e');
    }
  }
  void _handleDisconnect(dynamic data) {
    final userId = data as String; // Explicit cast
    _disconnectPeer(userId);
    _users.removeWhere((user) => user['id'] == userId);
    notifyListeners();
  }

  Future<RTCPeerConnection> _createPeerConnection(String targetUserId) async {
    if (_peerConnections.containsKey(targetUserId)) {
      return _peerConnections[targetUserId]!;
    }

    final pc = await createPeerConnection(_iceConfig);

    pc.onIceCandidate = (candidate) {
      if (candidate != null) {
        socket.emit('webrtc-candidate', {
          'candidate': {
            'candidate': candidate.candidate,
            'sdpMid': candidate.sdpMid,
            'sdpMlineIndex': candidate.sdpMLineIndex,
          },
          'target': targetUserId,
          'sender': socket.id
        });
      }
    };

    pc.onAddStream = (stream) async {
      final renderer = RTCVideoRenderer();
      await renderer.initialize();
      renderer.srcObject = stream;
      _remoteRenderers.add(renderer);
      notifyListeners();
    };

    pc.onIceConnectionState = (state) {
      print('ICE state for $targetUserId: $state');
      if (state == RTCIceConnectionState.RTCIceConnectionStateFailed) {
        pc.restartIce();
      }
    };

    pc.onSignalingState = (state) {
      print('Signaling state for $targetUserId: $state');
    };

    if (_localStream != null) {
      _localStream!.getTracks().forEach((track) {
        pc.addTrack(track, _localStream!);
      });
    }

    _peerConnections[targetUserId] = pc;
    return pc;
  }

  Future<void> callUser(String targetUserId) async {
    if (_localStream == null || _signalingState != SignalingState.stable) return;

    try {
      final pc = await _createPeerConnection(targetUserId);
      _signalingState = SignalingState.haveLocalOffer;

      final offer = await pc.createOffer();
      await pc.setLocalDescription(offer);

      socket.emit('webrtc-offer', {
        'offer': {'sdp': offer.sdp, 'type': offer.type},
        'target': targetUserId
      });
    } catch (e) {
      _signalingState = SignalingState.stable;
      print('Call initiation error: $e');
      rethrow;
    }
  }

  void _disconnectPeer(String userId) {
    final pc = _peerConnections.remove(userId);
    pc?.close();

    try {
      final renderer = _remoteRenderers.firstWhere(
            (r) => r.srcObject?.id == userId,
      );
      renderer.dispose();
      _remoteRenderers.remove(renderer);
    } catch (e) {
      print('No renderer found for $userId');
    }

    _signalingState = SignalingState.stable;
    notifyListeners();
  }

  @override
  void dispose() {
    _localRenderer.dispose();
    for (var renderer in _remoteRenderers) {
      renderer.dispose();
    }
    for (var pc in _peerConnections.values) {
      pc.close();
    }
    socket.dispose();
    super.dispose();
  }
}