# Contributing

Thank you for helping improve the Addis AI Flutter SDK.

## Development setup

1. Fork and clone the repository.
2. Run `flutter pub get`.
3. Create a focused branch for your change.
4. Add or update tests for behavior changes.

Before opening a pull request, run:

```sh
dart format --set-exit-if-changed lib test example/lib tool
dart analyze lib test tool
flutter test
cd example && flutter analyze
```

Do not commit API keys, tokens, generated documentation, build output, or local
environment files. Live smoke tests read `ADDIS_API_KEY` from the environment:

```sh
ADDIS_API_KEY=sk_your_key dart run tool/live_smoke.dart
```

Keep pull requests small, explain user-visible behavior, and document new
public APIs with Dart documentation comments.
