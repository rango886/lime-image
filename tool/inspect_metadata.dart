import 'package:limeimage/services/metadata_service.dart';

/// `dart run tool/inspect_metadata.dart <image>`
Future<void> main(List<String> args) async {
  if (args.length != 1) {
    print('Usage: dart run tool/inspect_metadata.dart <image>');
    return;
  }
  final service = MetadataService();
  final watch = Stopwatch()..start();
  final result = await service.load(args.single);
  print('Cold worker + read: ${watch.elapsedMilliseconds} ms');
  for (final field in result!.fields) {
    print('[${field.source}] ${field.name}: ${field.value}');
  }
  for (final warning in result.warnings) {
    print('Warning: $warning');
  }
  watch.reset();
  await service.load(args.single);
  print('Cached: ${watch.elapsedMicroseconds} us');
}
