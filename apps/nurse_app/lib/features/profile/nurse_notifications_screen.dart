import 'package:flutter/material.dart';
import 'package:tamreedy_core/tamreedy_core.dart';
import '../../app/nurse_router.dart';
import '../../core/nurse_session_coordinator.dart';

class NurseNotificationsScreen extends StatefulWidget {
  final NurseSessionCoordinator session;

  const NurseNotificationsScreen({super.key, required this.session});

  @override
  State<NurseNotificationsScreen> createState() => _NurseNotificationsScreenState();
}

class _NurseNotificationsScreenState extends State<NurseNotificationsScreen> {
  List<AeroNotificationItem> _items = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    if (kDemoMode) {
      _items = const [];
      setState(() => _loading = false);
      return;
    }
    try {
      final res = await widget.session.api.getMap('/v1/notifications?limit=40');
      final raw = res['items'] as List? ?? const [];
      _items = [
        for (final row in raw)
          if (row is Map)
            AeroNotificationItem(
              id: '${row['id'] ?? ''}',
              type: '${row['event_type'] ?? row['type'] ?? ''}',
              title: '${row['title'] ?? 'إشعار'}',
              body: '${row['body'] ?? ''}',
              createdAt: DateTime.tryParse('${row['created_at'] ?? ''}')?.toLocal() ?? DateTime.now(),
              isRead: row['read_at'] != null || row['is_read'] == true,
              data: row['data'] is Map
                  ? Map<String, dynamic>.from(row['data'] as Map)
                  : Map<String, dynamic>.from(row),
            ),
      ];
      widget.session.unreadNotifications.value = _items.where((i) => !i.isRead).length;
    } catch (_) {}
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _markAllRead() async {
    try {
      await widget.session.api.post('/v1/notifications/read-all', {});
      await _load();
    } catch (_) {}
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
          title: Text('سجل الإشعارات', style: aeroText(size: 16, weight: FontWeight.w800, color: tc.textPrimary)),
        ),
        body: AeroNotificationsCenter(
          notifications: _items,
          isLoading: _loading,
          onMarkAllRead: _markAllRead,
          onNotificationTap: (id) async {
            final idx = _items.indexWhere((i) => i.id == id);
            if (idx < 0) return;
            final item = _items[idx];
            if (!item.isRead && !kDemoMode) {
              widget.session.api.post('/v1/notifications/$id/read', {}).catchError((_) => <String, dynamic>{});
            }
            if (item.data != null) {
              final target = widget.session.notifications.routeFromTap(item.data!);
              if (target != null && mounted) {
                Navigator.of(context).pop();
                NurseRouter.handleNotificationTarget(widget.session, target);
              }
            }
          },
        ),
      ),
    );
  }
}
