import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:shared_preferences/shared_preferences.dart';

class APIKeyManager {
  static APIKeyManager? _instance;
  late String geminiApiKey;
  late String openaiApiKey;
  final String geminiEndpoint = 'https://generativelanguage.googleapis.com/v1beta/models/gemini-1.5-pro-latest:generateContent';  // Static endpoint for Gemini API

  APIKeyManager._({required this.geminiApiKey, required this.openaiApiKey});

  static Future<APIKeyManager> getInstance() async {
    if (_instance == null) {
      SharedPreferences prefs = await SharedPreferences.getInstance();
      String geminiKey;
      String openaiKey;

      if (dotenv.isInitialized) {
        geminiKey = dotenv.get('GEMINI_API_KEY', fallback: prefs.getString('GEMINI_API_KEY') ?? '');
        openaiKey = dotenv.get('OPENAI_API_KEY', fallback: prefs.getString('OPENAI_API_KEY') ?? '');
      } else {
        geminiKey = prefs.getString('GEMINI_API_KEY') ?? '';
        openaiKey = prefs.getString('OPENAI_API_KEY') ?? '';
      }
      _instance = APIKeyManager._(geminiApiKey: geminiKey, openaiApiKey: openaiKey);
    }
    return _instance!;
  }
}
