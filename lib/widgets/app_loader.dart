import 'dart:async';

import 'package:flutter/material.dart';
import 'package:lottie/lottie.dart';

import '../theme/glass.dart';

/// Shared full-screen loading indicator — the LazyTax sloth Lottie (the same
/// `loading.json` argon uses). Centered, looping; a drop-in replacement for
/// `Center(child: CircularProgressIndicator())` on page-level loads.
///
/// Shows nothing for the first [delay]: most waits end sooner, and a sloth
/// that appears for a split second reads as a glitch. The 206 KB animation is
/// then parsed off the UI isolate.
class AppLoader extends StatefulWidget {
  final double size;
  const AppLoader({super.key, this.size = 140});

  static const delay = Duration(milliseconds: 300);

  @override
  State<AppLoader> createState() => _AppLoaderState();
}

class _AppLoaderState extends State<AppLoader> {
  Timer? _timer;
  bool _show = false;

  @override
  void initState() {
    super.initState();
    _timer = Timer(AppLoader.delay, () {
      if (mounted) setState(() => _show = true);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final size = widget.size;
    return Center(
      child: _show
          ? Lottie.asset(
              'assets/animations/loading.json',
              width: size,
              height: size,
              repeat: true,
              backgroundLoading: true,
            )
          : SizedBox.square(dimension: size),
    );
  }
}

/// The launch loading screen: [AppLoader] on the glass backdrop, the same as
/// Today's own loading state. Auth restore, session bootstrap and Today's
/// first load all use it, so launch shows one continuous screen.
class GlassLoadingScreen extends StatelessWidget {
  const GlassLoadingScreen({super.key});

  @override
  Widget build(BuildContext context) => const AmbientBackdrop(
    child: Scaffold(backgroundColor: Colors.transparent, body: AppLoader()),
  );
}
