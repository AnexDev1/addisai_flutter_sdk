/// Base URL for the Addis AI API.
const String baseUrl = 'https://api.addisassistant.com/api/v1';

/// Default API origin used by the official Addis AI SDKs.
const String defaultBaseUrl = 'https://api.addisassistant.com';

/// Public model identifier. Addis AI selects the underlying model.
const String addisChatModel = 'addis-1-alef';

/// Supported target languages for the Addis AI API.
enum Language {
  /// Amharic
  am,

  /// Afan Oromo
  om,

  /// English
  en;

  /// Returns the string value sent to the API (e.g. `"am"`).
  String get value => name;
}

/// Languages supported by speech-to-text.
enum SttLanguage {
  am,
  om,
  en,
  ha,
  sw;

  String get value => name;
}

/// Languages supported by translation.
enum TranslateLanguage {
  am,
  om,
  en;

  String get value => name;
}

/// Voice synthesis output formats.
enum OutputFormat {
  mp3_44100,
  wav_44100,
  pcm_16000;

  String get value => name;
}
