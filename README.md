# Finance Buddy

An Android-first Flutter personal finance app for tracking bank accounts, mobile money, cash, savings, and other money accounts. Create named accounts with opening balances, then record income and expenses against any account. All accounts currently use GHS.

## Daily flow

1. Create an account for each bank account, wallet, or cash balance.
2. Add income or an expense with an account, amount, optional category, note, and date.
3. Enable **Settings → Detect transaction notifications** and grant Finance Buddy notification access in Android settings. Allow notification permission for background reminders.
4. New SMS and banking app notifications containing financial transaction text become suggestions. While the app is open, a confirmation form appears. In the background, tap the generic reminder notification to open the app and review pending suggestions.
5. Check or correct the details and save. **Later** leaves a suggestion in the inbox; **Ignore** dismisses it. No detected message changes a balance until confirmed.

Account routing rules suggest an account/category; they never save a transaction automatically. Existing accounts and ledger records are preserved. The dashboard shows total account balances, not a complete calculation of net worth. Opening balances and direct balance adjustments are not income.

## Detection and privacy

- Detection is optional and Android-only. Android notification access can expose notifications from all apps; the native listener filters financial-looking text before storing candidates locally. Disable detection in Settings or revoke notification access in Android settings.
- The listener reads newly posted notification text, including SMS notifications. It does not receive SMS directly when the messaging app suppresses its notification. Redacted notifications, some device configurations, work profiles, and unsupported message formats can prevent detection.
- Optional **Find transactions in SMS** reads up to 1,000 inbox messages with SMS permission and queues them for confirmation. Notification detection does not need SMS inbox permission.
- Notification candidates survive process restarts in app-private storage until acknowledged into the SQLite review queue. Repeated delivery of the same source notification/content and repeat inbox scans are deduplicated. An inbox SMS and an app notification can still describe the same payment with different identifiers or text: check suggestions before saving both. A manually recorded payment can also reappear as a suggestion.
- Amounts are suggestions, not authoritative bank data. OTP/failed/pending/promotional messages are filtered where recognized. Foreign currency suggestions require you to enter their GHS equivalent explicitly; no automatic conversion occurs.
- No backend, analytics, or network integration is included. Backups are disabled. Records and pending message text are stored locally in the app sandbox, without application-level database encryption. Uninstalling or clearing app data deletes them.
- Android restricts launching activities from the background, so the app uses a tap-to-open reminder instead of an overlay. Notifications show generic review text rather than payment details.

## Run and verify

Install Flutter and the Android SDK, then:

```sh
flutter pub get
flutter analyze
flutter test
flutter run
flutter build apk --debug
```

Use an Android phone or emulator for notification and inbox features. Enable notification access and send a transaction-like SMS (for example, `You received GHS 150 from Ama. Ref: ABC123`). Confirm it once, then verify that the chosen account changes by the entered amount and the suggestion disappears. Repeat with the app backgrounded and reopened, detection disabled, notification permission denied, and a nonfinancial/OTP message.

Google Play distribution requires checking the applicable SMS permission policy; inbox access may require a declaration or a different import approach. The current release Gradle configuration still uses debug signing and is for development, not store release.

## Architecture

- `lib/data`: SQLite accounts, ledger, review queue, and atomic balance updates
- `lib/services`: SMS parsing, manual inbox scans, and the notification platform bridge
- `lib/state`: Provider application state and review confirmation
- `lib/ui`: accounts dashboard, transaction forms/history, suggestions, and settings
- `android/.../TransactionNotificationListener.kt`: native notification filtering, durable queue, and background reminders
- `test`: parser, database workflow, and form tests
