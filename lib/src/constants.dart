/// Base URL for the Addis AI API.
const String baseUrl = 'https://api.addisassistant.com/api/v1';

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
