import 'package:flutter/material.dart';
import '../tokens/aero_typography.dart';
import '../tokens/tam_status.dart';
import '../tokens/tam_tokens.dart';

/// Semantic status badge for any Tamreedy request, visit, or credential state.
class TamStatusBadge extends StatelessWidget {
  final String? status;
  final String? labelOverride;
  final Color? foregroundOverride;
  final Color? backgroundOverride;
  final IconData? iconOverride;
  final bool compact;

  const TamStatusBadge({
    super.key,
    this.status,
    this.labelOverride,
    this.foregroundOverride,
    this.backgroundOverride,
    this.iconOverride,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.tamColors;
    final parsed = TamRequestStatus.parse(status);
    final fg = foregroundOverride ?? parsed.foreground(c);
    final bg = backgroundOverride ?? parsed.background(c);
    final icon = iconOverride ?? parsed.icon;
    final label = labelOverride ??
        (parsed == TamRequestStatus.unknown &&
                status != null &&
                status!.trim().isNotEmpty
            ? status!
            : parsed.labelAr);

    return Semantics(
      label: label,
      child: Container(
        padding: EdgeInsets.symmetric(
          horizontal: compact ? TamSpacing.sm : TamSpacing.md,
          vertical: compact ? TamSpacing.xs : 6,
        ),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: fg.withValues(alpha: 0.22)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: compact ? 13 : 15, color: fg),
            const SizedBox(width: 5),
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: aeroText(
                  size: compact ? 11 : 12,
                  weight: FontWeight.w700,
                  color: fg,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
