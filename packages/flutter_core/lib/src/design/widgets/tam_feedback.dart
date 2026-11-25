import 'package:flutter/material.dart';
import '../tokens/aero_radii.dart';
import '../tokens/aero_typography.dart';
import '../tokens/tam_tokens.dart';
import 'aero_button.dart';

enum TamToastTone { info, success, warning, error }

/// Unified snackbar/toast helper respecting RTL, SafeArea, and semantic colors.
class TamToast {
  static void show(
    BuildContext context,
    String message, {
    TamToastTone tone = TamToastTone.info,
    Duration duration = const Duration(seconds: 3),
  }) {
    final c = context.tamColors;
    final Color accent;
    final IconData icon;
    switch (tone) {
      case TamToastTone.success:
        accent = c.success;
        icon = Icons.check_circle_rounded;
        break;
      case TamToastTone.warning:
        accent = c.warning;
        icon = Icons.warning_amber_rounded;
        break;
      case TamToastTone.error:
        accent = c.danger;
        icon = Icons.error_rounded;
        break;
      case TamToastTone.info:
        accent = c.secondary;
        icon = Icons.info_rounded;
        break;
    }

    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          duration: duration,
          behavior: SnackBarBehavior.floating,
          backgroundColor: c.isDark ? c.surfaceElevated : const Color(0xFF0F172A),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
            side: BorderSide(color: accent.withValues(alpha: 0.45)),
          ),
          content: Row(
            children: [
              Icon(icon, color: accent, size: 20),
              const SizedBox(width: TamSpacing.sm),
              Expanded(
                child: Text(
                  message,
                  style: aeroText(
                    size: 13,
                    weight: FontWeight.w600,
                    color: Colors.white,
                    height: 1.4,
                  ),
                ),
              ),
            ],
          ),
        ),
      );
  }
}

/// Standardized Tamreedy 2.0 Bottom Sheet wrapper.
class TamBottomSheet extends StatelessWidget {
  final String? title;
  final String? subtitle;
  final Widget child;
  final double maxHeightFactor;

  const TamBottomSheet({
    super.key,
    this.title,
    this.subtitle,
    required this.child,
    this.maxHeightFactor = 0.88,
  });

  static Future<T?> show<T>(
    BuildContext context, {
    String? title,
    String? subtitle,
    required Widget child,
    bool isDismissible = true,
    bool enableDrag = true,
    double maxHeightFactor = 0.88,
  }) {
    return showModalBottomSheet<T>(
      context: context,
      isScrollControlled: true,
      isDismissible: isDismissible,
      enableDrag: enableDrag,
      backgroundColor: Colors.transparent,
      builder: (_) => TamBottomSheet(
        title: title,
        subtitle: subtitle,
        maxHeightFactor: maxHeightFactor,
        child: child,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = context.tamColors;
    final bottomInset = MediaQuery.viewInsetsOf(context).bottom;
    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * maxHeightFactor,
      ),
      padding: EdgeInsets.only(bottom: bottomInset),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: AeroRadii.sheetRadius,
        border: Border.all(color: c.border),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: TamSpacing.md),
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: c.borderStrong,
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
            ),
            if (title != null) ...[
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  TamSpacing.xl,
                  TamSpacing.lg,
                  TamSpacing.xl,
                  TamSpacing.xs,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title!,
                      style: aeroText(
                        size: 18,
                        weight: FontWeight.w700,
                        color: c.textPrimary,
                      ),
                    ),
                    if (subtitle != null) ...[
                      const SizedBox(height: TamSpacing.xs),
                      Text(
                        subtitle!,
                        style: aeroText(
                          size: 13,
                          color: c.textSecondary,
                          height: 1.4,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              Divider(color: c.border),
            ],
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(TamSpacing.xl),
                child: child,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Standardized Tamreedy 2.0 Dialog with confirm/cancel actions.
class TamDialog extends StatelessWidget {
  final String title;
  final String? message;
  final Widget? content;
  final String confirmLabel;
  final String? cancelLabel;
  final bool destructive;
  final VoidCallback? onConfirm;

  const TamDialog({
    super.key,
    required this.title,
    this.message,
    this.content,
    this.confirmLabel = 'تأكيد',
    this.cancelLabel = 'إلغاء',
    this.destructive = false,
    this.onConfirm,
  });

  static Future<bool?> confirm(
    BuildContext context, {
    required String title,
    required String message,
    String confirmLabel = 'تأكيد',
    String cancelLabel = 'إلغاء',
    bool destructive = false,
  }) {
    return showDialog<bool>(
      context: context,
      builder: (ctx) => TamDialog(
        title: title,
        message: message,
        confirmLabel: confirmLabel,
        cancelLabel: cancelLabel,
        destructive: destructive,
        onConfirm: () => Navigator.of(ctx).pop(true),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = context.tamColors;
    return Dialog(
      backgroundColor: c.surface,
      shape: RoundedRectangleBorder(
        borderRadius: AeroRadii.dialogRadius,
        side: BorderSide(color: c.border),
      ),
      child: Padding(
        padding: const EdgeInsets.all(TamSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              title,
              style: aeroText(
                size: 18,
                weight: FontWeight.w700,
                color: c.textPrimary,
              ),
            ),
            if (message != null) ...[
              const SizedBox(height: TamSpacing.sm),
              Text(
                message!,
                style: aeroText(
                  size: 14,
                  color: c.textSecondary,
                  height: 1.5,
                ),
              ),
            ],
            if (content != null) ...[
              const SizedBox(height: TamSpacing.md),
              content!,
            ],
            const SizedBox(height: TamSpacing.xl),
            Row(
              children: [
                if (cancelLabel != null) ...[
                  Expanded(
                    child: AeroButton.secondary(
                      cancelLabel!,
                      height: 46,
                      fontSize: 14,
                      onPressed: () => Navigator.of(context).pop(false),
                    ),
                  ),
                  const SizedBox(width: TamSpacing.md),
                ],
                Expanded(
                  child: destructive
                      ? AeroButton.danger(
                          confirmLabel,
                          height: 46,
                          fontSize: 14,
                          onPressed:
                              onConfirm ?? () => Navigator.of(context).pop(true),
                        )
                      : AeroButton.teal(
                          confirmLabel,
                          height: 46,
                          fontSize: 14,
                          onPressed:
                              onConfirm ?? () => Navigator.of(context).pop(true),
                        ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
