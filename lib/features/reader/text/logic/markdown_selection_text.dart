import 'package:markdown/markdown.dart' as markdown;

/// Plain text corresponding to the reader's rendered Markdown. Used only for
/// explicit full-document Copy; normal range copying is owned by SelectionArea.
/// Kept top-level so large documents can be parsed with compute/isolate.
String markdownSelectionText(String source) {
  final document = markdown.Document(
    extensionSet: markdown.ExtensionSet.gitHubFlavored,
    encodeHtml: false,
  );
  final nodes = document.parseLines(source.split('\n'));
  final output = StringBuffer();
  void write(markdown.Node node) {
    if (node is markdown.Text) {
      output.write(node.text);
      return;
    }
    if (node is! markdown.Element) return;
    if (node.tag == 'br') {
      output.writeln();
      return;
    }
    if (node.tag == 'img') {
      output.write(node.attributes['alt'] ?? 'External image blocked');
      return;
    }
    final children = node.children ?? const <markdown.Node>[];
    for (var i = 0; i < children.length; i++) {
      if (node.tag == 'tr' && i > 0) output.write('\t');
      write(children[i]);
    }
    if (const <String>{'p', 'h1', 'h2', 'h3', 'h4', 'h5', 'h6',
      'li', 'pre', 'tr', 'blockquote', 'hr'}.contains(node.tag)) {
      output.writeln();
    }
  }
  for (final node in nodes) {
    write(node);
  }
  return output.toString().trimRight();
}
