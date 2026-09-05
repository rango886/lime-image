import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import '../l10n/strings.dart';
import 'language_page.dart';

import '../models/enums.dart';
import '../services/settings_service.dart';
import '../state/viewer_state.dart';
import 'theme.dart';
import 'viewer_page.dart';

class LimeApp extends StatelessWidget {
  const LimeApp({super.key, required this.state});
  final ViewerState state;

  @override
  Widget build(BuildContext context) {
    final SettingsService svc = state.settingsService;
    return AnimatedBuilder(
      animation: svc,
      builder: (context, _) {
        final cfg = svc.settings;
        return MaterialApp(
          debugShowCheckedModeBanner: false,
          title: 'lime image',
          locale:
              (cfg.language ??
                      AppLanguage.fromLocale(
                        WidgetsBinding.instance.platformDispatcher.locale,
                      ))
                  .locale,
          supportedLocales: AppLanguage.values.map((v) => v.locale),
          localizationsDelegates: GlobalMaterialLocalizations.delegates,
          themeMode: switch (cfg.theme) {
            ThemePref.system => ThemeMode.system,
            ThemePref.light => ThemeMode.light,
            ThemePref.dark => ThemeMode.dark,
          },
          theme: LimeTheme.build(
            Brightness.light,
            cfg.accentColor,
            radius: cfg.cornerRadius,
            fontScale: cfg.uiFontScale,
          ),
          darkTheme: LimeTheme.build(
            Brightness.dark,
            cfg.accentColor,
            radius: cfg.cornerRadius,
            fontScale: cfg.uiFontScale,
          ),
          home: cfg.language == null
              ? LanguagePage(service: svc)
              : ViewerScope(
                  state: state,
                  child: AnimatedBuilder(
                    animation: state,
                    builder: (context, _) => Material(
                      color: Theme.of(context).scaffoldBackgroundColor,
                      child: ViewerPage(state: state),
                    ),
                  ),
                ),
        );
      },
    );
  }
}
