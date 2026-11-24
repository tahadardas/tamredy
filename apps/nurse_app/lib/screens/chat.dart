import 'package:flutter/material.dart';
import 'package:tamreedy_core/tamreedy_core.dart';
import '../controller.dart';

class NurseChatScreen extends StatefulWidget {
  final NurseController c;
  final String requestId;
  final String patientName;

  const NurseChatScreen({
    super.key,
    required this.c,
    required this.requestId,
    required this.patientName,
  });

  @override
  State<NurseChatScreen> createState() => _NurseChatScreenState();
}

class _NurseChatScreenState extends State<NurseChatScreen> {
  final List<AeroChatMessage> _messages = [];
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _loadMessages();
  }

  Future<void> _loadMessages() async {
    setState(() => _isLoading = true);
    try {
      final res = await widget.c.api.getMap('/v1/chat/requests/${widget.requestId}/messages');
      if (res['messages'] is List) {
        final list = (res['messages'] as List).map((m) {
          final isMe = m['sender_role'] == 'NURSE' || m['is_me'] == true;
          return AeroChatMessage(
            id: m['id']?.toString() ?? '',
            senderId: m['sender_user_id']?.toString() ?? '',
            senderName: isMe ? 'أنا (الممرض)' : widget.patientName,
            text: m['message_text']?.toString() ?? '',
            attachmentUrl: m['attachment_url']?.toString(),
            createdAt: m['created_at'] != null ? DateTime.parse(m['created_at']) : DateTime.now(),
            isMe: isMe,
            isRead: m['delivery_status'] == 'READ',
          );
        }).toList();

        setState(() {
          _messages.clear();
          _messages.addAll(list);
        });
      }
    } catch (_) {
      // Mock fallback
      if (_messages.isEmpty) {
        _messages.add(
          AeroChatMessage(
            id: 'init-1',
            senderId: 'patient',
            senderName: widget.patientName,
            text: 'مرحباً، العنوان هو الطابق الثاني على اليمين.',
            createdAt: DateTime.now().subtract(const Duration(minutes: 8)),
            isMe: false,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _handleSendMessage(String text) async {
    final tempMsg = AeroChatMessage(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      senderId: 'me',
      senderName: 'أنا',
      text: text,
      createdAt: DateTime.now(),
      isMe: true,
    );

    setState(() => _messages.insert(0, tempMsg));

    try {
      await widget.c.api.post('/v1/chat/messages', {
        'requestId': widget.requestId,
        'messageText': text,
      });
    } catch (_) {
      // Offline fallback
    }
  }

  void _handleVoiceCall() async {
    try {
      await widget.c.api.post('/v1/calls/initiate', {
        'requestId': widget.requestId,
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('جارٍ الاتصال بالمريض هاتفياً عبر النظام المشفر...')),
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('الاتصال الصوتي متاح فقط أثناء الزيارة المعتمدة')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          'محادثة المريض — ${widget.patientName}',
          style: aeroText(size: 16, weight: FontWeight.w700, color: AeroColors.primaryNavy),
        ),
        backgroundColor: Colors.white,
        elevation: 0,
        centerTitle: true,
        iconTheme: const IconThemeData(color: AeroColors.primaryNavy),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: AeroColors.accentTeal))
          : AeroChatView(
              recipientName: widget.patientName,
              recipientRole: 'المريض / المستفيد',
              messages: _messages,
              showContactAdvisory: true,
              onVoiceCallPressed: _handleVoiceCall,
              onSendMessage: _handleSendMessage,
            ),
    );
  }
}
