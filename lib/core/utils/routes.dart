import 'package:flutter/material.dart';

/// Custom route transitions for smoother navigation
class AppRoutes {
  /// Slide-up transition for forward navigation
  static Route<T> slideUp<T>({
    required Widget Function(BuildContext) builder,
  }) {
    return PageRouteBuilder(
      pageBuilder: (context, _, _) => builder(context),
      transitionsBuilder: (_, animation, _, child) {
        return SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(0, 0.08),
            end: Offset.zero,
          ).animate(CurvedAnimation(
            parent: animation,
            curve: Curves.easeOut,
          )),
          child: child,
        );
      },
      transitionDuration: const Duration(milliseconds: 250),
    );
  }

  /// Fade transition for dialogs / simple transitions
  static Route<T> fade<T>({
    required Widget Function(BuildContext) builder,
  }) {
    return PageRouteBuilder(
      pageBuilder: (context, _, _) => builder(context),
      transitionsBuilder: (_, animation, _, child) {
        return FadeTransition(
          opacity: animation,
          child: child,
        );
      },
      transitionDuration: const Duration(milliseconds: 200),
    );
  }
}
