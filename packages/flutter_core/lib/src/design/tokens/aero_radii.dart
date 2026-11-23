import 'package:flutter/material.dart';

/// Aero Signature & Medical Aero Premium Design Tokens — Radii
abstract class AeroRadii {
  static const double heroCard = 26.0;
  static const double mainCard = 24.0;
  static const double secondaryCard = 20.0;
  static const double button = 18.0;
  static const double buttonSmall = 14.0;
  static const double dialog = 28.0;
  static const double sheet = 28.0;
  static const double dock = 999.0; // Fully Rounded Pill
  static const double badge = 999.0;

  static const BorderRadius heroCardRadius = BorderRadius.all(Radius.circular(heroCard));
  static const BorderRadius mainCardRadius = BorderRadius.all(Radius.circular(mainCard));
  static const BorderRadius secondaryCardRadius = BorderRadius.all(Radius.circular(secondaryCard));
  static const BorderRadius buttonRadius = BorderRadius.all(Radius.circular(button));
  static const BorderRadius dialogRadius = BorderRadius.all(Radius.circular(dialog));
  static const BorderRadius sheetRadius = BorderRadius.only(
    topLeft: Radius.circular(sheet),
    topRight: Radius.circular(sheet),
  );
  static const BorderRadius dockRadius = BorderRadius.all(Radius.circular(dock));
}
