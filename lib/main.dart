import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'data/app_database.dart';
import 'services/sms_scanner.dart';
import 'services/sms_source.dart';
import 'services/transaction_parser.dart';
import 'state/app_state.dart';
import 'ui/home_shell.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  final database = AppDatabase();
  final scanner = SmsScanner(database, AndroidSmsSource(), TransactionParser());
  runApp(FinanceBuddyApp(state: AppState(database, scanner)));
}

class FinanceBuddyApp extends StatefulWidget {
  const FinanceBuddyApp({super.key, required this.state});
  final AppState state;

  @override
  State<FinanceBuddyApp> createState() => _FinanceBuddyAppState();
}

class _FinanceBuddyAppState extends State<FinanceBuddyApp> {
  @override
  void initState() {
    super.initState();
    widget.state.initialize();
  }

  @override
  Widget build(BuildContext context) => ChangeNotifierProvider.value(
        value: widget.state,
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          title: 'Finance Buddy',
          theme: ThemeData(
            colorScheme: ColorScheme.fromSeed(
                seedColor: const Color(0xff176b4d),
                brightness: Brightness.light),
            scaffoldBackgroundColor: const Color(0xfff4f7f5),
            useMaterial3: true,
            cardTheme:
                const CardThemeData(elevation: 0, margin: EdgeInsets.zero),
            inputDecorationTheme:
                const InputDecorationTheme(border: OutlineInputBorder()),
          ),
          home: const HomeShell(),
        ),
      );
}
