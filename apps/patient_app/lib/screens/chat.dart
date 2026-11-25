import 'dart:async';
import 'package:flutter/material.dart';
import 'package:tamreedy_core/tamreedy_core.dart';
import '../controller.dart';

class PatientChatScreen extends StatefulWidget {
  final PatientController c;
  final String requestId;
  final String nurseName;

  const PatientChatScreen({
    super.key,
    required this.c,
    required this.requestId,
    required this.nurseName,
  });

  @override
  State<PatientChatScreen> createState() => _PatientChatScreenState();
}

class _PatientChatScreenState extends State<PatientChatScreen> {
  final List<AeroChatMessage> _messages = [];
  bool _isLoading = false;
  Timer? _pollTimer;

  @override
  void initState() {
    super.initState();
    _loadMessages(showSpinner: true);
    _pollTimer = Timer.periodic(
      const Duration(seconds: 4),
      (_) => _loadMessages(showSpinner: false),
    );
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    super.dispose();
  }

  Future<void> _loadMessages({bool showSpinner = false}) async {
    if (showSpinner) setState(() => _isLoading = true);
    try {
      final raw = await widget.c.api.getList(
        '/v1/chat/requests/${widget.requestId}/messages',
      );
      final list = raw.map((item) {
        final m = Map<String, dynamic>.from(item as Map);
        final isMe = m['sender_role'] == 'PATIENT' || m['is_me'] == true;
        return AeroChatMessage(
          id: m['id']?.toString() ?? '',
          senderId: m['sender_user_id']?.toString() ?? '',
          senderName: isMe ? 'أنا' : widget.nurseName,
          text: m['content']?.toString() ?? m['message_text']?.toString() ?? '',
          attachmentUrl: m['attachment_url']?.toString(),
          createdAt: m['created_at'] != null
              ? DateTime.parse(m['created_at'].toString())
              : DateTime.now(),
          isMe: isMe,
          isRead: m['status'] == 'READ' || m['delivery_status'] == 'READ',
        );
      }).toList();

      if (mounted) {
        setState(() {
          _messages
            ..clear()
            ..addAll(list.reversed);
        });
      }
    } catch (e) {
      if (showSpinner && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(explainError(e, fallback: 'تعذر تحميل رسائل المحادثة'))),
        );
      }
    } finally {
      if (showSpinner && mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _handleSendMessage(String text) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return;
    final clientMsgId = 'p_${DateTime.now().microsecondsSinceEpoch}';
    final tempMsg = AeroChatMessage(
      id: clientMsgId,
      senderId: 'me',
      senderName: 'أنا',
      text: trimmed,
      createdAt: DateTime.now(),
      isMe: true,
    );

    setState(() => _messages.insert(0, tempMsg));

    try {
      final res = await widget.c.api.post('/v1/chat/messages', {
        'requestId': widget.requestId,
        'content': trimmed,
        'clientMessageId': clientMsgId,
      });
      final advisory = (res['advisoryMessage'] ?? res['advisory'])?.toString();
      if (advisory != null && advisory.isNotEmpty && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(advisory)),
        );
      }
      await _loadMessages();
    } catch (e) {
      if (mounted) {
        setState(() => _messages.removeWhere((m) => m.id == clientMsgId));
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(explainError(e, fallback: 'تعذر إرسال الرسالة'))),
        );
      }
    }
  }

  void _handleVoiceCall() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => TamInAppCallScreen(
          api: widget.c.api,
          requestId: widget.requestId,
          peerName: widget.nurseName,
          peerRole: 'ممرض مرخص معتمد',
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final tc = context.tamColors;
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: tc.background,
        appBar: AppBar(
          title: Text(
            'محادثة الزيارة — ${widget.nurseName}',
            style: aeroText(size: 16, weight: FontWeight.w700, color: tc.textPrimary),
          ),
          backgroundColor: tc.surface,
          elevation: 0,
          centerTitle: true,
          leading: IconButton(
            tooltip: 'رجوع',
            icon: Icon(Icons.arrow_back_rounded, color: tc.textPrimary),
            onPressed: () => Navigator.of(context).maybePop(),
          ),
        ),
        body: _isLoading
            ? const Center(child: CircularProgressIndicator(color: AeroColors.accentTeal))
            : AeroChatView(
                recipientName: widget.nurseName,
                recipientRole: 'ممرض مرخص معتمد • محادثة آمنة داخل التطبيق',
                messages: _messages,
                onSendMessage: _handleSendMessage,
                onVoiceCallPressed: _handleVoiceCall,
              ),
      ),
    );
  }
}
