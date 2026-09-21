import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// Registers a branded in-app error widget that replaces Flutter's default
/// red-screen-of-death.  Call once during startup — the builder is a global
/// singleton so it must only be assigned a single time.
void registerErrorWidget() {
  ErrorWidget.builder = (details) {
    return Material(
      color: Colors.yellow.shade100,
      child: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('⚠️ 渲染错误',
                  style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Colors.red)),
              const SizedBox(height: 8),
              Text(details.exceptionAsString(),
                  style: const TextStyle(fontSize: 12)),
              if (details.stack != null) ...[
                const SizedBox(height: 8),
                Text(details.stack.toString(),
                    style: const TextStyle(
                        fontSize: 10, color: AppColors.slate)),
              ],
            ],
          ),
        ),
      ),
    );
  };
}
