import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _noteColorsKey = 'note_colors';
const _notebookColorsKey = 'notebook_colors';
const _colorLabelsKey = 'color_labels';

/// Client-side-only color assignments (id -> ARGB int), never synced to the
/// NAS. NoteStation's server schema has no such field for either notes or
/// notebooks, and the project's fidelity-first design principle
/// (docs/RICH-TEXT.md) rules out smuggling it into synced `content` — so
/// this lives purely in shared_preferences, independent of NAS-vs-local mode,
/// and survives regardless of which repository a note/notebook came from.
/// Shared by [noteColorsProvider] and [notebookColorsProvider] — they're
/// separate maps (a note and a notebook could coincidentally share an id
/// namespace) but otherwise identical.
class IdColorNotifier extends StateNotifier<Map<String, Color>> {
  IdColorNotifier(this._prefsKey) : super(const {}) {
    _restore();
  }

  final String _prefsKey;

  Future<void> _restore() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_prefsKey);
    if (raw == null) return;
    final decoded = jsonDecode(raw) as Map<String, dynamic>;
    state = decoded.map((k, v) => MapEntry(k, Color(v as int)));
  }

  Future<void> _persist() async {
    final prefs = await SharedPreferences.getInstance();
    final encoded = state.map((k, v) => MapEntry(k, v.toARGB32()));
    await prefs.setString(_prefsKey, jsonEncode(encoded));
  }

  Future<void> setColor(String id, Color color) async {
    state = {...state, id: color};
    await _persist();
  }

  Future<void> clearColor(String id) async {
    if (!state.containsKey(id)) return;
    state = {...state}..remove(id);
    await _persist();
  }
}

final noteColorsProvider =
    StateNotifierProvider<IdColorNotifier, Map<String, Color>>(
        (ref) => IdColorNotifier(_noteColorsKey));

final notebookColorsProvider =
    StateNotifierProvider<IdColorNotifier, Map<String, Color>>(
        (ref) => IdColorNotifier(_notebookColorsKey));

/// Base palette — enough distinct, accessible hues to build a real
/// color-coding scheme, not just a handful of "starter" colors. Intentionally
/// distinct from AppTheme.accentPalette so a note/notebook's color doesn't
/// visually collide with whatever accent color the user picked for the app.
const baseColorPalette = [
  Color(0xFFE53935), // red
  Color(0xFFD81B60), // pink
  Color(0xFF8E24AA), // purple
  Color(0xFF5E35B1), // deep purple
  Color(0xFF3949AB), // indigo
  Color(0xFF1E88E5), // blue
  Color(0xFF00ACC1), // cyan
  Color(0xFF00897B), // teal
  Color(0xFF43A047), // green
  Color(0xFF7CB342), // light green
  Color(0xFFC0CA33), // lime
  Color(0xFFFDD835), // yellow
  Color(0xFFFFB300), // amber
  Color(0xFFFB8C00), // orange
  Color(0xFF6D4C41), // brown
  Color(0xFF757575), // grey
];

/// User-defined names for colors (e.g. "Urgent" → red), so a color scheme is
/// self-documenting instead of a bare swatch grid. Keyed by ARGB int, shared
/// across the note and notebook pickers — labeling red once labels it
/// everywhere red is offered.
class ColorLabelsNotifier extends StateNotifier<Map<int, String>> {
  ColorLabelsNotifier() : super(const {}) {
    _restore();
  }

  Future<void> _restore() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_colorLabelsKey);
    if (raw == null) return;
    final decoded = jsonDecode(raw) as Map<String, dynamic>;
    state = decoded.map((k, v) => MapEntry(int.parse(k), v as String));
  }

  Future<void> _persist() async {
    final prefs = await SharedPreferences.getInstance();
    final encoded = state.map((k, v) => MapEntry(k.toString(), v));
    await prefs.setString(_colorLabelsKey, jsonEncode(encoded));
  }

  Future<void> setLabel(Color color, String label) async {
    final key = color.toARGB32();
    final trimmed = label.trim();
    if (trimmed.isEmpty) {
      if (!state.containsKey(key)) return;
      state = {...state}..remove(key);
    } else {
      state = {...state, key: trimmed};
    }
    await _persist();
  }
}

