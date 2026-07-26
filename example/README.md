# Addis AI Flutter example

This app demonstrates chat completions, durable voice generation, and realtime
voice sessions with `addis_ai_sdk`.

Run it without placing a secret in source code:

```sh
flutter pub get
flutter run --dart-define=ADDIS_API_KEY=sk_your_key
```

For a production consumer application, route requests through your backend
instead of embedding a privileged API key in the compiled app.
