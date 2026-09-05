class MetadataField {
  const MetadataField(this.source, this.name, this.value, {this.namespace});
  final String source;
  final String name;
  final String value;
  final String? namespace;
}

class ImageMetadata {
  const ImageMetadata({this.fields = const [], this.warnings = const []});
  final List<MetadataField> fields;
  final List<String> warnings;
}
