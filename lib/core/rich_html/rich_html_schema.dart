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
    'br', // line break — not in the captured fixture, but basic enough
    // (and standard in NoteStation's TinyMCE editor) that we allow it rather
    // than lose every blank line the WebView editor's Enter key produces.
    'a', // hyperlinks — verified round-trippable, see capture below
    'img', // attachment images — verified round-trippable, see capture below
  };

  /// Attribute names allowed on any element.
  static const _allowedGlobalAttrs = {'style', 'class'};

  /// Attributes only meaningful on specific tags, on top of the global set.
  static const _allowedTagAttrs = {
    'input': {'type', 'src'},
    'hr': {'id'}, // TinyMCE's own "ext-genNNNN" — harmless, not required
    'a': {'href'},
    // VERIFIED (2026-07-25 HAR capture — see rich-text capture notes): a
    // saved image tag never carries the real picture in `src` (same
    // transparent-gif trick as checkboxes) — the real link lives in `ref`,
    // resolved against the note's `attachment` map. `width`/`height` (plain
    // attributes, not style) were missing from the original capture's
    // request payload but confirmed present on a real NAS-saved note
    // (TinyMCE sets them for image sizing) — added after a live note using
    // them was incorrectly falling back to read-only.
    'img': {'class', 'src', 'border', 'ref', 'adjust', 'width', 'height'},
  };

  static const _allowedStyleProps = {
    'font-family',
    'color',
    'background-color',
    'text-decoration',
    'width',
    'height',
    'text-align',
    // NOT independently verified against a real save/reload — these are
    // generated only by our own image-crop UI (editor.js cmdCropImage),
    // never from arbitrary user CSS, so the risk mirrors text-align's
    // sibling values below rather than truly unconfirmed vocabulary. If a
    // real NoteStation client's own editor ever strips unrecognized style
    // props from a saved <img>, cropped images would lose their crop (but
    // not the image itself, which stays a plain, valid <img>) — never a
    // worse outcome than not having this feature.
    'object-fit',
    'object-position',
    // NOT independently verified — the real fixture note sizes text via a
    // *class* (syno-fontsize-x-large, see _fontSizeClass below), not an
    // inline style. Our own editor now generates this instead (a plain px
    // value, user-typed rather than a handful of named presets) per
    // explicit request. Same worst case as object-fit/object-position
    // above: if the real app's own editor ever strips it on save, the
    // text just reverts to its surrounding size — never corrupted.
    'font-size',
  };

  /// Only this value has been seen for text-decoration (strikethrough).
  static const _allowedTextDecoration = {'line-through'};

  /// Only 'center' was directly captured, but left/right/justify are exactly
  /// what our own editor's justifyLeft/Center/Right commands produce — a
  /// controlled, known output set, not arbitrary user CSS — so the same
  /// confidence extends to the sibling values.
  static const _allowedTextAlign = {'left', 'center', 'right', 'justify'};

  /// Standard CSS object-fit keywords — cmdCropImage only ever emits 'cover'
  /// (and '' to clear it), but the full standard set costs nothing extra to
  /// allow, same reasoning as _allowedTextAlign's siblings.
  static const _allowedObjectFit = {
    'cover',
    'contain',
    'fill',
    'none',
    'scale-down',
  };

  /// Only 'center' is ever produced (cmdCropImage's presets are all
  /// centered, not freeform-positioned) — kept narrow, unlike
  /// _allowedObjectFit, since there's no equivalent "known sibling values"
  /// argument for arbitrary percentage/keyword positions.
  static const _allowedObjectPosition = {'center'};

  /// Bounds cmdFontSize's user-typed px value to a sane range (matches the
  /// picker's own clamp — see note_editor.dart's font-size dialog) without
  /// pinning it to a fixed preset list, since the whole point is letting
  /// the user pick any value.
  static final _fontSizePx = RegExp(r'^([6-9]|[1-9][0-9]|1[0-4][0-9]|150)px$');

  // Hyphen included: real captured class is "syno-fontsize-x-large", which
  // the old `[a-z]+` (no hyphen) rejected — a real value the schema was
  // silently miscategorizing as unconfirmed.
  static final _fontSizeClass = RegExp(r'^syno-fontsize-[a-z-]+$');
  static final _checkboxClass = RegExp(
      r'^syno-notestation-editor-checkbox( syno-notestation-editor-checkbox-checked)?$');
  static final _imageClass = RegExp(r'^syno-notestation-image-object$');

  /// True if [contentHtml] uses only the confirmed-preserved vocabulary —
  /// i.e. it's safe to load into the rich editor and save back without risk
  /// of the stock Note Station app silently stripping something on its next
  /// open.
  ///
  /// [onReject], if given, is called with a human-readable reason for the
  /// *first* disallowed construct found — purely a debugging aid (e.g. to
  /// log why a real NAS note fell back to read-only) and never affects the
  /// return value.
  static bool isRoundTrippable(String contentHtml,
      {void Function(String reason)? onReject}) {
    if (contentHtml.trim().isEmpty) return true;
    final fragment = html_parser.parseFragment(contentHtml);
    return _checkChildren(fragment, onReject);
  }

  static bool _checkChildren(dom.Node node, void Function(String)? onReject) {
    for (final child in node.nodes) {
      if (child is dom.Element) {
        if (!_checkElement(child, onReject)) return false;
        if (!_checkChildren(child, onReject)) return false;
      } else if (child is dom.Text) {
        continue;
      } else {
        // Comments or anything else outside the confirmed vocabulary.
        onReject?.call('non-element, non-text node: ${child.runtimeType}');
        return false;
      }
    }
    return true;
  }

  static bool _checkElement(dom.Element el, void Function(String)? onReject) {
    final tag = (el.localName ?? '').toLowerCase();
    if (!allowedTags.contains(tag)) {
      onReject?.call('disallowed tag <$tag>');
      return false;
    }

    for (final attrName in el.attributes.keys) {
      final name = attrName.toString().toLowerCase();
      if (_allowedGlobalAttrs.contains(name)) continue;
      if (_allowedTagAttrs[tag]?.contains(name) == true) continue;
      onReject?.call('disallowed attribute "$name" on <$tag> '
          '(value: ${el.attributes[attrName]})');
      return false;
    }

    if (tag == 'input') {
      if (el.attributes['type'] != 'image') {
        onReject?.call('<input> with type="${el.attributes['type']}" '
            '(only type="image" allowed)');
        return false;
      }
      final cls = el.attributes['class'] ?? '';
      if (!_checkboxClass.hasMatch(cls)) {
        onReject?.call('<input> with unrecognized class "$cls"');
        return false;
      }
    }

    if (tag == 'span') {
      final cls = el.attributes['class'];
      if (cls != null && cls.isNotEmpty && !_fontSizeClass.hasMatch(cls)) {
        onReject?.call('<span> with unrecognized class "$cls"');
        return false;
      }
    }

    if (tag == 'img') {
      final cls = el.attributes['class'] ?? '';
      if (!_imageClass.hasMatch(cls)) {
        onReject?.call('<img> with unrecognized class "$cls"');
        return false;
      }
    }

    final style = el.attributes['style'];
    if (style != null && style.isNotEmpty) {
      for (final declaration in style.split(';')) {
        final trimmed = declaration.trim();
        if (trimmed.isEmpty) continue;
        final sep = trimmed.indexOf(':');
        if (sep == -1) {
          onReject?.call('unparsable style declaration "$trimmed" on <$tag>');
          return false;
        }
        final prop = trimmed.substring(0, sep).trim().toLowerCase();
        final value = trimmed.substring(sep + 1).trim().toLowerCase();
        if (!_allowedStyleProps.contains(prop)) {
          onReject?.call('disallowed style property "$prop" on <$tag>');
          return false;
        }
        if (prop == 'text-decoration' &&
            !_allowedTextDecoration.contains(value)) {
          onReject?.call('disallowed text-decoration value "$value"');
          return false;
        }
        if (prop == 'text-align' && !_allowedTextAlign.contains(value)) {
          onReject?.call('disallowed text-align value "$value"');
          return false;
        }
        if (prop == 'object-fit' && !_allowedObjectFit.contains(value)) {
          onReject?.call('disallowed object-fit value "$value"');
          return false;
        }
        if (prop == 'object-position' &&
            !_allowedObjectPosition.contains(value)) {
          onReject?.call('disallowed object-position value "$value"');
          return false;
        }
        if (prop == 'font-size' && !_fontSizePx.hasMatch(value)) {
          onReject?.call('disallowed font-size value "$value"');
          return false;
        }
      }
    }

    return true;
  }
}
