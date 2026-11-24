import 'package:flutter/material.dart';
import '../tokens/aero_colors.dart';
import '../tokens/aero_radii.dart';
import '../tokens/aero_typography.dart';
import 'aero_glass_card.dart';

class AeroChatMessage {
  final String id;
  final String senderId;
  final String senderName;
  final String text;
  final String? attachmentUrl;
  final String? attachmentType;
  final DateTime createdAt;
  final bool isMe;
  final bool isRead;

  const AeroChatMessage({
    required this.id,
    required this.senderId,
    required this.senderName,
    required this.text,
    this.attachmentUrl,
    this.attachmentType,
    required this.createdAt,
    required this.isMe,
    this.isRead = false,
  });
}

/// AeroChatView — Real-time in-app chat component supporting Medical Aero aesthetics,
/// contact masking warnings, voice call shortcuts, and attachment previews.
class AeroChatView extends StatefulWidget {
  final String recipientName;
  final String? recipientRole;
  final List<AeroChatMessage> messages;
  final bool showContactAdvisory;
  final VoidCallback? onVoiceCallPressed;
  final ValueChanged<String> onSendMessage;
  final VoidCallback? onPickAttachment;
  final bool isSending;

  const AeroChatView({
    super.key,
    required this.recipientName,
    this.recipientRole,
    required this.messages,
    this.showContactAdvisory = true,
    this.onVoiceCallPressed,
    required this.onSendMessage,
    this.onPickAttachment,
    this.isSending = false,
  });

  @override
  State<AeroChatView> createState() => _AeroChatViewState();
}

class _AeroChatViewState extends State<AeroChatView> {
  final TextEditingController _textController = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  @override
  void dispose() {
    _textController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _handleSend() {
    final text = _textController.text.trim();
    if (text.isEmpty) return;
    widget.onSendMessage(text);
    _textController.clear();
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Column(
        children: [
          // Header / Recipient Bar
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: AeroColors.surfaceWhite,
              border: Border(
                bottom: BorderSide(color: AeroColors.borderLight),
              ),
            ),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 20,
                  backgroundColor: AeroColors.aeroTint,
                  child: Text(
                    widget.recipientName.isNotEmpty ? widget.recipientName[0] : '?',
                    style: aeroText(size: 16, weight: FontWeight.w700, color: AeroColors.primaryNavy),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.recipientName,
                        style: aeroText(size: 16, weight: FontWeight.w700),
                      ),
                      if (widget.recipientRole != null)
                        Text(
                          widget.recipientRole!,
                          style: aeroText(size: 12, color: AeroColors.textSecondary),
                        ),
                    ],
                  ),
                ),
                if (widget.onVoiceCallPressed != null)
                  IconButton(
                    icon: const Icon(Icons.call, color: AeroColors.accentTeal),
                    tooltip: 'اتصال صوتي تمريضي',
                    onPressed: widget.onVoiceCallPressed,
                  ),
              ],
            ),
          ),

          // Contact Advisory Warning Banner
          if (widget.showContactAdvisory)
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: const Color(0xFFFEF3C7),
                borderRadius: BorderRadius.circular(AeroRadii.badge),
                border: Border.all(color: const Color(0xFFF59E0B).withValues(alpha: 0.4)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.security, size: 18, color: Color(0xFFB45309)),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'نوصي بالتواصل ضمن التطبيق لحماية الخصوصية وضمان توثيق الملاحظات الطبية ضمن سجل الزيارة المعتمد.',
                      style: aeroText(size: 11, color: const Color(0xFF92400E), height: 1.3),
                    ),
                  ),
                ],
              ),
            ),

          // Messages List
          Expanded(
            child: ListView.builder(
              controller: _scrollController,
              padding: const EdgeInsets.all(16),
              reverse: true,
              itemCount: widget.messages.length,
              itemBuilder: (context, index) {
                final msg = widget.messages[index];
                return _buildMessageBubble(msg);
              },
            ),
          ),

          // Input Bar
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AeroColors.surfaceWhite,
              border: Border(top: BorderSide(color: AeroColors.borderLight)),
            ),
            child: SafeArea(
              child: Row(
                children: [
                  if (widget.onPickAttachment != null)
                    IconButton(
                      icon: const Icon(Icons.attach_file, color: AeroColors.textSecondary),
                      onPressed: widget.onPickAttachment,
                      tooltip: 'إرفاق وصفة أو تقرير',
                    ),
                  Expanded(
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      decoration: BoxDecoration(
                        color: AeroColors.lightCanvas,
                        borderRadius: BorderRadius.circular(24),
                        border: Border.all(color: AeroColors.borderSubtle),
                      ),
                      child: TextField(
                        controller: _textController,
                        style: aeroText(size: 14),
                        decoration: InputDecoration(
                          hintText: 'اكتب رسالتك هنا...',
                          hintStyle: aeroText(size: 14, color: AeroColors.textMuted),
                          border: InputBorder.none,
                          isDense: true,
                          contentPadding: const EdgeInsets.symmetric(vertical: 12),
                        ),
                        onSubmitted: (_) => _handleSend(),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  CircleAvatar(
                    backgroundColor: AeroColors.accentTeal,
                    radius: 22,
                    child: widget.isSending
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                          )
                        : IconButton(
                            icon: const Icon(Icons.send, color: Colors.white, size: 20),
                            onPressed: _handleSend,
                          ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMessageBubble(AeroChatMessage msg) {
    final isMe = msg.isMe;
    return Align(
      alignment: isMe ? Alignment.centerLeft : Alignment.centerRight,
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.78),
        child: AeroGlassCard(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          borderRadius: 16,
          tintColor: isMe ? AeroColors.aeroTint : Colors.white,
          child: Column(
            crossAxisAlignment: isMe ? CrossAxisAlignment.start : CrossAxisAlignment.end,
            children: [
              if (msg.attachmentUrl != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: Container(
                      height: 120,
                      color: AeroColors.borderLight,
                      child: const Center(
                        child: Icon(Icons.insert_drive_file, color: AeroColors.accentTeal, size: 36),
                      ),
                    ),
                  ),
                ),
              Text(
                msg.text,
                style: aeroText(
                  size: 14,
                  color: isMe ? AeroColors.primaryNavy : AeroColors.textPrimary,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 4),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    '${msg.createdAt.hour.toString().padLeft(2, '0')}:${msg.createdAt.minute.toString().padLeft(2, '0')}',
                    style: aeroText(size: 10, color: AeroColors.textMuted),
                  ),
                  if (isMe) ...[
                    const SizedBox(width: 4),
                    Icon(
                      msg.isRead ? Icons.done_all : Icons.done,
                      size: 14,
                      color: msg.isRead ? AeroColors.accentTeal : AeroColors.textMuted,
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
