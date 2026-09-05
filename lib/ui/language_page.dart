import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';

import '../l10n/strings.dart';
import '../services/settings_service.dart';

/// First-run gate: no viewer shortcuts or file operations until language is saved.
class LanguagePage extends StatefulWidget {
  const LanguagePage({super.key, required this.service});
  final SettingsService service;

  @override
  State<LanguagePage> createState() => _LanguagePageState();
}

class _LanguagePageState extends State<LanguagePage> with WindowListener {
  late AppLanguage _selected;
  bool _saving = false;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _selected = AppLanguage.fromLocale(
      WidgetsBinding.instance.platformDispatcher.locale,
    );
    windowManager.addListener(this);
  }

  @override
  void dispose() {
    windowManager.removeListener(this);
    super.dispose();
  }

  @override
  void onWindowClose() => windowManager.destroy();

  String text(String source) =>
      AppStrings.translate(source, const [], _selected);

  Future<void> _continue() async {
    setState(() {
      _saving = true;
      _failed = false;
    });
    try {
      await widget.service.chooseLanguage(_selected);
    } catch (_) {
      if (mounted) {
        setState(() {
          _saving = false;
          _failed = true;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: Column(
      children: [
        Row(
          children: [
            Expanded(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onPanStart: (_) => windowManager.startDragging(),
                child: const Padding(
                  padding: EdgeInsets.all(12),
                  child: Text('lime image'),
                ),
              ),
            ),
            IconButton(
              tooltip: text('关闭'),
              onPressed: () => windowManager.destroy(),
              icon: const Icon(Icons.close),
            ),
          ],
        ),
        Expanded(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 440),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Icon(Icons.language, size: 36),
                    const SizedBox(height: 12),
                    Text(
                      text('选择语言'),
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.headlineSmall,
                    ),
                    const SizedBox(height: 6),
                    const Text(
                      '简体中文 · 繁體中文 · English · 日本語 · 한국어',
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 20),
                    for (final language in AppLanguage.values)
                      ListTile(
                        key: ValueKey(language.code),
                        title: Text(language.nativeName),
                        selected: _selected == language,
                        leading: Icon(
                          _selected == language
                              ? Icons.radio_button_checked
                              : Icons.radio_button_unchecked,
                        ),
                        onTap: _saving
                            ? null
                            : () => setState(() => _selected = language),
                      ),
                    if (_failed)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        child: Text(
                          text('保存语言失败，请检查配置目录的写入权限。'),
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.error,
                          ),
                        ),
                      ),
                    const SizedBox(height: 16),
                    FilledButton(
                      key: const ValueKey('confirmLanguage'),
                      onPressed: _saving ? null : _continue,
                      child: Text(text('继续')),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    ),
  );
}
