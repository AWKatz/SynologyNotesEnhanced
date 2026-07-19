import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:synologynotesenhanceds_enhanced/core/crypto/note_crypto.dart';
import 'package:synologynotesenhanceds_enhanced/core/rich_html/rich_html_schema.dart';

/// Pins the rich-editor eligibility gate against the real "apply every
/// formatting option, save, reload" note (see docs/RICH-TEXT.md) and against
/// constructs we've deliberately excluded from v1 (unconfirmed vocabulary).
void main() {
  late String everythingHtml;

  setUpAll(() {
    final blob =
        File('test/fixtures/encrypted_note_12345.b64').readAsStringSync();
    everythingHtml = NoteCrypto.decrypt(blob, '12345');
  });

  test('empty content is round-trippable', () {
    expect(RichHtmlSchema.isRoundTrippable(''), isTrue);
  });

  test('plain text/div content is round-trippable', () {
    expect(RichHtmlSchema.isRoundTrippable('<div>Hello world</div>'), isTrue);
  });

  test('the real "everything applied" fixture is round-trippable', () {
    expect(RichHtmlSchema.isRoundTrippable(everythingHtml), isTrue);
  });

  test('unchecked and checked checkbox markup is round-trippable', () {
    const html = '<div><input class="syno-notestation-editor-checkbox" '
        'src="webman/3rdparty/NoteStation/images/transparent.gif" '
        'type="image" />todo</div>'
        '<div><input class="syno-notestation-editor-checkbox '
        'syno-notestation-editor-checkbox-checked" '
        'src="webman/3rdparty/NoteStation/images/transparent.gif" '
        'type="image" />done</div>';
    expect(RichHtmlSchema.isRoundTrippable(html), isTrue);
  });

  test('a table with inline width/height style is round-trippable', () {
    const html = '<table style="width: 240px; height: 120px;"><tbody>'
        '<tr><td>&nbsp;</td></tr></tbody></table>';
    expect(RichHtmlSchema.isRoundTrippable(html), isTrue);
  });

  test('a link tag is NOT round-trippable (unconfirmed vocabulary)', () {
    expect(
      RichHtmlSchema.isRoundTrippable('<div><a href="https://x.com">x</a></div>'),
      isFalse,
    );
  });

  test('a real image tag is NOT round-trippable (unconfirmed vocabulary)', () {
    expect(
      RichHtmlSchema.isRoundTrippable('<div><img src="photo.png"/></div>'),
      isFalse,
    );
  });

  test('a code block is NOT round-trippable (unconfirmed vocabulary)', () {
    expect(
      RichHtmlSchema.isRoundTrippable('<pre><code>x</code></pre>'),
      isFalse,
    );
  });

  test('a blockquote is NOT round-trippable (unconfirmed vocabulary)', () {
    expect(
      RichHtmlSchema.isRoundTrippable('<blockquote>quote</blockquote>'),
      isFalse,
    );
  });

  test('text-align inline style is NOT round-trippable (unconfirmed)', () {
    expect(
      RichHtmlSchema.isRoundTrippable('<div style="text-align: center;">x</div>'),
      isFalse,
    );
  });

  test('an unrecognized span class is NOT round-trippable', () {
    expect(
      RichHtmlSchema.isRoundTrippable('<span class="some-other-class">x</span>'),
      isFalse,
    );
  });
}
