import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:uuid/uuid.dart';
import '../api.dart';
import '../errors.dart';
import 'realtime_bus.dart';

enum CallPhase {
  idle,
  initiating,
  ringing,
  accepted,
  connecting,
  connected,
  reconnecting,
  ended,
  rejected,
  cancelled,
  missed,
  failed,
}

enum AudioOutputRoute { earpiece, speaker, bluetooth }

/// Decoupled WebRTC CallManager (Phase 8, Section 45).
/// Manages peer connection, ICE restart, quality metrics, and server signaling
/// independently of Widget lifecycles. Duration starts strictly on CONNECTED.
class CallManager extends ChangeNotifier {
  final TamreedyApi api;
  final RealtimeEventBus eventBus;

  CallManager({required this.api, required this.eventBus}) {
    _busSub = eventBus.whereType(_callEventTypes).listen(_onBusEvent);
  }

  static const _callEventTypes = {
    'call.incoming',
    'call.ringing',
    'call.accepted',
    'call.rejected',
    'call.cancel',
    'call.signal',
    'call.connected',
    'call.reconnecting',
    'call.ended',
    'call.missed',
    'call.failed',
  };

  static const _uuid = Uuid();

  StreamSubscription<RealtimeEvent>? _busSub;
  Timer? _pollTimer;
  Timer? _durationTimer;
  Timer? _reconnectTimer;
  Timer? _qualityTimer;

  RTCPeerConnection? _pc;
  MediaStream? _localStream;
  final Set<String> _handledSignals = <String>{};
  final List<RTCIceCandidate> _pendingCandidates = <RTCIceCandidate>[];
  bool _remoteDescriptionSet = false;
  bool _offerSent = false;
  bool _answerSent = false;
  bool _connectedReported = false;
  int _signalSequence = 0;
  int _reconnectAttempts = 0;

  String? _callId;
  String? _requestId;
  String _peerName = 'المستخدم';
  String _peerRole = 'مكالمة تمريضي الآمنة';
  bool _isIncoming = false;
  CallPhase _phase = CallPhase.idle;
  String? _error;
  bool _muted = false;
  AudioOutputRoute _audioRoute = AudioOutputRoute.earpiece;
  bool _acting = false;
  int _elapsedSeconds = 0;
  bool _overlayVisible = false;

  String? get callId => _callId;
  String? get requestId => _requestId;
  String get peerName => _peerName;
  String get peerRole => _peerRole;
  bool get isIncoming => _isIncoming;
  CallPhase get phase => _phase;
  String? get error => _error;
  bool get muted => _muted;
  AudioOutputRoute get audioRoute => _audioRoute;
  bool get speakerOn => _audioRoute == AudioOutputRoute.speaker;
  bool get bluetoothOn => _audioRoute == AudioOutputRoute.bluetooth;
  bool get acting => _acting;
  int get elapsedSeconds => _elapsedSeconds;
  bool get overlayVisible => _overlayVisible;

  bool get isActive =>
      _phase != CallPhase.idle && !isTerminal;

  bool get isIncomingWaiting =>
      _isIncoming && (_phase == CallPhase.ringing || _phase == CallPhase.initiating);

  bool get isTerminal => const {
    CallPhase.ended,
    CallPhase.rejected,
    CallPhase.cancelled,
    CallPhase.missed,
    CallPhase.failed,
  }.contains(_phase);

  void _resetMediaState() {
    _pollTimer?.cancel();
    _pollTimer = null;
    _durationTimer?.cancel();
    _durationTimer = null;
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    _qualityTimer?.cancel();
    _qualityTimer = null;
    _handledSignals.clear();
    _pendingCandidates.clear();
    _remoteDescriptionSet = false;
    _offerSent = false;
    _answerSent = false;
    _connectedReported = false;
    _signalSequence = 0;
    _reconnectAttempts = 0;
  }

  Future<void> _disposeWebRtc() async {
    try {
      await _localStream?.dispose();
    } catch (_) {}
    _localStream = null;
    try {
      await _pc?.close();
    } catch (_) {}
    _pc = null;
  }

