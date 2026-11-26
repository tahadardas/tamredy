import 'package:flutter/material.dart';
import '../../api.dart';
import '../../core/call_manager.dart';
import '../../core/realtime_bus.dart';

/// Full-screen encrypted WebRTC voice call UI backed by [CallManager].
/// Can be rendered either inside a global root overlay or pushed as a route.
class TamCallView extends StatelessWidget {
  final CallManager manager;
  final VoidCallback? onClose;

  const TamCallView({
    super.key,
    required this.manager,
    this.onClose,
  });

  String _formatDuration(int totalSeconds) {
    final m = (totalSeconds ~/ 60).toString().padLeft(2, '0');
    final s = (totalSeconds % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  String _statusLabel() {
    switch (manager.phase) {
      case CallPhase.idle:
      case CallPhase.initiating:
        return 'جارٍ بدء الاتصال المشفّر...';
      case CallPhase.ringing:
        return manager.isIncoming ? 'مكالمة صوتية واردة' : 'جارٍ الرنين...';
      case CallPhase.accepted:
      case CallPhase.connecting:
        return 'جارٍ تأسيس الاتصال الصوتي...';
      case CallPhase.connected:
        return 'متصل • ${_formatDuration(manager.elapsedSeconds)}';
      case CallPhase.reconnecting:
        return 'جارٍ استعادة الاتصال...';
      case CallPhase.rejected:
        return 'تم رفض المكالمة';
      case CallPhase.missed:
        return 'مكالمة فائتة';
      case CallPhase.ended:
      case CallPhase.cancelled:
        return 'انتهت المكالمة';
      case CallPhase.failed:
        return manager.error ?? 'تعذر إجراء المكالمة';
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: manager,
      builder: (context, _) {
        final isIncomingWaiting = manager.isIncomingWaiting;
        final isTerminal = manager.isTerminal;
        final routeIcon = switch (manager.audioRoute) {
          AudioOutputRoute.earpiece => Icons.phone_in_talk_rounded,
          AudioOutputRoute.speaker => Icons.volume_up_rounded,
          AudioOutputRoute.bluetooth => Icons.bluetooth_audio_rounded,
        };
        final routeLabel = switch (manager.audioRoute) {
          AudioOutputRoute.earpiece => 'السماعة',
          AudioOutputRoute.speaker => 'مكبر الصوت',
          AudioOutputRoute.bluetooth => 'بلوتوث',
        };

        return Directionality(
          textDirection: TextDirection.rtl,
          child: Scaffold(
            backgroundColor: const Color(0xFF0A1419),
            body: SafeArea(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
                child: Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        IconButton(
                          tooltip: 'تصغير',
                          onPressed: onClose ?? manager.dismissOverlay,
                          icon: const Icon(Icons.keyboard_arrow_down_rounded, color: Colors.white70, size: 28),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                          decoration: BoxDecoration(
                            color: const Color(0xFF005F59).withValues(alpha: 0.7),
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(color: const Color(0xFF007F78)),
                          ),
                          child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.verified_user_rounded, size: 15, color: Color(0xFFE0F5F1)),
                              SizedBox(width: 6),
                              Text(
                                'مكالمة محمية دون كشف الرقم',
                                style: TextStyle(color: Color(0xFFE0F5F1), fontSize: 12, fontWeight: FontWeight.w600),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 48),
                      ],
                    ),
                    const Spacer(),
                    Container(
                      width: 112,
                      height: 112,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: const Color(0xFF007F78).withValues(alpha: 0.2),
                        border: Border.all(color: const Color(0xFF007F78), width: 2),
                      ),
                      child: const Icon(Icons.person_rounded, size: 54, color: Color(0xFFE0F5F1)),
                    ),
                    const SizedBox(height: 20),
                    Text(
                      manager.peerName,
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.w800),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      manager.peerRole,
                      style: const TextStyle(color: Colors.white60, fontSize: 14),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      _statusLabel(),
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: isTerminal ? const Color(0xFFFCA5A5) : const Color(0xFF5EEAD4),
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    if (manager.error != null && !isTerminal) ...[
                      const SizedBox(height: 8),
                      Text(
                        manager.error!,
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: Color(0xFFFCA5A5), fontSize: 13),
                      ),
                    ],
                    const Spacer(),
                    if (!isTerminal && !isIncomingWaiting) ...[
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          _CallControlButton(
                            icon: manager.muted ? Icons.mic_off_rounded : Icons.mic_rounded,
                            label: manager.muted ? 'إلغاء الكتم' : 'كتم الصوت',
                            active: manager.muted,
                            onTap: manager.toggleMute,
                          ),
                          const SizedBox(width: 28),
                          _CallControlButton(
                            icon: routeIcon,
                            label: routeLabel,
                            active: manager.audioRoute != AudioOutputRoute.earpiece,
                            onTap: manager.cycleAudioRoute,
                          ),
                        ],
                      ),
                      const SizedBox(height: 32),
                    ],
                    if (isIncomingWaiting)
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                        children: [
                          Column(
                            children: [
                              FloatingActionButton.large(
                                heroTag: 'reject_call_global',
                                backgroundColor: const Color(0xFFDC2626),
                                onPressed: manager.acting ? null : manager.rejectIncoming,
                                child: const Icon(Icons.call_end_rounded, color: Colors.white),
                              ),
                              const SizedBox(height: 8),
                              const Text('رفض', style: TextStyle(color: Colors.white70, fontSize: 13)),
                            ],
                          ),
                          Column(
                            children: [
                              FloatingActionButton.large(
                                heroTag: 'accept_call_global',
                                backgroundColor: const Color(0xFF15803D),
                                onPressed: manager.acting ? null : manager.acceptIncoming,
                                child: const Icon(Icons.call_rounded, color: Colors.white),
                              ),
                              const SizedBox(height: 8),
                              const Text('رد', style: TextStyle(color: Colors.white70, fontSize: 13)),
                            ],
                          ),
                        ],
                      )
                    else if (isTerminal)
                      SizedBox(
                        width: double.infinity,
                        height: 54,
                        child: FilledButton(
                          onPressed: onClose ?? manager.dismissOverlay,
                          style: FilledButton.styleFrom(
                            backgroundColor: const Color(0xFF163B45),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                          ),
                          child: const Text('إغلاق', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                        ),
                      )
                    else
                      FloatingActionButton.large(
                        heroTag: 'end_call_global',
                        backgroundColor: const Color(0xFFDC2626),
                        onPressed: manager.acting ? null : manager.endCall,
                        child: const Icon(Icons.call_end_rounded, color: Colors.white),
                      ),
                    const SizedBox(height: 20),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

/// Global overlay wrapper that shows [TamCallView] above ANY screen in the app
/// whenever a call is active or incoming, or a floating mini-pill when minimized.
class TamGlobalCallOverlay extends StatelessWidget {
  final CallManager manager;
  final Widget child;

  const TamGlobalCallOverlay({
    super.key,
    required this.manager,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: manager,
      builder: (context, _) {
        return Stack(
          children: [
            child,
            if (manager.isActive && !manager.overlayVisible)
              PositionedDirectional(
                top: MediaQuery.paddingOf(context).top + 8,
                start: 16,
                end: 16,
                child: Material(
                  color: const Color(0xFF15803D),
                  borderRadius: BorderRadius.circular(14),
                  elevation: 6,
                  child: InkWell(
                    borderRadius: BorderRadius.circular(14),
                    onTap: manager.showOverlay,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                      child: Row(
                        children: [
                          const Icon(Icons.call_rounded, color: Colors.white, size: 20),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'مكالمة جارية مع ${manager.peerName} • اضغط للعودة',
                              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 13),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            if (manager.overlayVisible && manager.phase != CallPhase.idle)
              Positioned.fill(
                child: TamCallView(manager: manager),
              ),
          ],
        );
      },
    );
  }
}

/// Backward-compatible standalone route wrapper around [CallManager] + [TamCallView].
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
  late final RealtimeEventBus _bus = RealtimeEventBus();
  late final CallManager _manager = CallManager(api: widget.api, eventBus: _bus);

  @override
  void initState() {
    super.initState();
    if (widget.incomingCallId != null && widget.incomingCallId!.isNotEmpty) {
      _manager.presentIncoming(
        callId: widget.incomingCallId!,
        requestId: widget.requestId,
        peerName: widget.peerName,
        peerRole: widget.peerRole,
      );
    } else {
      _manager.startOutgoing(
        requestId: widget.requestId,
        peerName: widget.peerName,
        peerRole: widget.peerRole,
      );
    }
  }

  @override
  void dispose() {
    _manager.dispose();
    _bus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return TamCallView(
      manager: _manager,
      onClose: () => Navigator.of(context).maybePop(),
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
              color: active ? const Color(0xFF0A1419) : Colors.white,
              size: 26,
            ),
          ),
        ),
        const SizedBox(height: 8),
        Text(label, style: const TextStyle(color: Colors.white70, fontSize: 12)),
      ],
    );
  }
}
