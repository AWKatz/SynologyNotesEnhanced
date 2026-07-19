import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

/// WebView-hosted `contenteditable` rich-text editor for notes whose HTML is
/// within the confirmed-safe NoteStation vocabulary (see
/// `lib/core/rich_html/rich_html_schema.dart`). Loads a small first-party
/// HTML/CSS/JS page (`assets/editor/`) rather than a third-party editor
/// engine — nothing to license or reverse-engineer. Safety comes from the
/// JS page's own `sanitize()`, which keeps every edit (and paste) within
/// that same vocabulary, mirrored from the Dart-side allowlist.
///
/// Callers get at the controller via a `GlobalKey<RichHtmlEditorState>` —
/// `getContent()` for saving, and the `cmd*`-style methods for toolbar
/// actions (bold, headings, checkboxes, tables, ...).
class RichHtmlEditor extends StatefulWidget {
  final String initialHtml;
  final bool darkMode;
  final VoidCallback? onDirty;

  const RichHtmlEditor({
    super.key,
    required this.initialHtml,
    required this.darkMode,
    this.onDirty,
  });

  @override
  State<RichHtmlEditor> createState() => RichHtmlEditorState();
}

class RichHtmlEditorState extends State<RichHtmlEditor> {
  InAppWebViewController? _controller;

  /// Returns the current (already-sanitized) HTML, for saving.
  Future<String> getContent() async {
    final result =
        await _controller?.evaluateJavascript(source: 'window.getContent()');
    return result as String? ?? widget.initialHtml;
  }

  Future<void> _run(String js) async {
    await _controller?.evaluateJavascript(source: js);
  }

  Future<void> bold() => _run('window.cmdBold()');
  Future<void> italic() => _run('window.cmdItalic()');
  Future<void> underline() => _run('window.cmdUnderline()');
  Future<void> strikethrough() => _run('window.cmdStrikethrough()');
  Future<void> superscript() => _run('window.cmdSuperscript()');
  Future<void> subscript() => _run('window.cmdSubscript()');
  Future<void> orderedList() => _run('window.cmdOrderedList()');
  Future<void> unorderedList() => _run('window.cmdUnorderedList()');
  Future<void> heading(int level) => _run('window.cmdHeading($level)');
  Future<void> paragraph() => _run('window.cmdParagraph()');
  Future<void> insertCheckbox() => _run('window.cmdInsertCheckbox()');
  Future<void> insertDivider() => _run('window.cmdInsertDivider()');
  Future<void> insertTable({int rows = 3, int cols = 3}) =>
      _run('window.cmdInsertTable($rows, $cols)');
  Future<void> fontColor(Color color) =>
      _run('window.cmdFontColor(${_jsString(_toHex(color))})');
  Future<void> highlight(Color color) =>
      _run('window.cmdHighlight(${_jsString(_toHex(color))})');
  Future<void> fontFamily(String name) =>
      _run('window.cmdFontFamily(${_jsString(name)})');

  static String _toHex(Color c) =>
      '#${c.toARGB32().toRadixString(16).padLeft(8, '0').substring(2)}';

  static String _jsString(String s) =>
      '"${s.replaceAll('\\', '\\\\').replaceAll('"', '\\"')}"';

  @override
  Widget build(BuildContext context) {
    return InAppWebView(
      initialFile: 'assets/editor/editor.html',
      initialSettings: InAppWebViewSettings(
        transparentBackground: true,
        disableVerticalScroll: false,
        disableHorizontalScroll: true,
      ),
      onWebViewCreated: (controller) {
        _controller = controller;
        controller.addJavaScriptHandler(
          handlerName: 'onDirty',
          callback: (args) {
            widget.onDirty?.call();
            return null;
          },
        );
      },
      onLoadStop: (controller, url) async {
        await controller.evaluateJavascript(
            source: 'window.setDarkMode(${widget.darkMode});');
        await controller.evaluateJavascript(
            source: 'window.setContent(${_jsString(widget.initialHtml)});');
      },
    );
  }
}
