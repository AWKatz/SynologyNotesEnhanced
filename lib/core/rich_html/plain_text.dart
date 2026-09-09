/// Converts note HTML content into a plain-text preview: strips tags, decodes
/// HTML entities (so an empty `<td>&nbsp;</td>` — how the editor pads blank
/// lines/cells, see assets/editor/editor.js — doesn't leave a literal
/// "&nbsp;" behind), and collapses whitespace.
String htmlToPlainText(String html) {
  final noTags = html.replaceAll(RegExp(r'<[^>]+>'), ' ');
  final decoded = _decodeHtmlEntities(noTags);
  return decoded.replaceAll(RegExp(r'\s+'), ' ').trim();
}

const _namedEntities = <String, String>{
  'nbsp': ' ',
  'amp': '&',
  'lt': '<',
  'gt': '>',
  'quot': '"',
  'apos': "'",
};

final _entityPattern = RegExp(r'&(#x[0-9a-fA-F]+|#[0-9]+|[a-zA-Z]+);');

String _decodeHtmlEntities(String text) {
  return text.replaceAllMapped(_entityPattern, (m) {
    final entity = m.group(1)!;
    if (entity.startsWith('#x') || entity.startsWith('#X')) {
      final code = int.tryParse(entity.substring(2), radix: 16);
      return code != null ? String.fromCharCode(code) : m.group(0)!;
    }
    if (entity.startsWith('#')) {
      final code = int.tryParse(entity.substring(1));
      return code != null ? String.fromCharCode(code) : m.group(0)!;
    }
    return _namedEntities[entity] ?? m.group(0)!;
  });
}
