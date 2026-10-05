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
flutter run \
  --dart-define=SUPABASE_URL=https://hpswkgmcxhrrbsnlbbdl.supabase.co \
  --dart-define=SUPABASE_PUBLISHABLE_KEY=<publishable key>
```

Without the two defines the app runs local-only, with no sign-in.

## Code generation and tests

```sh
dart run build_runner build   # after changing lib/data/local/models.dart
flutter analyze
flutter test                  # set ISAR_CORE_LIB=<path to libisar> if the Isar binary download is blocked
```
