import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../tokens/aero_typography.dart';
import '../tokens/tam_tokens.dart';

/// Standardized Tamreedy 2.0 Text Field supporting Default, Focused, Disabled,
/// Success, and Error states, RTL/LTR, keyboard actions, and accessible touch targets.
class TamTextField extends StatelessWidget {
  final TextEditingController? controller;
  final FocusNode? focusNode;
  final String? label;
  final String? hint;
  final String? errorText;
  final String? helperText;
  final bool isSuccess;
  final bool enabled;
  final bool obscureText;
  final int maxLines;
  final TextInputType? keyboardType;
  final TextInputAction? textInputAction;
  final TextDirection? textDirection;
  final Iterable<String>? autofillHints;
  final List<TextInputFormatter>? inputFormatters;
  final IconData? prefixIcon;
  final Widget? suffix;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;
  final VoidCallback? onTap;
  final bool readOnly;

  const TamTextField({
    super.key,
    this.controller,
    this.focusNode,
    this.label,
    this.hint,
    this.errorText,
    this.helperText,
    this.isSuccess = false,
    this.enabled = true,
    this.obscureText = false,
    this.maxLines = 1,
    this.keyboardType,
    this.textInputAction,
    this.textDirection,
    this.autofillHints,
    this.inputFormatters,
    this.prefixIcon,
    this.suffix,
    this.onChanged,
    this.onSubmitted,
    this.onTap,
    this.readOnly = false,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.tamColors;
    final hasError = errorText != null && errorText!.trim().isNotEmpty;
    final borderColor = hasError
        ? c.danger
        : isSuccess
            ? c.success
            : c.border;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (label != null) ...[
          Text(
            label!,
            style: aeroText(
              size: 13,
              weight: FontWeight.w600,
              color: enabled ? c.textPrimary : c.textMuted,
            ),
          ),
          const SizedBox(height: 6),
        ],
        Container(
          constraints: const BoxConstraints(minHeight: 50),
          decoration: BoxDecoration(
            color: enabled ? c.surface : c.surfaceElevated,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: borderColor,
              width: hasError || isSuccess ? 1.5 : 1.0,
            ),
          ),
          child: TextField(
            controller: controller,
            focusNode: focusNode,
            enabled: enabled,
            readOnly: readOnly,
            obscureText: obscureText,
            maxLines: maxLines,
            keyboardType: keyboardType,
            textInputAction: textInputAction,
            textDirection: textDirection,
            autofillHints: autofillHints,
            inputFormatters: inputFormatters,
            onChanged: onChanged,
            onSubmitted: onSubmitted,
            onTap: onTap,
            style: aeroText(
              size: 14.5,
              weight: FontWeight.w500,
              color: enabled ? c.textPrimary : c.textMuted,
            ),
            decoration: InputDecoration(
              hintText: hint,
              hintStyle: aeroText(size: 14, color: c.textMuted),
              border: InputBorder.none,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: TamSpacing.md,
                vertical: TamSpacing.md,
              ),
              prefixIcon: prefixIcon != null
                  ? Icon(prefixIcon, size: 20, color: c.textSecondary)
                  : null,
              suffixIcon: suffix,
            ),
          ),
        ),
        if (hasError) ...[
          const SizedBox(height: 5),
          Row(
            children: [
              Icon(Icons.error_outline_rounded, size: 14, color: c.danger),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  errorText!,
                  style: aeroText(
                    size: 12,
                    weight: FontWeight.w600,
                    color: c.danger,
                  ),
                ),
              ),
            ],
          ),
        ] else if (helperText != null) ...[
          const SizedBox(height: 5),
          Text(
            helperText!,
            style: aeroText(size: 12, color: c.textSecondary),
          ),
        ],
      ],
    );
  }
}

/// Instant search input with clear button.
class TamSearchField extends StatelessWidget {
  final TextEditingController? controller;
  final String hint;
  final ValueChanged<String>? onChanged;
  final VoidCallback? onClear;

