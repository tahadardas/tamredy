import 'package:flutter/material.dart';
import '../tokens/aero_motion_tokens.dart';
import '../tokens/aero_radii.dart';
import '../tokens/aero_shadows.dart';
import 'aero_button.dart';

/// AeroSmartCta — Option C Smart Floating CTA.
/// Listens to a [ScrollController] and smoothly transitions into view
/// once the top Hero action has scrolled past [scrollThreshold].
/// Hides automatically when the keyboard is active.
class AeroSmartCta extends StatefulWidget {
  final ScrollController scrollController;
  final String label;
  final VoidCallback onTap;
  final IconData icon;
  final double scrollThreshold;

  const AeroSmartCta({
    super.key,
    required this.scrollController,
    required this.label,
    required this.onTap,
    this.icon = Icons.add_circle_outline_rounded,
    this.scrollThreshold = 180.0,
  });

  @override
  State<AeroSmartCta> createState() => _AeroSmartCtaState();
}

class _AeroSmartCtaState extends State<AeroSmartCta> {
  bool _visible = false;

  @override
  void initState() {
    super.initState();
    widget.scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    widget.scrollController.removeListener(_onScroll);
    super.dispose();
  }

  void _onScroll() {
    if (!widget.scrollController.hasClients) return;
    final offset = widget.scrollController.offset;
    final shouldShow = offset > widget.scrollThreshold;
    if (shouldShow != _visible) {
      setState(() => _visible = shouldShow);
    }
  }

  @override
  Widget build(BuildContext context) {
    final keyboardOpen = MediaQuery.of(context).viewInsets.bottom > 0;
    final show = _visible && !keyboardOpen;

    return AnimatedSlide(
      offset: show ? Offset.zero : const Offset(0, 1.8),
      duration: AeroMotionTokens.sheetDuration,
      curve: AeroMotionTokens.springCurve,
      child: AnimatedOpacity(
        opacity: show ? 1.0 : 0.0,
        duration: AeroMotionTokens.buttonDuration,
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AeroRadii.dock),
            boxShadow: AeroShadows.hero,
          ),
          child: AeroButton.teal(
            widget.label,
            onPressed: show ? widget.onTap : null,
            leadingIcon: Icon(widget.icon, color: Colors.white, size: 20),
            height: 52,
            fontSize: 16,
          ),
        ),
      ),
    );
  }
}
