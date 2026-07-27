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
  final Color accentColor;

  /// Exact app theme surface/onSurface colors — overrides editor.css's own
  /// (only approximate) light/dark fallback colors, so there's no visible
  /// color seam switching between the read view and this WebView.
  final Color backgroundColor;
  final Color foregroundColor;
  final VoidCallback? onDirty;

  const RichHtmlEditor({
    super.key,
    required this.initialHtml,
    required this.darkMode,
    required this.accentColor,
    required this.backgroundColor,
    required this.foregroundColor,
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

  /// [direction] is one of 'left'/'center'/'right'/'justify'.
  Future<void> align(String direction) =>
      _run('window.cmdAlign(${_jsString(direction)})');
  Future<void> insertLink(String url) =>
      _run('window.cmdInsertLink(${_jsString(url)})');

  /// [dataUri] is the live preview shown until the note is saved; [ref] must
  /// match the `ref` passed to the upload call that persists this image —
  /// see `_NoteEditorContentState._pendingImages`.
  Future<void> insertImage(String dataUri, String ref) =>
      _run('window.cmdInsertImage(${_jsString(dataUri)}, ${_jsString(ref)})');

  /// Aligns the last-tapped image (see editor.js's `activeImage`); a no-op
  /// if no image is currently selected. [direction] is one of
  /// 'left'/'center'/'right'/'justify'.
  Future<void> alignImage(String direction) =>
      _run('window.cmdAlignImage(${_jsString(direction)})');

  /// Resizes the last-tapped image to a preset width (height scaled to
  /// match its natural aspect ratio). [preset] is one of
  /// 'small'/'medium'/'large'/'original'.
  Future<void> resizeImage(String preset) =>
      _run('window.cmdResizeImage(${_jsString(preset)})');

  /// Crops the last-tapped image to a preset aspect ratio via
  /// object-fit/object-position (display-only — the uploaded file itself is
  /// untouched). [preset] is one of 'square'/'portrait'/'landscape'/'wide'/
  /// 'none'.
  Future<void> cropImage(String preset) =>
      _run('window.cmdCropImage(${_jsString(preset)})');
  Future<void> insertCheckbox() => _run('window.cmdInsertCheckbox()');
  Future<void> insertDivider() => _run('window.cmdInsertDivider()');
  Future<void> insertTable({int rows = 3, int cols = 3}) =>
      _run('window.cmdInsertTable($rows, $cols)');
  Future<void> tableInsertRowAbove() => _run('window.cmdTableInsertRowAbove()');
  Future<void> tableInsertRowBelow() => _run('window.cmdTableInsertRowBelow()');
  Future<void> tableDeleteRow() => _run('window.cmdTableDeleteRow()');
  Future<void> tableInsertColumnLeft() =>
      _run('window.cmdTableInsertColumnLeft()');
  Future<void> tableInsertColumnRight() =>
      _run('window.cmdTableInsertColumnRight()');
  Future<void> tableDeleteColumn() => _run('window.cmdTableDeleteColumn()');
  Future<void> tableDeleteTable() => _run('window.cmdTableDeleteTable()');
  Future<void> fontColor(Color color) =>
      _run('window.cmdFontColor(${_jsString(_toHex(color))})');
  Future<void> highlight(Color color) =>
      _run('window.cmdHighlight(${_jsString(_toHex(color))})');
  Future<void> fontFamily(String name) =>
      _run('window.cmdFontFamily(${_jsString(name)})');

  /// [px] is a plain pixel value (e.g. 18), not a preset name.
  Future<void> fontSize(int px) => _run('window.cmdFontSize($px)');

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
      // The WebView is its own network stack (Chromium/WebView2), separate
      // from SynologyApiClient's http.Client — it does standard TLS
      // validation and silently fails to load inline note images (broken-
      // image icon, no error surfaced) against a NAS with a self-signed or
      // hostname-mismatched cert. Trust it here too, mirroring
      // createTrustingClient()'s rationale for the app's own HTTP calls.
      onReceivedServerTrustAuthRequest: (controller, challenge) async {
        debugPrint('WebView server trust challenge for '
            '${challenge.protectionSpace.host}:${challenge.protectionSpace.port} '
            '— proceeding.');
        return ServerTrustAuthResponse(
            action: ServerTrustAuthResponseAction.PROCEED);
      },
      onReceivedError: (controller, request, error) {
        debugPrint('WebView resource error loading ${request.url}: '
            '${error.type} ${error.description}');
      },
      onReceivedHttpError: (controller, request, errorResponse) {
        debugPrint('WebView HTTP error loading ${request.url}: '
            '${errorResponse.statusCode} ${errorResponse.reasonPhrase}');
      },
      onLoadStop: (controller, url) async {
        await controller.evaluateJavascript(
            source: 'window.setDarkMode(${widget.darkMode});');
        await controller.evaluateJavascript(
            source:
                'window.setAccentColor(${_jsString(_toHex(widget.accentColor))});');
        await controller.evaluateJavascript(
            source: 'window.setSurfaceColors('
                '${_jsString(_toHex(widget.backgroundColor))}, '
                '${_jsString(_toHex(widget.foregroundColor))});');
        await controller.evaluateJavascript(
            source: 'window.setContent(${_jsString(widget.initialHtml)});');
      },
    );
  }
}
