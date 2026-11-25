import 'package:flutter/material.dart';
import '../tokens/aero_typography.dart';
import '../tokens/tam_tokens.dart';

class TamTimelineItem {
  final String title;
  final String? subtitle;
  final String? timestamp;
  final bool isDone;
  final bool isCurrent;
  final bool isError;

  const TamTimelineItem({
    required this.title,
    this.subtitle,
    this.timestamp,
    this.isDone = false,
    this.isCurrent = false,
    this.isError = false,
  });
}

/// Vertical visit/order lifecycle timeline.
class TamTimeline extends StatelessWidget {
  final List<TamTimelineItem> items;

  const TamTimeline({super.key, required this.items});

  @override
  Widget build(BuildContext context) {
    final c = context.tamColors;
    return Column(
      children: List.generate(items.length, (i) {
        final item = items[i];
        final isLast = i == items.length - 1;
        final Color dotColor = item.isError
            ? c.danger
            : (item.isDone || item.isCurrent)
                ? c.primary
                : c.borderStrong;

        return IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(
                width: 24,
                child: Column(
                  children: [
                    Container(
                      width: 18,
                      height: 18,
                      decoration: BoxDecoration(
                        color: (item.isDone || item.isCurrent || item.isError)
                            ? dotColor
                            : c.surface,
                        shape: BoxShape.circle,
                        border: Border.all(color: dotColor, width: 2),
                      ),
                      child: item.isDone
                          ? const Icon(Icons.check, size: 11, color: Colors.white)
                          : item.isCurrent
                              ? Center(
                                  child: Container(
                                    width: 6,
                                    height: 6,
                                    decoration: const BoxDecoration(
                                      color: Colors.white,
                                      shape: BoxShape.circle,
                                    ),
                                  ),
                                )
                              : null,
                    ),
                    if (!isLast)
                      Expanded(
                        child: Container(
                          width: 2,
                          color: item.isDone ? c.primary : c.border,
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(width: TamSpacing.md),
              Expanded(
                child: Padding(
                  padding: EdgeInsets.only(bottom: isLast ? 0 : TamSpacing.lg),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              item.title,
                              style: aeroText(
                                size: 13.5,
                                weight: item.isCurrent
                                    ? FontWeight.w700
                                    : FontWeight.w600,
                                color: (item.isDone || item.isCurrent)
                                    ? c.textPrimary
                                    : c.textSecondary,
                              ),
                            ),
                          ),
                          if (item.timestamp != null)
                            Text(
                              item.timestamp!,
                              style: aeroText(
                                size: 11.5,
                                color: c.textMuted,
                              ),
                            ),
                        ],
                      ),
                      if (item.subtitle != null &&
                          item.subtitle!.isNotEmpty) ...[
                        const SizedBox(height: 2),
                        Text(
                          item.subtitle!,
                          style: aeroText(
                            size: 12,
                            color: c.textSecondary,
                            height: 1.4,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      }),
    );
  }
}

/// Horizontal multi-step booking stepper with clear labels & progress.
class TamStepper extends StatelessWidget {
  final List<String> steps;
  final int currentStep; // 0-indexed

  const TamStepper({
    super.key,
    required this.steps,
    required this.currentStep,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.tamColors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: List.generate(steps.length, (i) {
            final done = i < currentStep;
            final active = i == currentStep;
            return Expanded(
              child: Padding(
                padding: EdgeInsetsDirectional.only(
                  end: i < steps.length - 1 ? TamSpacing.xs : 0,
                ),
                child: AnimatedContainer(
                  duration: TamMotion.of(context, TamMotion.normal),
                  height: 5,
                  decoration: BoxDecoration(
                    color: done
                        ? c.primary
                        : active
                            ? c.secondary
                            : c.border,
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
              ),
            );
          }),
        ),
        const SizedBox(height: TamSpacing.sm),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Flexible(
              child: Text(
                steps[currentStep.clamp(0, steps.length - 1)],
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: aeroText(
                  size: 13,
                  weight: FontWeight.w700,
                  color: c.textPrimary,
                ),
              ),
            ),
            Text(
              'الخطوة ${currentStep + 1} من ${steps.length}',
              style: aeroText(
                size: 12,
                weight: FontWeight.w600,
                color: c.textSecondary,
              ),
            ),
          ],
        ),
      ],
    );
  }
}
