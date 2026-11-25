import 'package:flutter/painting.dart';

/// Soft colors Today gives habits: orange, violet, emerald, blue, pink,
/// amber, teal and rose (Tailwind 500s), readable on both themes.
const habitPalette = <Color>[
  Color(0xFFF97316),
  Color(0xFF8B5CF6),
  Color(0xFF10B981),
  Color(0xFF3B82F6),
  Color(0xFFEC4899),
  Color(0xFFEAB308),
  Color(0xFF14B8A6),
  Color(0xFFF43F5E),
];

/// A habit's color, picked from [habitPalette] by its id (FNV-1a hash), so
/// it stays the same across launches and devices. zinc doesn't store a color
/// yet; when it does, prefer that and keep this as the fallback.
Color habitColor(String? id) {
  var hash = 0x811C9DC5;
  for (final unit in (id ?? '').codeUnits) {
    hash = ((hash ^ unit) * 0x01000193) & 0xFFFFFFFF;
  }
  return habitPalette[hash % habitPalette.length];
}
