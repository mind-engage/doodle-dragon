import 'package:http/http.dart' as http;

class GeminiProxy {
  final String endPoint;
  final String apiKey;

  GeminiProxy(this.endPoint, this.apiKey);

  Future<http.Response> process(String jsonBody) async {
    var response = await http.post(
      Uri.parse('$endPoint?key=$apiKey'),
      headers: {'Content-Type': 'application/json'},
      body: jsonBody,
    );
    return response;
  }
}