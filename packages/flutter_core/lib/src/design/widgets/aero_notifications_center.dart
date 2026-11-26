import 'package:flutter/material.dart';
import '../tokens/aero_typography.dart';
import '../tokens/tam_tokens.dart';

class AeroNotificationItem {
  final String id;
  final String type;
  final String title;
  final String body;
  final DateTime createdAt;
  final bool isRead;
  final Map<String, dynamic>? data;

  const AeroNotificationItem({
    required this.id,
    required this.type,
    required this.title,
    required this.body,
    required this.createdAt,
    this.isRead = false,
    this.data,
  });
}

class AeroNotificationsCenter extends StatefulWidget {
  final List<AeroNotificationItem> notifications;
  final ValueChanged<String>? onNotificationTap;
  final VoidCallback? onMarkAllRead;
  final bool isLoading;

  const AeroNotificationsCenter({
    super.key,
    required this.notifications,
    this.onNotificationTap,
    this.onMarkAllRead,
    this.isLoading = false,
  });

  @override
  State<AeroNotificationsCenter> createState() => _AeroNotificationsCenterState();
}

class _AeroNotificationsCenterState extends State<AeroNotificationsCenter> {
  bool _unreadOnly = false;

  IconData _getTypeIcon(String type) {
    if (type.startsWith('chat.')) return Icons.chat_bubble_outline_rounded;
    if (type.startsWith('call.')) return Icons.call_rounded;
    if (type.startsWith('payment.')) return Icons.receipt_long_rounded;
    if (type.startsWith('safety.')) return Icons.shield_rounded;
    if (type.startsWith('marketplace.')) return Icons.campaign_rounded;
    if (type.startsWith('offer.')) return Icons.notifications_active_rounded;
    return Icons.local_hospital_rounded;
  }

  String _formatTime(DateTime dt) {
    final diff = DateTime.now().difference(dt);
    if (diff.inMinutes < 1) return 'الآن';
    if (diff.inMinutes < 60) return 'منذ ${diff.inMinutes} دقيقة';
    if (diff.inHours < 24) return 'منذ ${diff.inHours} ساعة';
    return 'منذ ${diff.inDays} يوم';
  }

  @override
  Widget build(BuildContext context) {
    final tc = context.tamColors;
    final displayedList = _unreadOnly
        ? widget.notifications.where((n) => !n.isRead).toList()
        : widget.notifications;
    final unreadCount = widget.notifications.where((n) => !n.isRead).length;

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Container(
        height: MediaQuery.of(context).size.height * 0.8,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        color: tc.background,
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Text(
                      'مركز التنبيهات',
                      style: aeroText(size: 19, weight: FontWeight.w800, color: tc.textPrimary),
                    ),
                    if (unreadCount > 0) ...[
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: tc.primary,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          '$unreadCount',
                          style: aeroText(size: 11, weight: FontWeight.w700, color: Colors.white),
                        ),
                      ),
                    ],
                  ],
                ),
                if (widget.onMarkAllRead != null && unreadCount > 0)
                  TextButton(
                    onPressed: widget.onMarkAllRead,
                    child: Text(
                      'تحديد الكل كمقروء',
                      style: aeroText(size: 13, weight: FontWeight.w700, color: tc.primary),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                ChoiceChip(
                  label: Text('الكل (${widget.notifications.length})', style: aeroText(size: 12.5, color: tc.textPrimary)),
                  selected: !_unreadOnly,
                  selectedColor: tc.primaryTint,
                  onSelected: (val) {
                    if (val) setState(() => _unreadOnly = false);
                  },
                ),
                const SizedBox(width: 8),
                ChoiceChip(
                  label: Text('غير مقروءة ($unreadCount)', style: aeroText(size: 12.5, color: tc.textPrimary)),
                  selected: _unreadOnly,
                  selectedColor: tc.primaryTint,
                  onSelected: (val) {
                    if (val) setState(() => _unreadOnly = true);
                  },
                ),
              ],
            ),
            const SizedBox(height: 12),
            Expanded(
              child: widget.isLoading
                  ? Center(child: CircularProgressIndicator(color: tc.primary))
                  : displayedList.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.notifications_off_outlined, size: 48, color: tc.textMuted),
                              const SizedBox(height: 8),
                              Text('لا توجد تنبيهات حالياً', style: aeroText(size: 14, color: tc.textSecondary)),
                            ],
                          ),
                        )
                      : ListView.separated(
                          itemCount: displayedList.length,
                          separatorBuilder: (_, __) => const SizedBox(height: 8),
                          itemBuilder: (context, index) {
                            final notif = displayedList[index];
                            return Material(
                              color: notif.isRead ? tc.surface : tc.primaryTint.withValues(alpha: 0.45),
                              borderRadius: BorderRadius.circular(16),
                              child: InkWell(
                                borderRadius: BorderRadius.circular(16),
                                onTap: () => widget.onNotificationTap?.call(notif.id),
                                child: Container(
                                  padding: const EdgeInsets.all(14),
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(16),
                                    border: Border.all(color: tc.border),
                                  ),
                                  child: Row(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      CircleAvatar(
                                        radius: 20,
                                        backgroundColor: notif.isRead ? tc.surfaceElevated : tc.primaryTint,
                                        child: Icon(
                                          _getTypeIcon(notif.type),
                                          size: 20,
                                          color: notif.isRead ? tc.textSecondary : tc.primary,
                                        ),
                                      ),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Row(
                                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                              children: [
                                                Expanded(
                                                  child: Text(
                                                    notif.title,
                                                    style: aeroText(
                                                      size: 14,
                                                      weight: notif.isRead ? FontWeight.w600 : FontWeight.w800,
                                                      color: tc.textPrimary,
                                                    ),
                                                  ),
                                                ),
                                                Text(
                                                  _formatTime(notif.createdAt),
                                                  style: aeroText(size: 11, color: tc.textMuted),
                                                ),
                                              ],
                                            ),
                                            const SizedBox(height: 4),
                                            Text(
                                              notif.body,
                                              style: aeroText(size: 13, color: tc.textSecondary, height: 1.4),
                                            ),
                                          ],
                                        ),
                                      ),
                                      if (!notif.isRead) ...[
                                        const SizedBox(width: 8),
                                        Container(
                                          width: 8,
                                          height: 8,
                                          decoration: BoxDecoration(color: tc.primary, shape: BoxShape.circle),
                                        ),
                                      ],
                                    ],
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
            ),
          ],
        ),
      ),
    );
  }
}
