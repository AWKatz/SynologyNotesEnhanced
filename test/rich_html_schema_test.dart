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

  test('a line break (blank line from the editor\'s Enter key) is round-trippable', () {
    expect(
      RichHtmlSchema.isRoundTrippable('<div>Line one</div><div><br></div>'),
      isTrue,
    );
  });

  test('a hyperlink is round-trippable (verified via HAR capture)', () {
    expect(
      RichHtmlSchema.isRoundTrippable(
          '<div><a href="http://hyperlinked">hyperlinked.com</a></div>'),
      isTrue,
    );
  });

  test('an uploaded image tag is round-trippable (verified via HAR capture)',
      () {
    const html = '<div><img class="syno-notestation-image-object" '
        'src="webman/3rdparty/NoteStation/images/transparent.gif" '
        'border="0" ref="cmVmMTIz" adjust="true" /></div>';
    expect(RichHtmlSchema.isRoundTrippable(html), isTrue);
  });

  test(
      'an uploaded image tag with width/height is round-trippable '
      '(regression: real NAS note with a sized image was falling back to '
      'read-only)', () {
    const html = '<div><img class="syno-notestation-image-object" '
        'src="webman/3rdparty/NoteStation/images/transparent.gif" '
        'border="0" ref="cmVmMTIz" adjust="true" width="200" '
        'height="200" /></div>';
    expect(RichHtmlSchema.isRoundTrippable(html), isTrue);
  });

  test(
      'a cropped image (object-fit/object-position, from cmdCropImage) is '
      'round-trippable', () {
    const html = '<div><img class="syno-notestation-image-object" '
        'src="webman/3rdparty/NoteStation/images/transparent.gif" '
        'border="0" ref="cmVmMTIz" adjust="true" width="200" height="200" '
        'style="object-fit: cover; object-position: center;" /></div>';
    expect(RichHtmlSchema.isRoundTrippable(html), isTrue);
  });

  test('an image with an arbitrary object-position is NOT round-trippable',
      () {
    const html = '<div><img class="syno-notestation-image-object" '
        'src="webman/3rdparty/NoteStation/images/transparent.gif" '
        'ref="cmVmMTIz" style="object-fit: cover; object-position: '
        '30% 70%;" /></div>';
    expect(RichHtmlSchema.isRoundTrippable(html), isFalse);
  });

  test('an image tag with an unrecognized class is NOT round-trippable', () {
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

  test('text-align inline style is round-trippable (verified via HAR capture)',
      () {
    expect(
      RichHtmlSchema.isRoundTrippable(
          '<div style="text-align: center;">x</div>'),
      isTrue,
    );
  });

  test('an unrecognized text-align value is NOT round-trippable', () {
    expect(
      RichHtmlSchema.isRoundTrippable(
          '<div style="text-align: initial;">x</div>'),
      isFalse,
    );
  });

  test('the x-large font-size class is round-trippable (regex fix)', () {
    expect(
      RichHtmlSchema.isRoundTrippable(
          '<span class="syno-fontsize-x-large">big</span>'),
      isTrue,
    );
  });

  test(
      'the small/medium/large font-size classes are round-trippable '
      '(reading notes that already use them — our own editor now produces '
      'a px style instead, see below)', () {
    for (final size in ['small', 'medium', 'large']) {
      expect(
        RichHtmlSchema.isRoundTrippable(
            '<span class="syno-fontsize-$size">text</span>'),
        isTrue,
        reason: 'syno-fontsize-$size should round-trip',
      );
    }
  });

  test(
      'a user-typed px font-size (from cmdFontSize) is round-trippable',
      () {
    expect(
      RichHtmlSchema.isRoundTrippable(
          '<span style="font-size: 18px;">text</span>'),
      isTrue,
    );
  });

  test('font-size values outside the accepted range are NOT round-trippable',
      () {
    for (final value in ['4px', '151px', '16pt', '2em']) {
      expect(
        RichHtmlSchema.isRoundTrippable(
            '<span style="font-size: $value;">text</span>'),
        isFalse,
        reason: '$value should be rejected',
      );
    }
  });

  test('an unrecognized span class is NOT round-trippable', () {
    expect(
      RichHtmlSchema.isRoundTrippable('<span class="some-other-class">x</span>'),
      isFalse,
    );
  });
}
