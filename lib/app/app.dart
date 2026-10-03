import 'package:field_ops/app/router.dart';
import 'package:field_ops/app/session_cubit.dart';
import 'package:field_ops/data/api/fake_field_ops_api.dart';
import 'package:field_ops/data/local/tenant_database.dart';
import 'package:field_ops/l10n/l10n.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:go_router/go_router.dart';

class FieldOpsApp extends StatefulWidget {
  const FieldOpsApp({required this.api, this.locale, this.openDatabase, super.key});

  final FakeFieldOpsApi api;
  final Locale? locale;

  /// Overridden in tests with an in-memory database.
  final TenantDatabase Function(String tenantId)? openDatabase;

  @override
  State<FieldOpsApp> createState() => _FieldOpsAppState();
}

class _FieldOpsAppState extends State<FieldOpsApp> {
  late final SessionCubit _session = SessionCubit(widget.api, openDatabase: widget.openDatabase);
  late final GoRouter _router = createRouter(_session);
  late final LocaleController _locale = LocaleController(widget.locale);

  @override
  void dispose() {
    _router.dispose();
    _locale.dispose();
    _session.close();
    super.dispose();
  }

  ThemeData _theme(Brightness brightness) {
    final scheme = ColorScheme.fromSeed(seedColor: const Color(0xFF1F5F99), brightness: brightness);
    return ThemeData(
      colorScheme: scheme,
      appBarTheme: AppBarTheme(backgroundColor: scheme.surface, scrolledUnderElevation: 0, centerTitle: false),
      cardTheme: CardThemeData(
        elevation: 0,
        color: scheme.surfaceContainerLow,
        margin: const EdgeInsets.only(bottom: 8),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
      ),
      filledButtonTheme: FilledButtonThemeData(style: FilledButton.styleFrom(minimumSize: const Size(0, 48))),
    );
  }

  @override
  Widget build(BuildContext context) => MultiRepositoryProvider(
    providers: [
      RepositoryProvider.value(value: widget.api),
      RepositoryProvider.value(value: _locale),
    ],
    child: BlocProvider.value(
      value: _session,
      child: ListenableBuilder(
        listenable: _locale.locale,
        builder: (context, _) => MaterialApp.router(
          onGenerateTitle: (context) => context.l10n.appTitle,
          debugShowCheckedModeBanner: false,
          theme: _theme(Brightness.light),
          darkTheme: _theme(Brightness.dark),
          locale: _locale.locale.value,
          supportedLocales: AppLocalizations.supportedLocales,
          localizationsDelegates: const [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          routerConfig: _router,
        ),
      ),
    ),
  );
}

/// Holds the chosen app language; `null` follows the device. Not itself a
/// Listenable, so it can be provided like any other dependency.
class LocaleController {
  LocaleController(Locale? initial) : locale = ValueNotifier(initial);

  final ValueNotifier<Locale?> locale;

  void toggle(Locale current) => locale.value = Locale(current.languageCode == 'ar' ? 'en' : 'ar');

  void dispose() => locale.dispose();
}
