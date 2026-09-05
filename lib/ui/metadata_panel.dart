import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../l10n/strings.dart';
import '../models/image_metadata.dart';

class MetadataPanel extends StatefulWidget {
  const MetadataPanel({super.key, required this.data});
  final ImageMetadata? data;
  @override
  State<MetadataPanel> createState() => _MetadataPanelState();
}

class _MetadataPanelState extends State<MetadataPanel> {
  final _collapsed = <String>{};
  final _expanded = <MetadataField>{};

  bool _isTechnical(MetadataField f) =>
      f.namespace == 'http://ns.adobe.com/xmp/note/' ||
      f.namespace == 'http://ns.adobe.com/xap/1.0/mm/' ||
      f.namespace == 'http://ns.adobe.com/xap/1.0/sType/ResourceRef#' ||
      f.name.contains('Padding') ||
      f.name.contains('Offset') ||
      f.name.contains('MakerNote');

  @override
  void didUpdateWidget(covariant MetadataPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.data, widget.data)) _expanded.clear();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final label = theme.textTheme.labelSmall;
    final muted = label?.copyWith(color: scheme.outline);
    final valueStyle = label?.copyWith(color: scheme.onSurface);
    final data = widget.data;
    if (data == null) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(13, 8, 13, 0),
        child: Text(lt('读取中…'), style: muted),
      );
    }
    final fields = data.fields.where((f) => !_isTechnical(f)).toList();
    // Flat, lazy rows: styling must not add work to image loading or navigation.
    final rows = <Object>[...data.warnings];
    for (final source in fields.map((f) => f.source).toSet()) {
      final group = fields.where((f) => f.source == source).toList();
      rows.add((source, group.length));
      if (!_collapsed.contains(source)) rows.addAll(group);
    }
    if (fields.isEmpty && data.warnings.isEmpty) {
      rows.add(lt('无可显示的元数据'));
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(13, 8, 13, 0),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Divider(height: 1, color: scheme.outlineVariant),
          const SizedBox(height: 5),
          SizedBox(
            height: fields.isEmpty ? 48 : 220,
            child: ListView.builder(
              padding: EdgeInsets.zero,
              primary: false,
              itemCount: rows.length,
              itemBuilder: (context, index) {
                final row = rows[index];
                if (row is String) {
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Text(row, style: muted),
                  );
                }
                if (row is (String, int)) {
                  final (source, count) = row;
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 3),
                    child: TextButton(
                      style: TextButton.styleFrom(
                        foregroundColor: scheme.primary,
                        minimumSize: const Size(0, 24),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 2,
                          vertical: 3,
                        ),
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        visualDensity: VisualDensity.standard,
                        alignment: Alignment.centerLeft,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ),
                      onPressed: () => setState(() {
                        if (!_collapsed.remove(source)) _collapsed.add(source);
                      }),
                      child: Row(
                        children: [
                          Icon(
                            _collapsed.contains(source)
                                ? Icons.chevron_right_rounded
                                : Icons.expand_more_rounded,
                            size: 14,
                          ),
                          const SizedBox(width: 3),
                          Text(
                            '${source == 'PNG Text' ? lt('PNG 文本') : source} ($count)',
                            style: label?.copyWith(
                              color: scheme.primary,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                }
                final field = row as MetadataField;
                final long = field.value.length > 300;
                return Padding(
                  padding: const EdgeInsets.only(left: 3, bottom: 6, right: 2),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Tooltip(
                              message: field.namespace == null
                                  ? field.name
                                  : '${field.name}\n${field.namespace}',
                              child: Text(
                                field.name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: muted,
                              ),
                            ),
                          ),
                          _action(
                            context,
                            icon: Icons.copy_rounded,
                            tooltip: lt('复制'),
                            onPressed: () => Clipboard.setData(
                              ClipboardData(text: field.value),
                            ),
                          ),
                        ],
                      ),
                      if (long && !_expanded.contains(field))
                        Text(
                          field.value,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: valueStyle,
                        )
                      else
                        SelectableText(field.value, style: valueStyle),
                      if (long)
                        TextButton(
                          style: TextButton.styleFrom(
                            minimumSize: const Size(0, 22),
                            padding: const EdgeInsets.symmetric(vertical: 2),
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            visualDensity: VisualDensity.standard,
                            textStyle: label,
                          ),
                          onPressed: () => setState(() {
                            if (!_expanded.remove(field)) _expanded.add(field);
                          }),
                          child: Text(
                            lt(_expanded.contains(field) ? '收起' : '展开全文'),
                          ),
                        ),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _action(
    BuildContext context, {
    required IconData icon,
    required String tooltip,
    required VoidCallback onPressed,
  }) {
    final scheme = Theme.of(context).colorScheme;
    return IconButton(
      tooltip: tooltip,
      onPressed: onPressed,
      icon: Icon(icon, size: 13),
      style: IconButton.styleFrom(
        fixedSize: const Size(22, 22),
        minimumSize: const Size(22, 22),
        maximumSize: const Size(22, 22),
        padding: EdgeInsets.zero,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        visualDensity: VisualDensity.standard,
        foregroundColor: scheme.outline,
        backgroundColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(5)),
      ),
    );
  }
}