  const TamSearchField({
    super.key,
    this.controller,
    this.hint = 'ابحث عن خدمة أو ممرض...',
    this.onChanged,
    this.onClear,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.tamColors;
    final hasText = controller != null && controller!.text.isNotEmpty;
    return Container(
      constraints: const BoxConstraints(minHeight: 48),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: c.border),
        boxShadow: c.cardShadow,
      ),
      child: TextField(
        controller: controller,
        onChanged: onChanged,
        style: aeroText(size: 14.5, color: c.textPrimary),
        decoration: InputDecoration(
          hintText: hint,
          hintStyle: aeroText(size: 14, color: c.textMuted),
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: TamSpacing.md,
            vertical: TamSpacing.md,
          ),
          prefixIcon: Icon(Icons.search_rounded, color: c.primary, size: 22),
          suffixIcon: hasText
              ? IconButton(
                  tooltip: 'مسح البحث',
                  icon: Icon(Icons.close_rounded, color: c.textSecondary, size: 20),
                  onPressed: () {
                    controller?.clear();
                    onChanged?.call('');
                    onClear?.call();
                  },
                )
              : null,
        ),
      ),
    );
  }
}

/// Standardized Dropdown wrapper.
class TamDropdown<T> extends StatelessWidget {
  final String? label;
  final T? value;
  final List<DropdownMenuItem<T>> items;
  final ValueChanged<T?>? onChanged;
  final String? hint;
  final String? errorText;

  const TamDropdown({
    super.key,
    this.label,
    required this.value,
    required this.items,
    required this.onChanged,
    this.hint,
    this.errorText,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.tamColors;
    final hasError = errorText != null && errorText!.isNotEmpty;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (label != null) ...[
          Text(
            label!,
            style: aeroText(
              size: 13,
              weight: FontWeight.w600,
              color: c.textPrimary,
            ),
          ),
          const SizedBox(height: 6),
        ],
        Container(
          constraints: const BoxConstraints(minHeight: 50),
          padding: const EdgeInsets.symmetric(horizontal: TamSpacing.md),
          decoration: BoxDecoration(
            color: onChanged == null ? c.surfaceElevated : c.surface,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: hasError ? c.danger : c.border),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<T>(
              value: value,
              items: items,
              onChanged: onChanged,
              isExpanded: true,
              dropdownColor: c.surface,
              hint: hint != null
                  ? Text(hint!, style: aeroText(size: 14, color: c.textMuted))
                  : null,
              style: aeroText(size: 14, color: c.textPrimary),
              icon: Icon(Icons.keyboard_arrow_down_rounded, color: c.textSecondary),
            ),
          ),
        ),
        if (hasError) ...[
          const SizedBox(height: 5),
          Text(
            errorText!,
            style: aeroText(size: 12, weight: FontWeight.w600, color: c.danger),
          ),
        ],
      ],
    );
  }
}

/// Multi-select chip group with accessible >= 48dp touch targets.
class TamMultiSelect<T> extends StatelessWidget {
  final String? label;
  final List<T> options;
  final Set<T> selected;
  final String Function(T item) labelBuilder;
  final ValueChanged<Set<T>> onChanged;
  final bool enabled;

  const TamMultiSelect({
    super.key,
    this.label,
    required this.options,
    required this.selected,
    required this.labelBuilder,
    required this.onChanged,
    this.enabled = true,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.tamColors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (label != null) ...[
          Text(
            label!,
            style: aeroText(
              size: 13,
              weight: FontWeight.w600,
              color: c.textPrimary,
            ),
          ),
          const SizedBox(height: TamSpacing.sm),
        ],
        Wrap(
          spacing: TamSpacing.sm,
          runSpacing: TamSpacing.sm,
          children: options.map((opt) {
            final isSelected = selected.contains(opt);
            return FilterChip(
              selected: isSelected,
              label: Text(
                labelBuilder(opt),
                style: aeroText(
                  size: 13,
                  weight: isSelected ? FontWeight.w700 : FontWeight.w500,
                  color: isSelected ? c.primaryDark : c.textPrimary,
                ),
              ),
              selectedColor: c.primaryTint,
              backgroundColor: c.surface,
              checkmarkColor: c.primaryDark,
              side: BorderSide(
                color: isSelected ? c.primary : c.border,
              ),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              onSelected: !enabled
                  ? null
                  : (v) {
                      final next = Set<T>.from(selected);
                      if (v) {
                        next.add(opt);
                      } else {
                        next.remove(opt);
                      }
                      onChanged(next);
                    },
            );
          }).toList(),
        ),
      ],
    );
  }
}
