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

  /// 'line-through' (strikethrough) was the original captured value.
  /// 'underline' is VERIFIED separately via a live round-trip test against a
  /// real NAS (2026-08-26): created a note with an inline
  /// `text-decoration: underline` span via the API directly (bypassing
  /// editor.js's sanitizer, which would otherwise strip it before send),
  /// fetched it back, and DSM returned the style unchanged — confirming the
  /// server round-trips this property's values verbatim rather than
  /// allowlisting specific ones itself.
  static const _allowedTextDecoration = {'line-through', 'underline'};

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

  /// Matches a bare numeric font-size value with its unit, e.g. "12pt" or
  /// "18.666666px" — the latter a WebKit `getComputedStyle` artifact from
  /// pasted content (≈14pt × 4/3), not anything a user or this app's editor
  /// wrote deliberately.
  static final _fontSizeValue = RegExp(r'^(\d+(?:\.\d+)?)(px|pt)$');

  /// True for a font-size value confirmed safe to preserve: cmdFontSize's
  /// own user-typed px output (bounded to the picker's clamp — see
  /// note_editor.dart's font-size dialog), the same numeric range in pt, or
  /// the parent-inheriting keyword `inherit`. Unlike every other property
  /// this schema gates, font-size on an *encrypted* note is never at risk
  /// from NoteStation's own server-side sanitizer — encrypted content is an
  /// opaque ciphertext blob to the server, never parsed as HTML there — so
  /// the only thing that could mangle a pt/decimal value is this app's own
  /// editor.js, which simply leaves it untouched rather than rewriting it.
  static bool _isAllowedFontSize(String value) {
    if (value == 'inherit') return true;
    final match = _fontSizeValue.firstMatch(value);
    if (match == null) return false;
    final n = double.tryParse(match.group(1)!);
    return n != null && n >= 6 && n <= 150;
  }

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

  /// Debugging aid: walks the *entire* tree (unlike [isRoundTrippable],
  /// which stops at the first violation) and returns every distinct
  /// structural reason it's not round-trippable — tag/attribute/property
  /// names only, deliberately never attribute values or text content, since
  /// real notes can hold sensitive user data. Lets a single note diagnose
  /// every remaining schema gap in one pass instead of one rebuild per fix.
  static Set<String> debugAllRejectionCategories(String contentHtml) {
    final reasons = <String>{};
    if (contentHtml.trim().isEmpty) return reasons;
    final fragment = html_parser.parseFragment(contentHtml);
    void walk(dom.Node node) {
      for (final child in node.nodes) {
        if (child is! dom.Element) continue;
        final tag = (child.localName ?? '').toLowerCase();
        if (!allowedTags.contains(tag)) {
          reasons.add('disallowed tag <$tag>');
          walk(child);
          continue;
        }
        for (final attrName in child.attributes.keys) {
          final name = attrName.toString().toLowerCase();
          if (_allowedGlobalAttrs.contains(name)) continue;
          if (_allowedTagAttrs[tag]?.contains(name) == true) continue;
          if (name.startsWith('data-')) continue;
          if (name == 'id') continue;
          reasons.add('disallowed attribute "$name" on <$tag>');
        }
        if (tag == 'input') {
          if (child.attributes['type'] != 'image') {
            reasons.add('<input> with disallowed type');
          } else {
            final cls = child.attributes['class'] ?? '';
            if (!_checkboxClass.hasMatch(cls)) {
              reasons.add('<input> with unrecognized class');
            }
          }
        }

        if (tag == 'span') {
          final cls = child.attributes['class'];
          if (cls != null && cls.isNotEmpty && !_fontSizeClass.hasMatch(cls)) {
            reasons.add('<span> with unrecognized class');
          }
        }

        if (tag == 'img') {
          final cls = child.attributes['class'] ?? '';
          if (!_imageClass.hasMatch(cls)) {
            reasons.add('<img> with unrecognized class');
          }
        }

        final style = child.attributes['style'];
        if (style != null && style.isNotEmpty) {
          for (final declaration in style.split(';')) {
            final trimmed = declaration.trim();
            if (trimmed.isEmpty) continue;
            final sep = trimmed.indexOf(':');
            if (sep == -1) {
              reasons.add('unparsable style declaration on <$tag>');
              continue;
            }
            final prop = trimmed.substring(0, sep).trim().toLowerCase();
            if (prop == 'white-space' || prop == '-webkit-tap-highlight-color') {
              continue;
            }
            final value = trimmed.substring(sep + 1).trim().toLowerCase();
            if (!_allowedStyleProps.contains(prop)) {
              reasons.add('disallowed style property "$prop" on <$tag>');
              continue;
            }
            if (prop == 'text-decoration' &&
                !_allowedTextDecoration.contains(value)) {
              reasons.add('disallowed text-decoration value on <$tag>');
            }
            if (prop == 'text-align' && !_allowedTextAlign.contains(value)) {
              reasons.add('disallowed text-align value on <$tag>');
            }
            if (prop == 'object-fit' && !_allowedObjectFit.contains(value)) {
              reasons.add('disallowed object-fit value on <$tag>');
            }
            if (prop == 'object-position' &&
                !_allowedObjectPosition.contains(value)) {
              reasons.add('disallowed object-position value on <$tag>');
            }
            // The value itself (a CSS length/keyword) isn't sensitive note
            // content, unlike text or href/src — surfacing it here (unlike
            // every other category above) is what lets a real rejection get
            // diagnosed without needing to see the note's actual body.
            if (prop == 'font-size' && !_isAllowedFontSize(value)) {
              reasons.add('disallowed font-size value "$value" on <$tag>');
            }
          }
        }
        walk(child);
      }
    }

    walk(fragment);
    return reasons;
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
      // data-* attributes are HTML-spec custom metadata: no browser or CSS
      // rule ever gives one rendering/formatting meaning, unlike an unknown
      // tag or style property might. Real-world notes pick these up as
      // leftover cruft from pasting rich text copied out of Word/Google
      // Docs/Pages/Notes (e.g. a `data-tt` paragraphStyle blob) — editor.js's
      // sanitizeElement already silently strips any attribute outside its
      // own allowlist the instant the note is edited, so rejecting the whole
      // note over one here just blocks editing without preventing anything;
      // let it through and rely on that same silent strip.
      if (name.startsWith('data-')) continue;
      // Same reasoning as data-*: a bare `id` has no rendering effect here —
      // neither the read view's flutter_widget_from_html_core nor the
      // WebView editor's editor.css define any selector keyed to arbitrary
      // pasted IDs (`hr`'s TinyMCE-generated id is the one case that *is*
      // meaningful, already covered by _allowedTagAttrs above). Also common
      // Word/Google Docs/Pages paste cruft.
      if (name == 'id') continue;
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
        // white-space is common Word/Google Docs/Pages paste cruft (used to
        // preserve literal spacing from the source doc) and, unlike the
        // other properties here, genuinely affects rendering — but
        // editor.js's sanitizer already silently drops it the instant a note
        // enters edit mode regardless of this check, so rejecting the whole
        // note over it protects nothing; it only blocks editing. Letting it
        // through means that spacing visually collapses to normal on first
        // edit (cosmetic only — no note content is lost).
        if (prop == 'white-space') continue;
        // WebKit's own vendor-prefixed property for disabling the mobile tap
        // highlight overlay — pure browser chrome, not note content, and
        // meaningless to both the read view (flutter_widget_from_html_core)
        // and editor.css. Common paste cruft from anything copied out of a
        // WebKit-based app or mobile browser. Same reasoning and same
        // outcome as white-space above: editor.js's sanitizer already drops
        // it on edit regardless, so gating the whole note on it protects
        // nothing.
        if (prop == '-webkit-tap-highlight-color') continue;
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
        if (prop == 'font-size' && !_isAllowedFontSize(value)) {
          onReject?.call('disallowed font-size value "$value"');
          return false;
        }
      }
    }

    return true;
  }
}