  Future<void> startOutgoing({
    required String requestId,
    required String peerName,
    required String peerRole,
  }) async {
    if (isActive) {
      _overlayVisible = true;
      notifyListeners();
      return;
    }
    _resetMediaState();
    _callId = null;
    _requestId = requestId;
    _peerName = peerName;
    _peerRole = peerRole;
    _isIncoming = false;
    _phase = CallPhase.initiating;
    _error = null;
    _muted = false;
    _audioRoute = AudioOutputRoute.earpiece;
    _elapsedSeconds = 0;
    _overlayVisible = true;
    notifyListeners();

    try {
      final res = await api.post(
        '/v1/calls/initiate',
        {'requestId': requestId},
        {'Idempotency-Key': _uuid.v4()},
      );
      _callId = res['id']?.toString();
      _phase = _parsePhase(res['call_status']?.toString()) ?? CallPhase.ringing;
      notifyListeners();
      try {
        await _initPeerConnection(res['ice_servers'] as List?);
        await _sendOfferIfCaller();
      } catch (e) {
        _error = 'تعذر الوصول إلى الميكروفون أو تأسيس الصوت';
        notifyListeners();
      }
      _startPolling();
    } catch (e) {
      _phase = CallPhase.failed;
      _error = explainError(e, fallback: 'الاتصال الصوتي متاح فقط أثناء الزيارة النشطة');
      notifyListeners();
    }
  }

  Future<void> presentIncoming({
    required String callId,
    required String requestId,
    required String peerName,
    required String peerRole,
  }) async {
    if (_callId == callId && isActive) {
      _overlayVisible = true;
      notifyListeners();
      return;
    }
    _resetMediaState();
    _callId = callId;
    _requestId = requestId;
    _peerName = peerName;
    _peerRole = peerRole;
    _isIncoming = true;
    _phase = CallPhase.ringing;
    _error = null;
    _muted = false;
    _audioRoute = AudioOutputRoute.earpiece;
    _elapsedSeconds = 0;
    _overlayVisible = true;
    notifyListeners();
    _startPolling();
    await refresh();
  }

  Future<void> checkActiveCalls({required String defaultPeerName, required String defaultPeerRole}) async {
    try {
      final active = await api.getList('/v1/calls/active/mine');
      if (active.isEmpty) return;
      final raw = Map<String, dynamic>.from(active.first as Map);
      final id = raw['id']?.toString();
      if (id == null || id.isEmpty) return;
      if (_callId == id && isActive) return;
      await presentIncoming(
        callId: id,
        requestId: raw['request_id']?.toString() ?? '',
        peerName: defaultPeerName,
        peerRole: defaultPeerRole,
      );
    } catch (_) {}
  }

  Future<void> acceptIncoming() async {
    final id = _callId;
    if (id == null || _acting) return;
    _acting = true;
    notifyListeners();
    try {
      final res = await api.post('/v1/calls/$id/accept', {});
      _phase = _parsePhase(res['call_status']?.toString()) ?? CallPhase.accepted;
      notifyListeners();
      await _initPeerConnection(res['ice_servers'] as List?);
      await refresh();
    } catch (e) {
      _error = explainError(e, fallback: 'تعذر الرد على المكالمة');
    } finally {
      _acting = false;
      notifyListeners();
    }
  }

  Future<void> rejectIncoming() async {
    final id = _callId;
    if (id == null || _acting) return;
    _acting = true;
    notifyListeners();
    try {
      await api.post('/v1/calls/$id/reject', {'reason': 'DECLINED'});
    } catch (_) {}
    _phase = CallPhase.rejected;
    _acting = false;
    _resetMediaState();
    await _disposeWebRtc();
    _overlayVisible = false;
    notifyListeners();
  }

  Future<void> endCall() async {
    final id = _callId;
    if (id != null && !_acting && !isTerminal) {
      _acting = true;
      notifyListeners();
      try {
        await api.post('/v1/calls/$id/end', {'reason': 'HANGUP'});
      } catch (_) {}
    }
    _phase = CallPhase.ended;
    _acting = false;
    _resetMediaState();
    await _disposeWebRtc();
    _overlayVisible = false;
    notifyListeners();
  }

  void dismissOverlay() {
    _overlayVisible = false;
    if (isTerminal) {
      _phase = CallPhase.idle;
      _callId = null;
      _requestId = null;
      _error = null;
      _elapsedSeconds = 0;
    }
    notifyListeners();
  }

  void showOverlay() {
    if (isActive || isTerminal) {
      _overlayVisible = true;
      notifyListeners();
    }
  }

  void toggleMute() {
    _muted = !_muted;
    for (final track in _localStream?.getAudioTracks() ?? const <MediaStreamTrack>[]) {
      track.enabled = !_muted;
    }
    notifyListeners();
  }

