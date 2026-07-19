import 'package:flutter/material.dart';

/// Consistent toast/snackbar feedback for actions across the app — so saving,
/// deleting, encrypting, tagging, etc. all give the same visual confirmation
/// (or failure notice) instead of silently succeeding or swallowing errors.
class AppToast {
  const AppToast._();

  static void success(BuildContext context, String message) {
    final cs = Theme.of(context).colorScheme;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Icon(Icons.check_circle_rounded, size: 18, color: cs.onInverseSurface),
            const SizedBox(width: 10),
            Expanded(child: Text(message)),
          ],
        ),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  static void error(BuildContext context, String message) {
    final cs = Theme.of(context).colorScheme;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.error_outline_rounded, size: 18, color: Colors.white),
            const SizedBox(width: 10),
            Expanded(child: Text(message)),
          ],
        ),
        backgroundColor: cs.error,
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 3),
      ),
    );
  }

  /// Shows an indeterminate progress toast for an action with a noticeable
  /// round-trip (e.g. creating a note against a NAS). Call `.close()` on the
  /// returned controller once the action finishes, success or not — closing
  /// this specific controller (rather than `hideCurrentSnackBar()`) avoids
  /// dismissing some other toast that may have been queued behind it.
  static ScaffoldFeatureController<SnackBar, SnackBarClosedReason> progress(
    BuildContext context,
    String message,
  ) {
    return ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            const SizedBox(width: 12),
            Text(message),
          ],
        ),
        duration: const Duration(seconds: 30),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }
}
