import 'dart:async';

class RealtimeEvent {
  final String eventId;
  final String type;
  final Map<String, dynamic> payload;
  final DateTime receivedAt;

  String get id => eventId;

  const RealtimeEvent({
    required this.eventId,
    required this.type,
    required this.payload,
    required this.receivedAt,
  });
}

/// Broadcasts deduplicated realtime domain events without forcing global UI reloads.
class RealtimeEventBus {
  final _controller = StreamController<RealtimeEvent>.broadcast();
  final _connectionController = StreamController<bool>.broadcast();
  final _seenIds = <String>{};
  final _seenOrder = <String>[];
  static const int _maxSeen = 1024;
  bool _connected = false;

  Stream<RealtimeEvent> get stream => _controller.stream;
  bool get isConnected => _connected;
  Stream<bool> get connectionStateStream => _connectionController.stream;

  void setConnected(bool connected) {
    if (_connected == connected) return;
    _connected = connected;
    if (!_connectionController.isClosed) {
      _connectionController.add(connected);
    }
  }

  Stream<RealtimeEvent> whereType(Set<String> types) =>
      _controller.stream.where((e) => types.contains(e.type));

  bool emit({
    required String eventId,
    required String type,
    required Map<String, dynamic> payload,
  }) {
    if (eventId.isNotEmpty) {
      if (_seenIds.contains(eventId)) return false;
      _seenIds.add(eventId);
      _seenOrder.add(eventId);
      if (_seenOrder.length > _maxSeen) {
        final oldest = _seenOrder.removeAt(0);
        _seenIds.remove(oldest);
      }
    }
    if (!_controller.isClosed) {
      _controller.add(
        RealtimeEvent(
          eventId: eventId,
          type: type,
          payload: payload,
          receivedAt: DateTime.now(),
        ),
      );
    }
    return true;
  }

  void clearDedupe() {
    _seenIds.clear();
    _seenOrder.clear();
  }

  void dispose() {
    _controller.close();
    _connectionController.close();
  }
}
