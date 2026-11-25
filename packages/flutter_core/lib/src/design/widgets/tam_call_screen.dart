import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:uuid/uuid.dart';
import '../../api.dart';
import '../../errors.dart';
import '../../realtime.dart';

/// Masked in-app WebRTC voice call screen backed by `/v1/calls/*` so patient
/// and nurse communicate with clear Opus audio without ever exposing phone numbers.
class TamInAppCallScreen extends StatefulWidget {
  final TamreedyApi api;
  final String requestId;
  final String peerName;
  final String peerRole;
  final String? incomingCallId;

  const TamInAppCallScreen({
    super.key,
    required this.api,
    required this.requestId,
    required this.peerName,
    required this.peerRole,
    this.incomingCallId,
  });

  @override
  State<TamInAppCallScreen> createState() => _TamInAppCallScreenState();
}

class _TamInAppCallScreenState extends State<TamInAppCallScreen> {
  String? _callId;
  String _status = 'INITIATING';
  String? _error;
  bool _muted = false;
  bool _speaker = false;
  bool _acting = false;
  int _elapsedSeconds = 0;
  Timer? _pollTimer;
  Timer? _durationTimer;
  Timer? _reconnectTimer;
  Timer? _qualityTimer;
  LiveChannel? _live;
  int _signalSequence = 0;
  bool _connectedReported = false;
  int _reconnectAttempts = 0;
  static const _uuid = Uuid();

  RTCPeerConnection? _pc;
  MediaStream? _localStream;
  final Set<String> _handledSignals = <String>{};
  bool _remoteDescriptionSet = false;
  final List<RTCIceCandidate> _pendingCandidates = <RTCIceCandidate>[];
  bool _offerSent = false;
  bool _answerSent = false;

  @override
  void initState() {
    super.initState();
    _live = LiveChannel(
      api: widget.api,
      onResync: _refresh,
      onEvent: (_) {},
      onEventData: _onLiveEvent,
    )..start();
    if (widget.incomingCallId != null && widget.incomingCallId!.isNotEmpty) {
      _callId = widget.incomingCallId;
      _status = 'RINGING';
      _startPolling();
    } else {
      _initiate();
    }
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    _durationTimer?.cancel();
    _reconnectTimer?.cancel();
    _qualityTimer?.cancel();
    _live?.dispose();
    _disposeWebRtc();
    super.dispose();
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
      if (!mounted) return;
      if (state == RTCPeerConnectionState.RTCPeerConnectionStateConnected) {
        _reconnectTimer?.cancel();
        _reconnectTimer = null;
        _reconnectAttempts = 0;
        setState(() => _status = 'CONNECTED');
        _ensureDurationTimer();
        _startQualityMonitoring();
        if (!_connectedReported && _callId != null) {
          _connectedReported = true;
          widget.api.post('/v1/calls/${_callId!}/connected', {}).catchError((_) => <String, dynamic>{});
        }
      } else if (state == RTCPeerConnectionState.RTCPeerConnectionStateDisconnected ||
          state == RTCPeerConnectionState.RTCPeerConnectionStateFailed) {
        setState(() => _status = 'RECONNECTING');
        if (widget.incomingCallId == null) _scheduleIceRestart();
      }
    };

