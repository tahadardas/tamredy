import 'package:flutter/material.dart';
import '../../core/api_models.dart';
import '../tokens/tam_tokens.dart';

/// Displays clear, non-blocking network/server state banner (Phase 9, Section 50).
class TamConnectionBanner extends StatelessWidget {
  final ValueNotifier<ConnectionHealth> health;
  final VoidCallback? onRetry;

  const TamConnectionBanner({
    super.key,
    required this.health,
    this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ConnectionHealth>(
      valueListenable: health,
      builder: (context, status, _) {
        if (status == ConnectionHealth.online) return const SizedBox.shrink();
        final tc = context.tamColors;
        final (bg, fg, icon, text) = switch (status) {
          ConnectionHealth.offline => (
            tc.dangerTint,
            tc.danger,
            Icons.wifi_off_rounded,
            'لا يوجد اتصال بالإنترنت — يتم الاحتفاظ بالمسودات والجلسة',
          ),
          ConnectionHealth.reconnecting => (
            tc.warningTint,
            tc.warning,
            Icons.sync_rounded,
            'جارٍ إعادة الاتصال بالخادم...',
          ),
          ConnectionHealth.staleData => (
            tc.warningTint,
            tc.warning,
            Icons.schedule_rounded,
            'البيانات المعروضة قد تكون غير محدثة — اسحب للتحديث',
          ),
          ConnectionHealth.serverUnavailable => (
            tc.dangerTint,
            tc.danger,
            Icons.cloud_off_rounded,
            'الخادم غير متاح مؤقتاً، يرجى المحاولة بعد لحظات',
          ),
          ConnectionHealth.online => (tc.successTint, tc.success, Icons.check, ''),
        };

        return Material(
          color: bg,
          child: SafeArea(
            bottom: false,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
              child: Row(
                children: [
                  Icon(icon, size: 17, color: fg),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      text,
                      style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w700,
                        color: tc.textPrimary,
                      ),
                    ),
                  ),
                  if (onRetry != null)
                    TextButton(
                      onPressed: onRetry,
                      style: TextButton.styleFrom(
                        minimumSize: const Size(48, 32),
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                      ),
                      child: Text(
                        'تحديث',
                        style: TextStyle(color: fg, fontWeight: FontWeight.w800, fontSize: 12.5),
                      ),
                    ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
