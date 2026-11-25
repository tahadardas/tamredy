import 'package:flutter/material.dart';
import '../tokens/aero_typography.dart';
import '../tokens/tam_tokens.dart';
import 'aero_button.dart';

/// Unified empty state with clear icon, title, subtitle, and optional action.
class TamEmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? message;
  final String? actionLabel;
  final VoidCallback? onAction;

  const TamEmptyState({
    super.key,
    this.icon = Icons.inbox_rounded,
    required this.title,
    this.message,
    this.actionLabel,
    this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.tamColors;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(TamSpacing.xxl),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: c.border),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: c.primaryTint,
              shape: BoxShape.circle,
            ),
            child: Icon(icon, size: 28, color: c.primary),
          ),
          const SizedBox(height: TamSpacing.md),
          Text(
            title,
            textAlign: TextAlign.center,
            style: aeroText(
              size: 16,
              weight: FontWeight.w700,
              color: c.textPrimary,
            ),
          ),
          if (message != null && message!.isNotEmpty) ...[
            const SizedBox(height: TamSpacing.xs),
            Text(
              message!,
              textAlign: TextAlign.center,
              style: aeroText(
                size: 13,
                color: c.textSecondary,
                height: 1.5,
              ),
            ),
          ],
          if (actionLabel != null && onAction != null) ...[
            const SizedBox(height: TamSpacing.lg),
            AeroButton.secondary(
              actionLabel!,
              onPressed: onAction,
              height: 44,
              fontSize: 14,
            ),
          ],
        ],
      ),
    );
  }
}

/// Unified error state with Arabic-friendly recovery action.
class TamErrorState extends StatelessWidget {
  final String title;
  final String message;
  final String retryLabel;
  final VoidCallback? onRetry;

  const TamErrorState({
    super.key,
    this.title = 'تعذر تحميل البيانات',
    required this.message,
    this.retryLabel = 'إعادة المحاولة',
    this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.tamColors;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(TamSpacing.xl),
      decoration: BoxDecoration(
        color: c.dangerTint.withValues(alpha: c.isDark ? 0.35 : 0.6),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: c.danger.withValues(alpha: 0.3)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.error_outline_rounded, size: 36, color: c.danger),
          const SizedBox(height: TamSpacing.sm),
          Text(
            title,
            textAlign: TextAlign.center,
            style: aeroText(
              size: 15,
              weight: FontWeight.w700,
              color: c.textPrimary,
            ),
          ),
          const SizedBox(height: TamSpacing.xs),
          Text(
            message,
            textAlign: TextAlign.center,
            style: aeroText(size: 13, color: c.textSecondary, height: 1.45),
          ),
          if (onRetry != null) ...[
            const SizedBox(height: TamSpacing.md),
            AeroButton.danger(
              retryLabel,
              onPressed: onRetry,
              height: 44,
              fontSize: 14,
            ),
          ],
        ],
      ),
    );
  }
}

/// Offline / weak-connection banner or full card.
class TamOfflineState extends StatelessWidget {
  final String message;
  final VoidCallback? onRetry;
  final bool compact;

  const TamOfflineState({
    super.key,
    this.message = 'الاتصال بالإنترنت متوقف حالياً. يتم عرض آخر البيانات المحفوظة.',
    this.onRetry,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.tamColors;
    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(compact ? TamSpacing.md : TamSpacing.lg),
      decoration: BoxDecoration(
        color: c.warningTint.withValues(alpha: c.isDark ? 0.35 : 0.85),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: c.warning.withValues(alpha: 0.35)),
      ),
      child: Row(
        children: [
          Icon(Icons.wifi_off_rounded, color: c.warning, size: 22),
          const SizedBox(width: TamSpacing.md),
          Expanded(
            child: Text(
              message,
              style: aeroText(
                size: 12.5,
                weight: FontWeight.w600,
                color: c.textPrimary,
                height: 1.4,
              ),
            ),
          ),
          if (onRetry != null)
            TextButton(
              onPressed: onRetry,
              child: Text(
                'تحديث',
                style: aeroText(
                  size: 12.5,
                  weight: FontWeight.w700,
                  color: c.warning,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Skeleton loading placeholder respecting Reduced Motion.
class TamSkeleton extends StatefulWidget {
  final double? width;
  final double height;
  final double borderRadius;

  const TamSkeleton({
    super.key,
    this.width,
    this.height = 16,
    this.borderRadius = 12,
  });

  const TamSkeleton.card({super.key, this.height = 96})
      : width = double.infinity,
        borderRadius = 20;

  @override
  State<TamSkeleton> createState() => _TamSkeletonState();
}

class _TamSkeletonState extends State<TamSkeleton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1100),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.tamColors;
    final reduced = MediaQuery.disableAnimationsOf(context);
    if (reduced) {
      return Container(
        width: widget.width,
        height: widget.height,
        decoration: BoxDecoration(
          color: c.surfaceElevated,
          borderRadius: BorderRadius.circular(widget.borderRadius),
        ),
      );
    }
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        final color = Color.lerp(
          c.surfaceElevated,
          c.border,
          _controller.value,
        );
        return Container(
          width: widget.width,
          height: widget.height,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(widget.borderRadius),
          ),
        );
      },
    );
  }
}
