/// Flutter SDK for the Addis AI API.
///
/// Supports Ethiopian languages (Amharic and Afan Oromo) with chat
/// generation, text-to-speech, streaming, and multipart uploads.
///
/// ```dart
/// import 'package:addis_ai_sdk/addis_ai_sdk.dart';
///
/// final client = AddisAI(apiKey: 'YOUR_API_KEY');
///
/// final response = await client.generateChat(
///   ChatRequest(
///     prompt: 'ሰላም!',
///     targetLanguage: Language.am,
///   ),
/// );
/// print(response.responseText);
/// ```
library;

export 'src/constants.dart';
export 'src/models.dart';
export 'src/exceptions.dart';
export 'src/addis_ai_client.dart';
export 'src/realtime_client.dart';
