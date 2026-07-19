import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html_parser;

/// The confirmed-preserved HTML vocabulary NoteStation's server round-trips
/// without stripping — verified from a real "apply every formatting option,
/// save, reload" note (`test/fixtures/encrypted_note_12345.b64`, decrypted
/// via `NoteCrypto`; see `docs/RICH-TEXT.md`). A note using only this subset
/// is safe to open in the rich WebView editor; anything else stays
/// read-only, same fidelity-first fallback the app already used before this
/// editor existed.
///
/// This is the Dart-side half of the allowlist; `assets/editor/editor.js`'s
/// `sanitize()` enforces the same vocabulary on the JS side (on every edit
/// and on paste) so a note can't drift outside it while being edited. Keep
/// the two in sync — if you add a tag/attribute/style here, add it there too.
class RichHtmlSchema {
  const RichHtmlSchema._();

  static const allowedTags = {
    'h1', 'h2', 'h3', 'h4', 'h5', 'h6', // headings
    'div', 'p', // block/paragraph (div is what saved notes actually use)
    'b', 'i', 'u', 'sup', 'sub', 'span', // inline formatting
    'ol', 'ul', 'li', // lists
    'input', // checkboxes only (see _checkElement)
    'table', 'tbody', 'tr', 'td', // tables
    'hr', // divider
  };

  /// Attribute names allowed on any element.
  static const _allowedGlobalAttrs = {'style', 'class'};

  /// Attributes only meaningful on specific tags, on top of the global set.
  static const _allowedTagAttrs = {
    'input': {'type', 'src'},
    'hr': {'id'}, // TinyMCE's own "ext-genNNNN" — harmless, not required
  };

  static const _allowedStyleProps = {
    'font-family',
    'color',
    'background-color',
    'text-decoration',
    'width',
    'height',
  };

  /// Only this value has been seen for text-decoration (strikethrough).
  static const _allowedTextDecoration = {'line-through'};

  static final _fontSizeClass = RegExp(r'^syno-fontsize-[a-z]+$');
  static final _checkboxClass = RegExp(
      r'^syno-notestation-editor-checkbox( syno-notestation-editor-checkbox-checked)?$');

  /// True if [contentHtml] uses only the confirmed-preserved vocabulary —
  /// i.e. it's safe to load into the rich editor and save back without risk
  /// of the stock Note Station app silently stripping something on its next
  /// open.
  static bool isRoundTrippable(String contentHtml) {
    if (contentHtml.trim().isEmpty) return true;
    final fragment = html_parser.parseFragment(contentHtml);
    return _checkChildren(fragment);
  }

  static bool _checkChildren(dom.Node node) {
    for (final child in node.nodes) {
      if (child is dom.Element) {
        if (!_checkElement(child)) return false;
        if (!_checkChildren(child)) return false;
      } else if (child is dom.Text) {
        continue;
      } else {
        // Comments or anything else outside the confirmed vocabulary.
        return false;
      }
    }
    return true;
  }

  static bool _checkElement(dom.Element el) {
    final tag = (el.localName ?? '').toLowerCase();
    if (!allowedTags.contains(tag)) return false;

    for (final attrName in el.attributes.keys) {
      final name = attrName.toString().toLowerCase();
      if (_allowedGlobalAttrs.contains(name)) continue;
      if (_allowedTagAttrs[tag]?.contains(name) == true) continue;
      return false;
    }

    if (tag == 'input') {
      if (el.attributes['type'] != 'image') return false;
      final cls = el.attributes['class'] ?? '';
      if (!_checkboxClass.hasMatch(cls)) return false;
    }

    if (tag == 'span') {
      final cls = el.attributes['class'];
      if (cls != null && cls.isNotEmpty && !_fontSizeClass.hasMatch(cls)) {
        return false;
      }
    }

    final style = el.attributes['style'];
    if (style != null && style.isNotEmpty) {
      for (final declaration in style.split(';')) {
        final trimmed = declaration.trim();
        if (trimmed.isEmpty) continue;
        final sep = trimmed.indexOf(':');
        if (sep == -1) return false;
        final prop = trimmed.substring(0, sep).trim().toLowerCase();
        final value = trimmed.substring(sep + 1).trim().toLowerCase();
        if (!_allowedStyleProps.contains(prop)) return false;
        if (prop == 'text-decoration' &&
            !_allowedTextDecoration.contains(value)) {
          return false;
        }
      }
    }

    return true;
  }
}
