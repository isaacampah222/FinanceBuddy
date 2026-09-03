# Finance Buddy

An Android-first Flutter app that reads transaction SMS messages only when the
user taps **Scan SMS & Sync**. Parsing, rules, deduplication, and SQLite storage
all stay on the device; the app contains no backend or network integration.

## Run

1. Install Flutter 3.22+ and an Android SDK.
2. Run `flutter pub get`.
3. Connect an Android device and run `flutter run`.

SMS inbox access only works on Android. Google Play restricts SMS permissions,
so distribution through Play may require a policy-compliant declaration or a
different distribution method.

## Architecture

- `lib/data`: SQLite schema and atomic ledger operations
- `lib/services`: SMS gateway, parser, and scanner orchestration
- `lib/state`: Provider-backed application state
- `lib/ui`: Dashboard, ledger, review queue, and routing rules

The database seeds Bank, Mobile Money, Cash, and common categories. Each SMS is
identified by SHA-256 of its native ID, sender, timestamp, and body. Transaction
insert, hash insert, and balance update are committed atomically.
