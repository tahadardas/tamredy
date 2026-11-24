import 'package:flutter/material.dart';
import '../tokens/aero_colors.dart';
import '../tokens/aero_typography.dart';
import 'aero_glass_card.dart';

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
    switch (type) {
      case 'VISIT_STATUS_CHANGED':
        return Icons.local_hospital;
      case 'CHAT_MESSAGE_RECEIVED':
        return Icons.chat_bubble_outline;
      case 'VOICE_CALL_MISSED':
        return Icons.phone_missed;
      case 'SCHEDULED_VISIT_REMINDER':
        return Icons.alarm;
      case 'CARE_PLAN_UPDATE':
        return Icons.calendar_month;
      case 'FINANCIAL_TRANSACTION':
      case 'WALLET_CREDIT':
        return Icons.account_balance_wallet;
      case 'SAFETY_ALERT':
        return Icons.shield;
      default:
        return Icons.notifications_none;
    }
  }

  String _formatTime(DateTime dt) {
    final diff = DateTime.now().difference(dt);
    if (diff.inMinutes < 60) {
      return 'منذ ${diff.inMinutes} دقيقة';
    } else if (diff.inHours < 24) {
      return 'منذ ${diff.inHours} ساعة';
    } else {
      return 'منذ ${diff.inDays} يوم';
    }
  }

  @override
  Widget build(BuildContext context) {
    final displayedList = _unreadOnly
        ? widget.notifications.where((n) => !n.isRead).toList()
        : widget.notifications;

    final unreadCount = widget.notifications.where((n) => !n.isRead).length;

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Container(
        height: MediaQuery.of(context).size.height * 0.8,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Column(
          children: [
            // Header
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Text(
                      'مركز التنبيهات',
                      style: aeroText(size: 18, weight: FontWeight.w700, color: AeroColors.primaryNavy),
                    ),
                    if (unreadCount > 0) ...[
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: AeroColors.accentTeal,
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
                      style: aeroText(size: 13, weight: FontWeight.w600, color: AeroColors.accentTeal),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 12),

            // Tabs / Filter Chips
            Row(
              children: [
                ChoiceChip(
                  label: Text('الكل (${widget.notifications.length})', style: aeroText(size: 12)),
                  selected: !_unreadOnly,
                  selectedColor: AeroColors.aeroTint,
                  onSelected: (val) {
                    if (val) setState(() => _unreadOnly = false);
                  },
                ),
                const SizedBox(width: 8),
                ChoiceChip(
                  label: Text('غير مقروءة ($unreadCount)', style: aeroText(size: 12)),
                  selected: _unreadOnly,
                  selectedColor: AeroColors.aeroTint,
                  onSelected: (val) {
                    if (val) setState(() => _unreadOnly = true);
                  },
                ),
              ],
            ),
            const SizedBox(height: 12),

            // List
            Expanded(
              child: widget.isLoading
                  ? const Center(child: CircularProgressIndicator(color: AeroColors.accentTeal))
                  : displayedList.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.notifications_off_outlined, size: 48, color: AeroColors.textMuted),
                              const SizedBox(height: 8),
                              Text(
                                'لا توجد تنبيهات حالياً',
                                style: aeroText(size: 14, color: AeroColors.textSecondary),
                              ),
                            ],
                          ),
                        )
                      : ListView.separated(
                          itemCount: displayedList.length,
                          separatorBuilder: (_, __) => const SizedBox(height: 8),
                          itemBuilder: (context, index) {
                            final notif = displayedList[index];
                            return GestureDetector(
                              onTap: () => widget.onNotificationTap?.call(notif.id),
                              child: AeroGlassCard(
                                padding: const EdgeInsets.all(12),
                                tintColor: notif.isRead ? Colors.white : AeroColors.aeroTintLight,
                                child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    CircleAvatar(
                                      radius: 20,
                                      backgroundColor: notif.isRead ? AeroColors.lightCanvas : AeroColors.aeroTint,
                                      child: Icon(
                                        _getTypeIcon(notif.type),
                                        size: 20,
                                        color: notif.isRead ? AeroColors.textSecondary : AeroColors.accentTeal,
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
                                                    weight: notif.isRead ? FontWeight.w600 : FontWeight.w700,
                                                    color: AeroColors.primaryNavy,
                                                  ),
                                                ),
                                              ),
                                              Text(
                                                _formatTime(notif.createdAt),
                                                style: aeroText(size: 10, color: AeroColors.textMuted),
                                              ),
                                            ],
                                          ),
                                          const SizedBox(height: 4),
                                          Text(
                                            notif.body,
                                            style: aeroText(size: 12, color: AeroColors.textSecondary, height: 1.3),
                                          ),
                                        ],
                                      ),
                                    ),
                                    if (!notif.isRead) ...[
                                      const SizedBox(width: 8),
                                      Container(
                                        width: 8,
                                        height: 8,
                                        decoration: const BoxDecoration(
                                          color: AeroColors.accentTeal,
                                          shape: BoxShape.circle,
                                        ),
                                      ),
                                    ],
                                  ],
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
