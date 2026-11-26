import 'dart:async';
import 'package:flutter/material.dart';
import 'package:tamreedy_core/tamreedy_core.dart';
import '../../core/patient_session_coordinator.dart';

class VisitChatScreen extends StatefulWidget {
  final PatientSessionCoordinator session;
  final String requestId;
  final String? conversationId;
  final String peerName;

  const VisitChatScreen({
    super.key,
    required this.session,
    required this.requestId,
    this.conversationId,
    required this.peerName,
  });

  @override
  State<VisitChatScreen> createState() => _VisitChatScreenState();
}

class _VisitChatScreenState extends State<VisitChatScreen> {
  final List<AeroChatMessage> _messages = [];
  bool _loading = true;
  String? _convId;
  StreamSubscription<RealtimeEvent>? _chatSub;
  Timer? _degradedPoll;

  @override
  void initState() {
    super.initState();
    _convId = widget.conversationId;
    _loadMessages(showSpinner: true);
    _chatSub = widget.session.eventBus
        .whereType(const {'chat.message', 'chat.read'})
        .listen((ev) {
      final evReqId = ev.payload['requestId']?.toString() ?? ev.payload['request_id']?.toString();
      if (evReqId == null || evReqId == widget.requestId) {
        _loadMessages();
      }
    });
    _degradedPoll = Timer.periodic(const Duration(seconds: 12), (_) {
      if (widget.session.api.connectionHealth.value != ConnectionHealth.online) {
        _loadMessages();
      }
    });
  }

  @override
  void dispose() {
    _chatSub?.cancel();
    _degradedPoll?.cancel();
    super.dispose();
  }

  Future<void> _loadMessages({bool showSpinner = false}) async {
    if (kDemoMode) {
      if (mounted) setState(() => _loading = false);
      return;
    }
    if (showSpinner && mounted) setState(() => _loading = true);
    try {
      final raw = await widget.session.api.getList(
        '/v1/chat/requests/${widget.requestId}/messages',
      );
      final parsed = <AeroChatMessage>[];
      String? newestOtherId;
      for (final item in raw) {
        if (item is! Map) continue;
        final m = Map<String, dynamic>.from(item);
        _convId ??= m['conversation_id']?.toString();
        final isMe = m['sender_role'] == 'PATIENT' || m['is_me'] == true;
        final id = m['id']?.toString() ?? '';
        if (!isMe && id.isNotEmpty) newestOtherId = id;
        parsed.add(
          AeroChatMessage(
            id: id,
            senderId: m['sender_user_id']?.toString() ?? '',
            senderName: isMe ? 'أنا' : widget.peerName,
            text: m['content']?.toString() ?? m['message_text']?.toString() ?? '',
            attachmentUrl: m['attachment_url']?.toString(),
            attachmentType: m['message_type']?.toString(),
            createdAt: DateTime.tryParse('${m['created_at'] ?? ''}')?.toLocal() ?? DateTime.now(),
            isMe: isMe,
            isRead: m['status'] == 'READ' || m['delivery_status'] == 'READ',
          ),
        );
      }
      if (newestOtherId != null && _convId != null && _convId!.isNotEmpty) {
        widget.session.api.post('/v1/conversations/$_convId/read', {
          'messageId': newestOtherId,
        }).catchError((_) => <String, dynamic>{});
      }
      if (mounted) {
        final failedLocal = _messages.where((m) => m.isFailed).toList();
        setState(() {
          _messages
            ..clear()
            ..addAll(failedLocal)
            ..addAll(parsed.reversed);
        });
      }
    } catch (e) {
      if (showSpinner && mounted) {
        TamToast.show(context, explainError(e, fallback: 'تعذر تحميل المحادثة'), tone: TamToastTone.error);
      }
    } finally {
      if (showSpinner && mounted) setState(() => _loading = false);
    }
  }

  Future<void> _sendMessage(String text, {String? retryId}) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return;
    final clientMsgId = retryId ?? 'p_${widget.session.api.newIdempotencyKey()}';
    final pendingMsg = AeroChatMessage(
      id: clientMsgId,
      senderId: 'me',
      senderName: 'أنا',
      text: trimmed,
      createdAt: DateTime.now(),
      isMe: true,
      isPending: true,
    );

    setState(() {
      _messages.removeWhere((m) => m.id == clientMsgId);
      _messages.insert(0, pendingMsg);
    });

    if (kDemoMode) {
      setState(() {
        _messages[0] = AeroChatMessage(
          id: clientMsgId,
          senderId: 'me',
          senderName: 'أنا',
          text: trimmed,
          createdAt: DateTime.now(),
          isMe: true,
          isRead: true,
        );
      });
      return;
    }

    try {
      final res = await widget.session.api.post('/v1/chat/messages', {
        'requestId': widget.requestId,
        if (_convId != null) 'conversationId': _convId,
        'content': trimmed,
        'clientMessageId': clientMsgId,
      });
      final advisory = (res['advisoryMessage'] ?? res['advisory'])?.toString();
      if (advisory != null && advisory.isNotEmpty && mounted) {
        TamToast.show(context, advisory, tone: TamToastTone.info);
      }
      await _loadMessages();
    } catch (e) {
      if (!mounted) return;
      final idx = _messages.indexWhere((m) => m.id == clientMsgId);
      if (idx >= 0) {
        setState(() {
          _messages[idx] = AeroChatMessage(
            id: clientMsgId,
            senderId: 'me',
            senderName: 'أنا',
            text: trimmed,
            createdAt: pendingMsg.createdAt,
            isMe: true,
            isFailed: true,
          );
        });
      }
      TamToast.show(context, explainError(e, fallback: 'تعذر إرسال الرسالة'), tone: TamToastTone.error);
    }
  }

  @override
  Widget build(BuildContext context) {
    final tc = context.tamColors;
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: tc.background,
        appBar: AppBar(
          backgroundColor: tc.surface,
          elevation: 0,
          centerTitle: true,
          title: Text(
            'محادثة — ${widget.peerName}',
            style: aeroText(size: 15.5, weight: FontWeight.w800, color: tc.textPrimary),
          ),
        ),
        body: _loading
            ? const Center(child: CircularProgressIndicator())
            : AeroChatView(
                recipientName: widget.peerName,
                recipientRole: 'ممرض مرخص معتمد • محادثة آمنة داخل التطبيق',
                messages: _messages,
                onSendMessage: _sendMessage,
                onRetryMessage: (msg) => _sendMessage(msg.text, retryId: msg.id),
                onVoiceCallPressed: () => widget.session.callManager.startOutgoing(
                  requestId: widget.requestId,
                  peerName: widget.peerName,
                  peerRole: 'ممرض مرخص معتمد',
                ),
              ),
      ),
    );
  }
}
