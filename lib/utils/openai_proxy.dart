
class OpenAiProxy {
  final String endPoint;
  final String apiKey;

  OpenAiProxy(this.geminiEndpoint, this.strokeWidth, {List<Offset>? points})
      : this.points = points ?? [];

  Furutre<String> process(String jsonBody) async {
    var response = await http.post(
      Uri.parse('$geminiEndpoint?key=$geminiApiKey'),
      headers: {'Content-Type': 'application/json'},
      body: jsonBody,
    );
    return response;
  }
}