  Future<void> cycleAudioRoute() async {
    final next = switch (_audioRoute) {
      AudioOutputRoute.earpiece => AudioOutputRoute.speaker,
      AudioOutputRoute.speaker => AudioOutputRoute.bluetooth,
      AudioOutputRoute.bluetooth => AudioOutputRoute.earpiece,
    };
    await setAudioRoute(next);
  }

  Future<void> setAudioRoute(AudioOutputRoute route) async {
    _audioRoute = route;
    notifyListeners();
    try {
      await Helper.setSpeakerphoneOn(route == AudioOutputRoute.speaker);
      if (route == AudioOutputRoute.bluetooth) {
        await Helper.selectAudioOutput('bluetooth').catchError((_) {});
      } else if (route == AudioOutputRoute.earpiece) {
        await Helper.selectAudioOutput('earpiece').catchError((_) {});
      }
    } catch (_) {}
  }

  Future<void> _initPeerConnection(List<dynamic>? rawIceServers) async {
    if (_pc != null) return;
    final iceServers = (rawIceServers != null && rawIceServers.isNotEmpty)
        ? rawIceServers.map((e) => Map<String, dynamic>.from(e as Map)).toList()
        : [
            {'urls': 'stun:stun.l.google.com:19302'},
            {'urls': 'stun:stun1.l.google.com:19302'},
          ];

    final pc = await createPeerConnection({
      'iceServers': iceServers,
      'sdpSemantics': 'unified-plan',
    });

    final stream = await navigator.mediaDevices.getUserMedia({
      'audio': {
        'echoCancellation': true,
        'noiseSuppression': true,
        'autoGainControl': true,
      },
      'video': false,
    });

    for (final track in stream.getAudioTracks()) {
      await pc.addTrack(track, stream);
    }

    pc.onIceCandidate = (candidate) {
      final id = _callId;
      if (id == null || candidate.candidate == null) return;
      _sendSignal('ICE_CANDIDATE', {
        'candidate': candidate.candidate,
        'sdpMid': candidate.sdpMid,
        'sdpMLineIndex': candidate.sdpMLineIndex,
      }).catchError((_) => <String, dynamic>{});
    };

    pc.onConnectionState = (state) {
      if (state == RTCPeerConnectionState.RTCPeerConnectionStateConnected) {
        _reconnectTimer?.cancel();
        _reconnectTimer = null;
        _reconnectAttempts = 0;
        _phase = CallPhase.connected;
        _ensureDurationTimer();
        _startQualityMonitoring();
        if (!_connectedReported && _callId != null) {
          _connectedReported = true;
          api.post('/v1/calls/${_callId!}/connected', {}).catchError((_) => <String, dynamic>{});
        }
        notifyListeners();
      } else if (state == RTCPeerConnectionState.RTCPeerConnectionStateDisconnected ||
          state == RTCPeerConnectionState.RTCPeerConnectionStateFailed) {
        if (!isTerminal) {
          _phase = CallPhase.reconnecting;
          notifyListeners();
          if (!_isIncoming) _scheduleIceRestart();
        }
      }
    };

    _pc = pc;
    _localStream = stream;
    try {
      await Helper.setSpeakerphoneOn(_audioRoute == AudioOutputRoute.speaker);
    } catch (_) {}
  }

  Future<void> _sendOfferIfCaller() async {
    final id = _callId;
    final pc = _pc;
    if (id == null || pc == null || _offerSent) return;
    _offerSent = true;
    final offer = await pc.createOffer({'offerToReceiveAudio': true});
    await pc.setLocalDescription(offer);
    await _sendSignal('SDP_OFFER', {'sdp': offer.sdp, 'type': offer.type});
  }

