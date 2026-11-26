import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:tamreedy_core/tamreedy_core.dart';

class ConversationSummary {
  final String id;
  final String? requestId;
  final String peerName;
  final String peerRoleLabel;
  final String? lastMessage;
  final DateTime? updatedAt;
  final int unreadCount;

  const ConversationSummary({
    required this.id,
    this.requestId,
    required this.peerName,
    this.peerRoleLabel = 'ممرض مرخص معتمد',
    this.lastMessage,
    this.updatedAt,
    this.unreadCount = 0,
  });

  factory ConversationSummary.fromJson(Map<String, dynamic> j) => ConversationSummary(
        id: '${j['id'] ?? ''}',
        requestId: j['request_id']?.toString(),
        peerName: '${j['peer_name'] ?? j['nurse_name'] ?? j['other_party_name'] ?? 'فريق التمريض'}',
        peerRoleLabel: '${j['peer_role_label'] ?? 'ممرض مرخص معتمد'}',
        lastMessage: j['last_message_text']?.toString() ?? j['last_message']?.toString(),
        updatedAt: DateTime.tryParse('${j['last_message_at'] ?? j['updated_at'] ?? ''}')?.toLocal(),
        unreadCount: (num.tryParse('${j['unread_count'] ?? 0}') ?? 0).toInt(),
      );
}

class ConversationsStore extends ChangeNotifier {
  final TamreedyApi api;
  final RealtimeEventBus eventBus;

  ConversationsStore({required this.api, required this.eventBus}) {
    _sub = eventBus.whereType(const {'chat.message', 'chat.read'}).listen((_) {
      loadConversations(silent: true);
    });
  }

  late final StreamSubscription<RealtimeEvent> _sub;

  bool loading = false;
  String? error;
  List<ConversationSummary> conversations = const [];

  int _sessionGen = 0;

  int get totalUnread => conversations.fold<int>(0, (acc, c) => acc + c.unreadCount);

  void resetForSessionChange() {
    _sessionGen++;
    conversations = const [];
    loading = false;
    error = null;
    notifyListeners();
  }

  Future<void> loadConversations({bool silent = false}) async {
    if (kDemoMode) {
      conversations = const [];
      notifyListeners();
      return;
    }
    final gen = _sessionGen;
    if (!silent) {
      loading = true;
      error = null;
      notifyListeners();
    }
    try {
      final raw = await api.getList('/v1/conversations');
      if (gen != _sessionGen) return;
      conversations = [
        for (final row in raw)
          if (row is Map) ConversationSummary.fromJson(Map<String, dynamic>.from(row)),
      ];
      error = null;
    } catch (e) {
      if (gen != _sessionGen) return;
      if (!silent) {
        error = explainError(e, fallback: 'تعذر تحميل المحادثات');
      }
    } finally {
      if (gen == _sessionGen) {
        loading = false;
        notifyListeners();
      }
    }
  }

  @override
  void dispose() {
    _sub.cancel();
    super.dispose();
  }
}
