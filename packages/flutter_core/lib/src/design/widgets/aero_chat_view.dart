import 'package:flutter/material.dart';
import '../tokens/aero_radii.dart';
import '../tokens/aero_typography.dart';
import '../tokens/tam_tokens.dart';

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
  final bool isPending;
  final bool isFailed;
  final bool isSystem;

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
    this.isPending = false,
    this.isFailed = false,
    this.isSystem = false,
  });
}

/// Tamreedy 3.0 in-app chat view with send state, retry on failure,
/// contact masking advisory, attachment upload, and voice call trigger.
class AeroChatView extends StatefulWidget {
  final String recipientName;
  final String? recipientRole;
  final List<AeroChatMessage> messages;
  final bool showContactAdvisory;
  final VoidCallback? onVoiceCallPressed;
  final ValueChanged<String> onSendMessage;
  final ValueChanged<AeroChatMessage>? onRetryMessage;
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
    this.onRetryMessage,
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
    final tc = context.tamColors;
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: tc.surface,
              border: Border(bottom: BorderSide(color: tc.border)),
            ),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 20,
                  backgroundColor: tc.primaryTint,
                  child: Text(
                    widget.recipientName.isNotEmpty ? widget.recipientName[0] : '؟',
                    style: aeroText(size: 16, weight: FontWeight.w800, color: tc.primaryDark),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.recipientName,
                        style: aeroText(size: 16, weight: FontWeight.w700, color: tc.textPrimary),
                      ),
                      if (widget.recipientRole != null)
                        Text(
                          widget.recipientRole!,
                          style: aeroText(size: 12, color: tc.textSecondary),
                        ),
                    ],
                  ),
                ),
                if (widget.onVoiceCallPressed != null)
                  IconButton(
                    icon: Icon(Icons.call_rounded, color: tc.primary),
                    tooltip: 'مكالمة صوتية آمنة',
                    onPressed: widget.onVoiceCallPressed,
                  ),
              ],
            ),
          ),
          if (widget.showContactAdvisory)
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: tc.warningTint,
                borderRadius: BorderRadius.circular(AeroRadii.badge),
                border: Border.all(color: tc.warning.withValues(alpha: 0.35)),
              ),
              child: Row(
                children: [
                  Icon(Icons.verified_user_rounded, size: 18, color: tc.warning),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'نوصي بالتواصل داخل التطبيق لحماية خصوصيتك وتوثيق الملاحظات الطبية.',
                      style: aeroText(size: 11.5, color: tc.textPrimary, height: 1.35),
                    ),
                  ),
                ],
              ),
            ),
          Expanded(
            child: widget.messages.isEmpty
                ? Center(
                    child: Text(
                      'ابدأ المحادثة الآن',
                      style: aeroText(size: 14, color: tc.textSecondary),
                    ),
                  )
                : ListView.builder(
                    controller: _scrollController,
                    padding: const EdgeInsets.all(16),
                    reverse: true,
                    itemCount: widget.messages.length,
                    itemBuilder: (context, index) => _buildMessageBubble(widget.messages[index], tc),
                  ),
          ),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: tc.surface,
              border: Border(top: BorderSide(color: tc.border)),
            ),
            child: SafeArea(
              top: false,
              child: Row(
                children: [
                  if (widget.onPickAttachment != null)
                    IconButton(
                      icon: Icon(Icons.attach_file_rounded, color: tc.textSecondary),
                      onPressed: widget.onPickAttachment,
                      tooltip: 'إرفاق وصفة أو تقرير',
                    ),
                  Expanded(
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      decoration: BoxDecoration(
                        color: tc.surfaceElevated,
                        borderRadius: BorderRadius.circular(24),
                        border: Border.all(color: tc.border),
                      ),
                      child: TextField(
                        controller: _textController,
                        style: aeroText(size: 15, color: tc.textPrimary),
                        minLines: 1,
                        maxLines: 4,
                        decoration: InputDecoration(
                          hintText: 'اكتب رسالتك هنا...',
                          hintStyle: aeroText(size: 14, color: tc.textMuted),
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
                    backgroundColor: tc.primary,
                    radius: 24,
                    child: widget.isSending
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                          )
                        : IconButton(
                            icon: const Icon(Icons.send_rounded, color: Colors.white, size: 20),
                            tooltip: 'إرسال',
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

  Widget _buildMessageBubble(AeroChatMessage msg, TamThemeColors tc) {
    if (msg.isSystem) {
      return Center(
        child: Container(
          margin: const EdgeInsets.symmetric(vertical: 8),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: tc.surfaceElevated,
            borderRadius: BorderRadius.circular(99),
          ),
          child: Text(
            msg.text,
            textAlign: TextAlign.center,
            style: aeroText(size: 12, color: tc.textSecondary),
          ),
        ),
      );
    }

    final isMe = msg.isMe;
    return Align(
      alignment: isMe ? Alignment.centerLeft : Alignment.centerRight,
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.78),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: isMe ? tc.primaryTint : tc.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: msg.isFailed ? tc.danger : (isMe ? tc.primary.withValues(alpha: 0.25) : tc.border),
          ),
        ),
        child: Column(
          crossAxisAlignment: isMe ? CrossAxisAlignment.start : CrossAxisAlignment.end,
          children: [
            if (msg.attachmentUrl != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: tc.surfaceElevated,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.insert_drive_file_rounded, color: tc.primary, size: 20),
                      const SizedBox(width: 6),
                      Text('مرفق طبي', style: aeroText(size: 12, color: tc.textPrimary)),
                    ],
                  ),
                ),
              ),
            Text(
              msg.text,
              style: aeroText(
                size: 15,
                color: tc.textPrimary,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 4),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '${msg.createdAt.hour.toString().padLeft(2, '0')}:${msg.createdAt.minute.toString().padLeft(2, '0')}',
                  style: aeroText(size: 10.5, color: tc.textMuted),
                ),
                if (isMe) ...[
                  const SizedBox(width: 5),
                  if (msg.isFailed)
                    InkWell(
                      onTap: () => widget.onRetryMessage?.call(msg),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.error_outline_rounded, size: 14, color: tc.danger),
                          const SizedBox(width: 3),
                          Text('إعادة المحاولة', style: aeroText(size: 11, weight: FontWeight.w700, color: tc.danger)),
                        ],
                      ),
                    )
                  else if (msg.isPending)
                    Icon(Icons.schedule_rounded, size: 13, color: tc.textMuted)
                  else
                    Icon(
                      msg.isRead ? Icons.done_all_rounded : Icons.done_rounded,
                      size: 14,
                      color: msg.isRead ? tc.primary : tc.textMuted,
                    ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}