  Future<void> _consumeSignals(List<dynamic>? rawSignals) async {
    if (rawSignals == null || rawSignals.isEmpty || _pc == null) return;
    for (final raw in rawSignals) {
      final sig = Map<String, dynamic>.from(raw as Map);
      final sigId = sig['id']?.toString() ?? sig['event_id']?.toString() ?? '';
      if (sigId.isNotEmpty && !_handledSignals.add(sigId)) continue;
      final type = sig['event_type']?.toString();
      final data = sig['event_data'] is Map
          ? Map<String, dynamic>.from(sig['event_data'] as Map)
          : <String, dynamic>{};

      if ((type == 'SDP_OFFER' || type == 'ICE_RESTART') && _isIncoming) {
        final sdp = data['sdp']?.toString();
        final sdpType = data['type']?.toString() ?? 'offer';
        if (sdp != null && (!_remoteDescriptionSet || type == 'ICE_RESTART')) {
          await _pc!.setRemoteDescription(RTCSessionDescription(sdp, sdpType));
          _remoteDescriptionSet = true;
          await _flushPendingCandidates();
          if (!_answerSent && _callId != null) {
            _answerSent = true;
            final answer = await _pc!.createAnswer();
            await _pc!.setLocalDescription(answer);
            await _sendSignal('SDP_ANSWER', {'sdp': answer.sdp, 'type': answer.type});
          }
        }
      } else if (type == 'SDP_ANSWER' && !_isIncoming) {
        final sdp = data['sdp']?.toString();
        final sdpType = data['type']?.toString() ?? 'answer';
        if (sdp != null && !_remoteDescriptionSet) {
          await _pc!.setRemoteDescription(RTCSessionDescription(sdp, sdpType));
          _remoteDescriptionSet = true;
          await _flushPendingCandidates();
        }
      } else if (type == 'ICE_CANDIDATE') {
        final candStr = data['candidate']?.toString();
        if (candStr != null) {
          final cand = RTCIceCandidate(
            candStr,
            data['sdpMid']?.toString(),
            int.tryParse('${data['sdpMLineIndex'] ?? 0}'),
          );
          if (_remoteDescriptionSet) {
            await _pc!.addCandidate(cand);
          } else {
            _pendingCandidates.add(cand);
          }
        }
      }
    }
  }

  Future<void> _flushPendingCandidates() async {
    for (final c in _pendingCandidates) {
      await _pc?.addCandidate(c);
    }
    _pendingCandidates.clear();
  }

  Future<Map<String, dynamic>> _sendSignal(String eventType, Map<String, dynamic> data) {
    final id = _callId;
    if (id == null) return Future.value(<String, dynamic>{});
    _signalSequence++;
    return api.post('/v1/calls/$id/signal', {
      'eventId': _uuid.v4(),
      'sequenceNumber': _signalSequence,
      'eventType': eventType,
      'data': data,
    });
  }

  void _scheduleIceRestart() {
    if (_reconnectTimer != null || _reconnectAttempts >= 3) return;
    final delay = Duration(seconds: 1 << _reconnectAttempts);
    _reconnectTimer = Timer(delay, () async {
      _reconnectTimer = null;
      final pc = _pc;
      if (pc == null || _phase == CallPhase.connected || isTerminal) return;
      _reconnectAttempts++;
      try {
        final offer = await pc.createOffer({'iceRestart': true, 'offerToReceiveAudio': true});
        await pc.setLocalDescription(offer);
        await _sendSignal('ICE_RESTART', {'sdp': offer.sdp, 'type': offer.type});
      } catch (_) {}
      if (_phase != CallPhase.connected && _reconnectAttempts >= 3) {
        _phase = CallPhase.failed;
        _error = 'تعذر الحفاظ على استقرار المكالمة';
        notifyListeners();
        final id = _callId;
        if (id != null) {
          api.post('/v1/calls/$id/end', {'reason': 'ICE_RESTART_EXHAUSTED'}).catchError((_) => <String, dynamic>{});
        }
      } else if (_phase != CallPhase.connected) {
        _scheduleIceRestart();
      }
    });
  }

  void _onBusEvent(RealtimeEvent evt) {
    if (evt.type == 'call.incoming') {
      final incomingId = evt.payload['callId']?.toString();
      if (incomingId != null && incomingId.isNotEmpty) {
        presentIncoming(
          callId: incomingId,
          requestId: evt.payload['requestId']?.toString() ?? '',
          peerName: evt.payload['callerRole'] == 'NURSE' ? 'الممرض المعتمد' : 'المريض',
          peerRole: 'مكالمة صوتية آمنة',
        );
      }
      return;
    }

    if (evt.payload['callId']?.toString() != _callId) return;
    if (evt.type == 'call.signal') {
      final eventType = evt.payload['eventType']?.toString();
      final data = evt.payload['data'];
      if (eventType != null && data is Map) {
        _consumeSignals([
          {
            'id': evt.payload['eventId'],
            'event_type': eventType,
            'event_data': Map<String, dynamic>.from(data),
          },
        ]).catchError((_) {});
      }
      return;
    }

    final next = switch (evt.type) {
      'call.accepted' => CallPhase.accepted,
      'call.connected' => CallPhase.connected,
      'call.reconnecting' => CallPhase.reconnecting,
      'call.rejected' => CallPhase.rejected,
      'call.cancel' => CallPhase.cancelled,
      'call.ended' => CallPhase.ended,
      'call.missed' => CallPhase.missed,
      'call.failed' => CallPhase.failed,
      _ => null,
    };
    if (next != null) {
      _phase = next;
      // Only start duration timer if WebRTC is genuinely connected (never on ACCEPTED alone)
      if (next == CallPhase.connected && _pc != null) {
        _ensureDurationTimer();
      }
      if (isTerminal) {
        _resetMediaState();
        _disposeWebRtc();
      }
      notifyListeners();
    }
  }

