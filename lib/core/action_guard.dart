import 'dart:async';

import 'package:flutter/material.dart';

/// Reusable one-at-a-time action guard for buttons.
///
/// Wraps an async onPressed: the button is disabled (returns null) while the
/// action runs, so double-taps and multi-clicks cannot re-trigger it. Wrap
/// the result with a ListenableBuilder or use [guard] directly in stateful
/// screens that manage their own _busy flag.
///
/// Usage in a StatefulWidget:
///   `bool _busy = false;`
///   `Future<void> _onPressed() => runGuarded(this, () async { ... });`
///
/// Simplest usage — stateless double-click protection without a flag:
///   `onPressed: once(() async { ... })`   // ignores taps while previous runs
class ActionGuard {
  ActionGuard._();

  static final Set<Object> _running = {};

  /// Runs [action] only if no other action with the same [key] is running.
  /// Taps made while running are silently ignored (no queue, no re-entry).
  static Future<void> run(Object key, Future<void> Function() action) async {
    if (_running.contains(key)) return;
    _running.add(key);
    try {
      await action();
    } finally {
      _running.remove(key);
    }
  }
}

extension StateGuardExt on State {
  /// Runs [action] guarded against re-entry, with optional error handling:
  /// exceptions are caught and surfaced as a SnackBar instead of crashing.
  Future<void> guarded(Future<void> Function() action, {String? errorTitle}) {
    return ActionGuard.run(this, () async {
      try {
        await action();
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                errorTitle != null
                    ? '$errorTitle: ${_shortError(e)}'
                    : 'Something went wrong: ${_shortError(e)}',
              ),
              duration: const Duration(seconds: 3),
            ),
          );
        }
      }
    });
  }
}

String _shortError(Object e) {
  final msg = e.toString();
  return msg.length > 120 ? '${msg.substring(0, 120)}…' : msg;
}
