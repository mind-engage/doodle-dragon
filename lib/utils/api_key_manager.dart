import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:shared_preferences/shared_preferences.dart';

class APIKeyManager {
  static APIKeyManager? _instance;
  late String geminiApiKey;
  late String openaiApiKey;
  final String geminiEndpoint = 'https://generativelanguage.googleapis.com/v1beta/models/gemini-1.5-pro-latest:generateContent';  // Static endpoint for Gemini API
  late String openaiProxyEndpoint;
  late String geminiProxyEndpoint;

  APIKeyManager._({required this.geminiApiKey,
    required this.openaiApiKey,
    required this.openaiProxyEndpoint,
    required this.geminiProxyEndpoint});

  static Future<APIKeyManager> getInstance() async {
    if (_instance == null) {
      SharedPreferences prefs = await SharedPreferences.getInstance();
      String geminiKey = "";
      String openaiKey = "";

      String serviceType = dotenv.get('SERVICE_TYPE', fallback: "AppKey");
      String openaiProxyEndpoint = "";
      String geminiProxyEndpoint = "";

      if (dotenv.isInitialized) {
        if (serviceType == "AppKey") {
          geminiKey = dotenv.get('GEMINI_API_KEY',
              fallback: '');
          openaiKey = dotenv.get('OPENAI_API_KEY', fallback: '');
        } else if (serviceType == "UserKey") {
          geminiKey = prefs.getString('GEMINI_API_KEY') ?? '';
          openaiKey = prefs.getString('OPENAI_API_KEY') ?? '';
        } else if (serviceType == "ProxyApi") {
          openaiProxyEndpoint =
              dotenv.get('OPENAI_PROXY_ENDPOINT', fallback: '');
          geminiProxyEndpoint =
              dotenv.get('GEMINI_PROXY_ENDPOINT', fallback: '');
        }
      }
      _instance = APIKeyManager._(geminiApiKey: geminiKey, openaiApiKey: openaiKey,
          openaiProxyEndpoint: openaiProxyEndpoint, geminiProxyEndpoint: geminiProxyEndpoint);
    }
    return _instance!;
  }
}
