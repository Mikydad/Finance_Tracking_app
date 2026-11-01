# Finance app (Flutter)

iPhone first, Android later. Local-first: every write goes to Isar (community fork) and an
outbox, then syncs to Supabase with `sync_push` / `sync_pull`.

```
lib/
  core/          config (--dart-define), money helpers (santim <-> birr)
  data/local/    Isar collections mirroring the synced tables, outbox, sync cursor
  data/repositories/  the only code that touches Isar
  domain/        app-level models
  features/      auth, home (more per phase)
```

## Run

```sh
flutter pub get
flutter run
```

The app connects to the project's hosted Supabase by default (URL and publishable key in
`lib/core/config.dart`), so Xcode's Run button works too. To use another Supabase project, pass
`--dart-define=SUPABASE_URL=...` and `--dart-define=SUPABASE_PUBLISHABLE_KEY=...`; passing both as
empty strings runs the app local-only, with no sign-in.

## Code generation and tests

```sh
dart run build_runner build   # after changing lib/data/local/models.dart
flutter analyze
flutter test                  # set ISAR_CORE_LIB=<path to libisar> if the Isar binary download is blocked
```
