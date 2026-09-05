import 'package:xml/xml.dart';

import '../../models/image_metadata.dart';

List<MetadataField> parseXmp(String text) {
  if (text.contains('<!DOCTYPE') || text.contains('<!ENTITY')) {
    throw const FormatException('不允许 XMP DTD/实体声明');
  }
  final doc = XmlDocument.parse(text);
  const rdf = 'http://www.w3.org/1999/02/22-rdf-syntax-ns#';
  const xmlns = 'http://www.w3.org/2000/xmlns/';
  final fields = <MetadataField>[];
  var nodes = 0;
  void add(MetadataField field) {
    if (fields.length >= 2048) throw const FormatException('XMP 字段超过安全限制');
    fields.add(field);
  }

  void walk(XmlElement element, String path, int depth) {
    if (depth > 32 || ++nodes > 8192) {
      throw const FormatException('XMP 结构超过安全限制');
    }
    for (final attribute in element.attributes) {
      final ns = attribute.name.namespaceUri;
      if (ns == xmlns || attribute.name.qualified == 'xmlns' || ns == rdf) {
        continue;
      }
      add(
        MetadataField(
          'XMP',
          '$path/@${attribute.name.qualified}',
          attribute.value,
          namespace: ns,
        ),
      );
    }
    final children = element.childElements.toList();
    if (children.isEmpty) {
      final value =
          element.getAttribute('resource', namespaceUri: rdf) ??
          element.innerText;
      if (value.trim().isNotEmpty) {
        add(
          MetadataField(
            'XMP',
            path,
            value,
            namespace: element.name.namespaceUri,
          ),
        );
      }
    } else {
      var index = 0;
      for (final child in children) {
        final name = child.name.namespaceUri == rdf && child.name.local == 'li'
            ? 'li[${++index}]'
            : child.name.qualified;
        walk(child, path.isEmpty ? name : '$path/$name', depth + 1);
      }
    }
  }

  for (final element in doc.descendants.whereType<XmlElement>()) {
    if (element.name.namespaceUri == rdf &&
        element.name.local == 'Description' &&
        element.parentElement?.name.namespaceUri == rdf &&
        element.parentElement?.name.local == 'RDF') {
      walk(element, '', 0);
    }
  }
  return fields;
}