    _pc = pc;
    _localStream = stream;
    try {
      await Helper.setSpeakerphoneOn(_speaker);
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
      final sigId = sig['id']?.toString() ?? '';
      if (sigId.isNotEmpty && !_handledSignals.add(sigId)) continue;
      final type = sig['event_type']?.toString();
      final data = sig['event_data'] is Map
          ? Map<String, dynamic>.from(sig['event_data'] as Map)
          : <String, dynamic>{};

      if ((type == 'SDP_OFFER' || type == 'ICE_RESTART') && widget.incomingCallId != null) {
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
      } else if (type == 'SDP_ANSWER' && widget.incomingCallId == null) {
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

  Future<Map<String, dynamic>> _sendSignal(String eventType, Map<String, dynamic> data) {
    final id = _callId;
    if (id == null) return Future.value(<String, dynamic>{});
    _signalSequence++;
    return widget.api.post('/v1/calls/$id/signal', {
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
      if (pc == null || _status == 'CONNECTED') return;
      _reconnectAttempts++;
      try {
        final offer = await pc.createOffer({'iceRestart': true, 'offerToReceiveAudio': true});
        await pc.setLocalDescription(offer);
        await _sendSignal('ICE_RESTART', {'sdp': offer.sdp, 'type': offer.type});
      } catch (_) {}
      if (_status != 'CONNECTED') {
        if (_reconnectAttempts >= 3) {
          setState(() => _status = 'FAILED');
          final id = _callId;
          if (id != null) {
            widget.api.post('/v1/calls/$id/end', {'reason': 'ICE_RESTART_EXHAUSTED'}).catchError((_) => <String, dynamic>{});
          }
        } else {
          _scheduleIceRestart();
        }
      }
    });
  }

  void _onLiveEvent(String type, Map<String, dynamic> payload) {
    if (payload['callId']?.toString() != _callId || !mounted) return;
    if (type == 'call.signal') {
      final eventType = payload['eventType']?.toString();
      final data = payload['data'];
      if (eventType != null && data is Map) {
        _consumeSignals([{
          'id': payload['eventId'],
          'event_type': eventType,
          'event_data': Map<String, dynamic>.from(data),
        }]).catchError((_) {});
      }
      return;
    }
    final next = switch (type) {
      'call.accepted' => 'ACCEPTED',
      'call.connected' => 'CONNECTED',
      'call.reconnecting' => 'RECONNECTING',
      'call.rejected' => 'REJECTED',
      'call.cancel' => 'CANCELLED',
      'call.ended' => 'ENDED',
      'call.missed' => 'MISSED',
      'call.failed' => 'FAILED',
      _ => null,
    };
    if (next != null) {
      setState(() => _status = next);
      if (next == 'CONNECTED') _ensureDurationTimer();
      if (const {'ENDED', 'REJECTED', 'CANCELLED', 'MISSED', 'FAILED'}.contains(next)) {
        _pollTimer?.cancel();
        _durationTimer?.cancel();
        _disposeWebRtc();
      }
    }
  }

  Future<void> _flushPendingCandidates() async {
    for (final c in _pendingCandidates) {
      await _pc?.addCandidate(c);
    }
    _pendingCandidates.clear();
  }

  Future<void> _initiate() async {
    try {
      final res = await widget.api.post('/v1/calls/initiate', {
        'requestId': widget.requestId,
      });
      if (!mounted) return;
      setState(() {
        _callId = res['id']?.toString();
        _status = res['call_status']?.toString() ?? 'INITIATED';
      });
      try {
        await _initPeerConnection(res['ice_servers'] as List?);
        await _sendOfferIfCaller();
      } catch (_) {}
      _startPolling();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _status = 'FAILED';
        _error = explainError(
          e,
          fallback: 'الاتصال الصوتي متاح فقط أثناء الزيارة النشطة',
        );
      });
    }
  }

  void _startPolling() {
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(const Duration(seconds: 10), (_) => _refresh());
  }