  void _startPolling() {
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(const Duration(seconds: 6), (_) => refresh());
  }

  void _ensureDurationTimer() {
    if (_durationTimer != null) return;
    _durationTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (_phase == CallPhase.connected) {
        _elapsedSeconds++;
        notifyListeners();
      }
    });
  }

  void _startQualityMonitoring() {
    if (_qualityTimer != null) return;
    _qualityTimer = Timer.periodic(const Duration(seconds: 15), (_) => _reportQuality());
  }

  Future<void> _reportQuality() async {
    final pc = _pc;
    final id = _callId;
    if (pc == null || id == null || _phase != CallPhase.connected) return;
    try {
      final reports = await pc.getStats();
      double? rttMs, jitterMs, packetLossPercent, bitrateKbps;
      String? candidateType, connectionType;
      var turnUsed = false;
      for (final report in reports) {
        final values = report.values;
        final type = report.type;
        if (type == 'candidate-pair' && values['state'] == 'succeeded') {
          final rtt = num.tryParse('${values['currentRoundTripTime']}');
          if (rtt != null) rttMs = rtt.toDouble() * 1000;
          final bitrate = num.tryParse('${values['availableOutgoingBitrate']}');
          if (bitrate != null) bitrateKbps = bitrate.toDouble() / 1000;
        } else if (type == 'remote-inbound-rtp' || type == 'inbound-rtp') {
          final jitter = num.tryParse('${values['jitter']}');
          if (jitter != null) jitterMs = jitter.toDouble() * 1000;
          final lost = num.tryParse('${values['packetsLost']}')?.toDouble();
          final received = num.tryParse('${values['packetsReceived']}')?.toDouble();
          if (lost != null && received != null && lost + received > 0) {
            packetLossPercent = (lost / (lost + received)) * 100;
          }
        } else if (type == 'local-candidate') {
          final kind = values['candidateType']?.toString();
          candidateType ??= kind;
          connectionType ??= values['networkType']?.toString();
          if (kind == 'relay') turnUsed = true;
        }
      }
      await api.post('/v1/calls/$id/quality', {
        if (rttMs != null) 'rttMs': rttMs,
        if (jitterMs != null) 'jitterMs': jitterMs,
        if (packetLossPercent != null) 'packetLossPercent': packetLossPercent.clamp(0, 100),
        if (bitrateKbps != null) 'bitrateKbps': bitrateKbps,
        if (candidateType != null) 'candidateType': candidateType,
        if (connectionType != null) 'connectionType': connectionType,
        'turnUsed': turnUsed,
        'reconnectionCount': _reconnectAttempts,
      });
    } catch (_) {}
  }

  Future<void> refresh() async {
    final id = _callId;
    if (id == null || id.isEmpty) return;
    try {
      final res = await api.getMap('/v1/calls/$id');
      final next = _parsePhase(res['call_status']?.toString());
      if (next != null) {
        _phase = next;
      }
      if (_pc != null) {
        await _consumeSignals(res['signals'] as List?).catchError((_) {});
      }
      if (isTerminal) {
        _resetMediaState();
        await _disposeWebRtc();
      }
      notifyListeners();
    } catch (_) {}
  }

  static CallPhase? _parsePhase(String? raw) {
    switch (raw?.toUpperCase()) {
      case 'INITIATED':
        return CallPhase.initiating;
      case 'RINGING':
        return CallPhase.ringing;
      case 'ACCEPTED':
        return CallPhase.accepted;
      case 'CONNECTING':
        return CallPhase.connecting;
      case 'CONNECTED':
        return CallPhase.connected;
      case 'RECONNECTING':
        return CallPhase.reconnecting;
      case 'ENDED':
        return CallPhase.ended;
      case 'REJECTED':
        return CallPhase.rejected;
      case 'CANCELLED':
        return CallPhase.cancelled;
      case 'MISSED':
        return CallPhase.missed;
      case 'FAILED':
        return CallPhase.failed;
      default:
        return null;
    }
  }

  @override
  void dispose() {
    _busSub?.cancel();
    _resetMediaState();
    _disposeWebRtc();
    super.dispose();
  }
}
