import 'package:http/http.dart' as http;

// Abstract class acting as an interface
abstract class GeminiProxy {
  Future<http.Response> process(String jsonBody);
}

// Implementation for direct API calls
class DirectGeminiProxy implements GeminiProxy {
  final String endPoint;
  final String apiKey;

  DirectGeminiProxy(this.endPoint, this.apiKey);

  @override
  Future<http.Response> process(String jsonBody) async {
    var response = await http.post(
      Uri.parse('$endPoint?key=$apiKey'),
      headers: {'Content-Type': 'application/json'},
      body: jsonBody,
    );
    return response;
  }
}

// Implementation for calls via a cloud function
class CloudFunctionGeminiProxy implements GeminiProxy {
  final String cloudFunctionEndPoint;
  final String accessToken;

  CloudFunctionGeminiProxy(this.cloudFunctionEndPoint, this.accessToken);

  @override
  Future<http.Response> process(String jsonBody) async {
    var response = await http.post(
      Uri.parse(cloudFunctionEndPoint),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $accessToken'
      },
      body: jsonBody,
    );
    return response;
  }
}