import 'package:flutter_test/flutter_test.dart';
import 'package:synologynotesenhanceds_enhanced/core/rich_html/plain_text.dart';

void main() {
  group('htmlToPlainText', () {
    test('decodes &nbsp; left behind by blank lines/cells instead of showing it literally', () {
      expect(htmlToPlainText('<p>Hello</p><table><tr><td>&nbsp;</td></tr></table>'),
          'Hello');
    });

    test('strips tags and collapses whitespace', () {
      expect(htmlToPlainText('<p>Hello</p>\n<p>World</p>'), 'Hello World');
    });

    test('decodes other common entities', () {
      expect(htmlToPlainText('Fish &amp; Chips &lt;tasty&gt;'), 'Fish & Chips <tasty>');
    });

    test('decodes numeric entities', () {
      expect(htmlToPlainText('&#65;&#x42;'), 'AB');
    });

    test('empty content stays empty', () {
      expect(htmlToPlainText('<p>&nbsp;</p>'), '');
    });
  });
}
