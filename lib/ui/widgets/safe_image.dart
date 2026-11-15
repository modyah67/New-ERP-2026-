// lib/ui/widgets/safe_image.dart
// ─────────────────────────────────────────────
// Resilient image loader that prefers direct File access
// on desktop platforms to bypass AssetManifest.bin disconnects
// during hot reload, with graceful fallback to AssetImage.
// ─────────────────────────────────────────────

import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

ImageProvider safeImageProvider(String assetPath) {
  if (!kIsWeb) {
    try {
      final file = File(assetPath);
      if (file.existsSync()) {
        return FileImage(file);
      }
    } catch (_) {}
  }
  return AssetImage(assetPath);
}

class SafeImage extends StatelessWidget {
  final String assetPath;
  final double? width;
  final double? height;
  final BoxFit? fit;
  final Widget Function(BuildContext, Object, StackTrace?)? errorBuilder;
  final Color? color;
  final Animation<double>? opacity;

  const SafeImage(
    this.assetPath, {
    super.key,
    this.width,
    this.height,
    this.fit,
    this.errorBuilder,
    this.color,
    this.opacity,
  });

  @override
  Widget build(BuildContext context) {
    if (!kIsWeb) {
      try {
        final file = File(assetPath);
        if (file.existsSync()) {
          return Image.file(
            file,
            width: width,
            height: height,
            fit: fit,
            color: color,
            opacity: opacity,
            errorBuilder: errorBuilder,
          );
        }
      } catch (_) {}
    }

    return Image.asset(
      assetPath,
      width: width,
      height: height,
      fit: fit,
      color: color,
      opacity: opacity,
      errorBuilder: errorBuilder,
    );
  }
}
