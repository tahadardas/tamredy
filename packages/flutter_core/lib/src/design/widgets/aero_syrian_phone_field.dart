import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../auth/syrian_phone_normalizer.dart';
import '../tokens/aero_colors.dart';
import '../tokens/aero_radii.dart';
import '../tokens/aero_shadows.dart';
import '../tokens/aero_typography.dart';

/// Aero Syrian Phone Field — Dedicated input for Syrian mobile numbers.
/// Features a fixed `+963` country capsule and accepts local 10-digit format `09XXXXXXXX`.
class AeroSyrianPhoneField extends StatefulWidget {
  final TextEditingController? controller;
  final ValueChanged<String>? onChanged;
  final void Function(String local, String? e164)? onPhoneChanged;
  final FormFieldValidator<String>? validator;
  final bool enabled;
  final bool autoFocus;
  final String? initialValue;

  const AeroSyrianPhoneField({
    super.key,
    this.controller,
    this.onChanged,
    this.onPhoneChanged,
    this.validator,
    this.enabled = true,
    this.autoFocus = false,
    this.initialValue,
  });

  @override
  State<AeroSyrianPhoneField> createState() => _AeroSyrianPhoneFieldState();
}

class _AeroSyrianPhoneFieldState extends State<AeroSyrianPhoneField> {
  late final TextEditingController _controller;
  bool _ownsController = false;
  String? _errorText;
  int _charCount = 0;

  @override
  void initState() {
    super.initState();
    if (widget.controller != null) {
      _controller = widget.controller!;
    } else {
      _controller = TextEditingController(text: widget.initialValue ?? '');
      _ownsController = true;
    }
    _charCount = _controller.text.length;
    _controller.addListener(_handleTextChange);
  }

  void _handleTextChange() {
    final raw = _controller.text;
    final converted = SyrianPhoneNormalizer.convertArabicIndicDigits(raw);
    if (converted != raw) {
      _controller.value = _controller.value.copyWith(
        text: converted,
        selection: TextSelection.collapsed(offset: converted.length),
      );
      return;
    }

    // Auto-normalize if an international number was pasted (e.g. +9639...)
    if (raw.startsWith('+963') || raw.startsWith('00963') || (raw.startsWith('963') && raw.length > 9)) {
      final local = SyrianPhoneNormalizer.toLocalSyrianMobile(raw);
      if (local != null) {
        _controller.value = _controller.value.copyWith(
          text: local,
          selection: TextSelection.collapsed(offset: local.length),
        );
        return;
      }
    }

    final count = _controller.text.length;
    if (count != _charCount) {
      setState(() {
        _charCount = count;
        _errorText = null;
      });
    }

    widget.onChanged?.call(_controller.text);
    if (widget.onPhoneChanged != null) {
      final e164 = SyrianPhoneNormalizer.normalizeSyrianMobile(_controller.text);
      widget.onPhoneChanged!(_controller.text, e164);
    }
  }

  @override
  void dispose() {
    _controller.removeListener(_handleTextChange);
    if (_ownsController) {
      _controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isComplete = _charCount == 10;
    final isOver = _charCount > 10;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: AeroRadii.buttonRadius,
            border: Border.all(
              color: _errorText != null
                  ? AeroColors.danger
                  : isComplete
                      ? AeroColors.accentTeal
                      : AeroColors.borderLight,
              width: isComplete || _errorText != null ? 1.5 : 1.0,
            ),
            boxShadow: AeroShadows.card,
          ),
          child: Row(
            textDirection: TextDirection.ltr,
            children: [
              // Fixed Country Capsule (+963)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                decoration: BoxDecoration(
                  color: AeroColors.aeroTint.withValues(alpha: 0.5),
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(16),
                    bottomLeft: Radius.circular(16),
                  ),
                  border: Border(
                    right: BorderSide(color: AeroColors.borderLight, width: 1.0),
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      '🇸🇾',
                      style: const TextStyle(fontSize: 16),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      '+963',
                      style: aeroText(
                        size: 15,
                        weight: FontWeight.w700,
                        color: AeroColors.primaryNavy,
                      ),
                    ),
                  ],
                ),
              ),

              // Local Mobile Number Field (09XXXXXXXX)
              Expanded(
                child: TextField(
                  controller: _controller,
                  enabled: widget.enabled,
                  autofocus: widget.autoFocus,
                  keyboardType: TextInputType.phone,
                  textDirection: TextDirection.ltr,
                  style: aeroText(
                    size: 16,
                    weight: FontWeight.w700,
                    letterSpacing: 1.2,
                    color: AeroColors.textPrimary,
                  ),
                  inputFormatters: [
                    LengthLimitingTextInputFormatter(10),
                    FilteringTextInputFormatter.allow(RegExp(r'[\d٠-٩]')),
                  ],
                  decoration: InputDecoration(
                    hintText: '09XXXXXXXX',
                    hintTextDirection: TextDirection.ltr,
                    hintStyle: aeroText(
                      size: 15,
                      weight: FontWeight.w500,
                      color: AeroColors.textMuted,
                      letterSpacing: 1.0,
                    ),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                    border: InputBorder.none,
                    isDense: true,
                  ),
                ),
              ),

              // Character count indicator (e.g. 10/10)
              Padding(
                padding: const EdgeInsets.only(right: 12),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: isComplete
                        ? AeroColors.accentTeal.withValues(alpha: 0.15)
                        : isOver
                            ? AeroColors.danger.withValues(alpha: 0.15)
                            : AeroColors.lightCanvas,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    '$_charCount/10',
                    style: aeroText(
                      size: 11,
                      weight: FontWeight.w700,
                      color: isComplete
                          ? AeroColors.accentTeal
                          : isOver
                              ? AeroColors.danger
                              : AeroColors.textMuted,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        if (_errorText != null)
          Padding(
            padding: const EdgeInsets.only(top: 6, right: 8),
            child: Row(
              children: [
                Icon(Icons.error_outline_rounded, size: 14, color: AeroColors.danger),
                const SizedBox(width: 4),
                Text(
                  _errorText!,
                  style: aeroText(size: 12, weight: FontWeight.w600, color: AeroColors.danger),
                ),
              ],
            ),
          ),
      ],
    );
  }
}