  void _ensureDurationTimer() {
    if (_durationTimer != null) return;
    _durationTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() => _elapsedSeconds++);
    });
  }

  void _startQualityMonitoring() {
    if (_qualityTimer != null) return;
    _qualityTimer = Timer.periodic(const Duration(seconds: 15), (_) => _reportQuality());
  }

  Future<void> _reportQuality() async {
    final pc = _pc;
    final callId = _callId;
    if (pc == null || callId == null || _status != 'CONNECTED') return;
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
      await widget.api.post('/v1/calls/$callId/quality', {
        if (rttMs != null) 'rttMs': rttMs,
        if (jitterMs != null) 'jitterMs': jitterMs,
        if (packetLossPercent != null) 'packetLossPercent': packetLossPercent.clamp(0, 100),
        if (bitrateKbps != null) 'bitrateKbps': bitrateKbps,
        if (candidateType != null) 'candidateType': candidateType,
        if (connectionType != null) 'connectionType': connectionType,
        'turnUsed': turnUsed,
        'reconnectionCount': _reconnectAttempts,
      });
    } catch (_) {
      // Quality telemetry must never interrupt media.
    }
  }

  Future<void> _refresh() async {
    final id = _callId;
    if (id == null || id.isEmpty) return;
    try {
      final res = await widget.api.getMap('/v1/calls/$id');
      if (!mounted) return;
      final next = res['call_status']?.toString() ?? _status;
      setState(() => _status = next);
      if (next == 'CONNECTED') {
        _ensureDurationTimer();
      }
      if (_pc != null) {
        try {
          await _consumeSignals(res['signals'] as List?);
        } catch (_) {}
      }
      if (const {'ENDED', 'REJECTED', 'CANCELLED', 'MISSED', 'FAILED'}.contains(next)) {
        _pollTimer?.cancel();
        _durationTimer?.cancel();
        await _disposeWebRtc();
      }
    } catch (_) {}
  }

  Future<void> _accept() async {
    final id = _callId;
    if (id == null || _acting) return;
    setState(() => _acting = true);
    try {
      final res = await widget.api.post('/v1/calls/$id/accept', {});
      if (!mounted) return;
      setState(() => _status = res['call_status']?.toString() ?? 'ACCEPTED');
      try {
        await _initPeerConnection(res['ice_servers'] as List?);
        await _refresh();
      } catch (_) {}
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(explainError(e))),
        );
      }
    } finally {
      if (mounted) setState(() => _acting = false);
    }
  }

  Future<void> _reject() async {
    final id = _callId;
    if (id == null || _acting) return;
    setState(() => _acting = true);
    try {
      await widget.api.post('/v1/calls/$id/reject', {'reason': 'DECLINED'});
    } catch (_) {}
    await _disposeWebRtc();
    if (mounted) Navigator.of(context).maybePop();
  }

  Future<void> _end() async {
    final id = _callId;
    if (id != null && !_acting) {
      setState(() => _acting = true);
      try {
        await widget.api.post('/v1/calls/$id/end', {'reason': 'HANGUP'});
      } catch (_) {}
    }
    await _disposeWebRtc();
    if (mounted) Navigator.of(context).maybePop();
  }

  void _toggleMute() {
    final next = !_muted;
    setState(() => _muted = next);
    for (final track in _localStream?.getAudioTracks() ?? const <MediaStreamTrack>[]) {
      track.enabled = !next;
    }
  }

  Future<void> _toggleSpeaker() async {
    final next = !_speaker;
    setState(() => _speaker = next);
    try {
      await Helper.setSpeakerphoneOn(next);
    } catch (_) {}
  }

  String _formatDuration(int totalSeconds) {
    final m = (totalSeconds ~/ 60).toString().padLeft(2, '0');
    final s = (totalSeconds % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  String _statusLabel() {
    switch (_status) {
      case 'INITIATING':
      case 'INITIATED':
        return 'جارٍ بدء الاتصال المشفّر...';
      case 'RINGING':
        return widget.incomingCallId != null
            ? 'مكالمة صوتية واردة'
            : 'جارٍ الرنين...';
      case 'ACCEPTED':
      case 'CONNECTING':
        return 'جارٍ تأسيس الاتصال الصوتي...';
      case 'CONNECTED':
        return 'متصل • ${_formatDuration(_elapsedSeconds)}';
      case 'RECONNECTING':
        return 'جارٍ استعادة الاتصال...';
      case 'REJECTED':
        return 'تم رفض المكالمة';
      case 'ENDED':
      case 'CANCELLED':
        return 'انتهت المكالمة';
      case 'FAILED':
        return _error ?? 'تعذر إجراء المكالمة';
      default:
        return _status;
    }
  }

  @override
  Widget build(BuildContext context) {
    final isIncomingWaiting =
        widget.incomingCallId != null &&
        (_status == 'RINGING' || _status == 'INITIATED');
    final isTerminal = const {'ENDED', 'REJECTED', 'CANCELLED', 'MISSED', 'FAILED'}.contains(_status);

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: const Color(0xFF0B1220),
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    IconButton(
                      onPressed: () => Navigator.of(context).maybePop(),
                      icon: const Icon(
                        Icons.arrow_back_rounded,
                        color: Colors.white70,
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFF134E4A).withValues(alpha: 0.7),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: const Color(0xFF0D9488).withValues(alpha: 0.5),
                        ),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.verified_user_rounded,
                            size: 15,
                            color: Color(0xFF5EEAD4),
                          ),
                          SizedBox(width: 6),
                          Text(
                            'رقم الهاتف محمي داخل التطبيق',
                            style: TextStyle(
                              color: Color(0xFFCCFBF1),
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 48),
                  ],
                ),
                const Spacer(),
                Container(
                  width: 108,
                  height: 108,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: const Color(0xFF0D9488).withValues(alpha: 0.18),
                    border: Border.all(
                      color: const Color(0xFF0D9488).withValues(alpha: 0.55),
                      width: 2,
                    ),
                  ),
                  child: const Icon(
                    Icons.person_rounded,
                    size: 54,
                    color: Color(0xFF5EEAD4),
                  ),
                ),
                const SizedBox(height: 20),
                Text(
                  widget.peerName,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  widget.peerRole,
                  style: const TextStyle(color: Colors.white60, fontSize: 14),
                ),
                const SizedBox(height: 16),
                Text(
                  _statusLabel(),
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: isTerminal
                        ? const Color(0xFFFCA5A5)
                        : const Color(0xFF5EEAD4),
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const Spacer(),
                if (!isTerminal && !isIncomingWaiting) ...[
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      _CallControlButton(
                        icon: _muted ? Icons.mic_off_rounded : Icons.mic_rounded,
                        label: _muted ? 'إلغاء الكتم' : 'كتم الصوت',
                        active: _muted,
                        onTap: _toggleMute,
                      ),
                      const SizedBox(width: 28),
                      _CallControlButton(
                        icon: _speaker
                            ? Icons.volume_up_rounded
                            : Icons.volume_down_rounded,
                        label: 'مكبر الصوت',
                        active: _speaker,
                        onTap: _toggleSpeaker,
                      ),
                    ],
                  ),
                  const SizedBox(height: 32),
                ],
                if (isIncomingWaiting)
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      FloatingActionButton.large(
                        heroTag: 'reject_call',
                        backgroundColor: const Color(0xFFDC2626),
                        onPressed: _acting ? null : _reject,
                        child: const Icon(
                          Icons.call_end_rounded,
                          color: Colors.white,
                        ),
                      ),
                      FloatingActionButton.large(
                        heroTag: 'accept_call',
                        backgroundColor: const Color(0xFF16A34A),
                        onPressed: _acting ? null : _accept,
                        child: const Icon(
                          Icons.call_rounded,
                          color: Colors.white,
                        ),
                      ),
                    ],
                  )
                else if (isTerminal)
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: () => Navigator.of(context).maybePop(),
                      style: FilledButton.styleFrom(
                        backgroundColor: const Color(0xFF1E293B),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                      child: const Text('إغلاق'),
                    ),
                  )
                else
                  FloatingActionButton.large(
                    heroTag: 'end_call',
                    backgroundColor: const Color(0xFFDC2626),
                    onPressed: _acting ? null : _end,
                    child: const Icon(
                      Icons.call_end_rounded,
                      color: Colors.white,
                    ),
                  ),
                const SizedBox(height: 20),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _CallControlButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool active;
  final VoidCallback onTap;

  const _CallControlButton({
    required this.icon,
    required this.label,
    required this.active,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(32),
          child: Container(
            width: 58,
            height: 58,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: active ? Colors.white : Colors.white12,
            ),
            child: Icon(
              icon,
              color: active ? const Color(0xFF0B1220) : Colors.white,
              size: 26,
            ),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          label,
          style: const TextStyle(color: Colors.white70, fontSize: 12),
        ),
      ],
    );
  }
}
