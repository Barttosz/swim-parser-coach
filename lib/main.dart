import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';
import 'package:sqflite_common_ffi_web/sqflite_ffi_web.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:provider/provider.dart';
import 'core/design_system/app_theme.dart';
import 'features/athletes/athlete_repository.dart';
import 'features/session/session_repository.dart';
import 'features/session/session_input_screen.dart';
import 'features/session/session_history_screen.dart';
import 'features/calendar/calendar_screen.dart';
import 'features/calendar/basic_calendar_screen.dart';
import 'features/calendar/calendar_event_repository.dart';
import 'features/settings/settings_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  if (kIsWeb) {
    databaseFactory = databaseFactoryFfiWeb;
  }

  // Inicjalizacja repozytoriów
  final athleteRepo = AthleteRepository();
  final sessionRepo = SessionRepository();
  final eventRepo = CalendarEventRepository();

  // Inicjalizacja bazy danych
  await athleteRepo.init();
  await sessionRepo.init();
  await eventRepo.init();

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: athleteRepo),
        ChangeNotifierProvider.value(value: sessionRepo),
        ChangeNotifierProvider.value(value: eventRepo),
      ],
      child: const SwimParserApp(),
    ),
  );
}

class SwimParserApp extends StatelessWidget {
  const SwimParserApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Parser Treningów Pływackich',
      theme: AppTheme.light,
      debugShowCheckedModeBanner: false,
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: const [
        Locale('pl', 'PL'),
        Locale('en', 'US'),
      ],
      locale: const Locale('pl', 'PL'),
      initialRoute: '/',
      routes: {
        '/': (_) => const SessionInputScreen(),
        '/settings': (_) => const SettingsScreen(),
        '/history': (_) => const SessionHistoryScreen(),
        '/calendar': (_) => const BasicCalendarScreen(),
        '/calendar/grid': (_) => const CalendarScreen(),
      },
    );
  }
}