final colorLabelsProvider =
    StateNotifierProvider<ColorLabelsNotifier, Map<int, String>>(
        (ref) => ColorLabelsNotifier());

/// Shared color-swatch + label picker used from the note list, note editor,
/// and the notebook sidebar menu. Tap a swatch to apply it; long-press a
/// swatch to give it a custom name (e.g. "Urgent" for red) — building a
/// personal color-coding scheme that's remembered everywhere the picker is
/// shown, for both notes and notebooks.
void showColorPicker(
  BuildContext context,
  WidgetRef ref, {
  required String id,
  required StateNotifierProvider<IdColorNotifier, Map<String, Color>> colorsProvider,
}) {
  showDialog<void>(
    context: context,
    builder: (dialogContext) => _ColorPickerDialog(
      id: id,
      colorsProvider: colorsProvider,
    ),
  );
}

class _ColorPickerDialog extends ConsumerWidget {
  final String id;
  final StateNotifierProvider<IdColorNotifier, Map<String, Color>> colorsProvider;

  const _ColorPickerDialog({required this.id, required this.colorsProvider});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs = Theme.of(context).colorScheme;
    final current = ref.watch(colorsProvider)[id];
    final labels = ref.watch(colorLabelsProvider);

    return AlertDialog(
      title: const Text('Color'),
      content: SizedBox(
        width: 320,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Tap a color to apply it. Long-press a color to name it.',
              style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                InkWell(
                  borderRadius: BorderRadius.circular(20),
                  onTap: () {
                    ref.read(colorsProvider.notifier).clearColor(id);
                    Navigator.of(context).pop();
                  },
                  child: Tooltip(
                    message: 'None',
                    child: Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(color: cs.outlineVariant, width: 1.5),
                      ),
                      child: Icon(Icons.close_rounded,
                          size: 18, color: cs.onSurfaceVariant),
                    ),
                  ),
                ),
                ...baseColorPalette.map((color) {
                  final selected = current?.toARGB32() == color.toARGB32();
                  final label = labels[color.toARGB32()];
                  return InkWell(
                    borderRadius: BorderRadius.circular(20),
                    onTap: () {
                      ref.read(colorsProvider.notifier).setColor(id, color);
                      Navigator.of(context).pop();
                    },
                    onLongPress: () => _editLabel(context, ref, color, label),
                    child: Tooltip(
                      message: label ?? 'Long-press to name this color',
                      child: Container(
                        width: 36,
                        height: 36,
                        decoration: BoxDecoration(
                          color: color,
                          shape: BoxShape.circle,
                          border: selected
                              ? Border.all(color: cs.onSurface, width: 2.5)
                              : null,
                        ),
                        child: selected
                            ? const Icon(Icons.check_rounded,
                                color: Colors.white, size: 18)
                            : null,
                      ),
                    ),
                  );
                }),
              ],
            ),
            if (labels.isNotEmpty) ...[
              const SizedBox(height: 16),
              Align(
                alignment: Alignment.centerLeft,
                child: Text('Your color scheme',
                    style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: cs.onSurfaceVariant)),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: baseColorPalette
                    .where((c) => labels.containsKey(c.toARGB32()))
                    .map((c) => Chip(
                          avatar: CircleAvatar(backgroundColor: c, radius: 8),
                          label: Text(labels[c.toARGB32()]!,
                              style: const TextStyle(fontSize: 12)),
                          materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          visualDensity: VisualDensity.compact,
                        ))
                    .toList(),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Close'),
        ),
      ],
    );
  }

  Future<void> _editLabel(
      BuildContext context, WidgetRef ref, Color color, String? current) async {
    final controller = TextEditingController(text: current ?? '');
    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            CircleAvatar(backgroundColor: color, radius: 10),
            const SizedBox(width: 10),
            const Text('Name this color'),
          ],
        ),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: 'Label',
            hintText: 'e.g. Urgent, Personal, Follow-up…',
          ),
          onSubmitted: (v) => Navigator.of(context).pop(v),
        ),
        actions: [
          if (current != null)
            TextButton(
              onPressed: () => Navigator.of(context).pop(''),
              child: const Text('Remove label'),
            ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(controller.text),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (result != null) {
      await ref.read(colorLabelsProvider.notifier).setLabel(color, result);
    }
  }
}
