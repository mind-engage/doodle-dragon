import 'package:dart_openai/dart_openai.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';

abstract class OpenAiProxy {
  Future<OpenAIImageModel> process(String model, String prompt, OpenAIImageSize size);
}

class DirectOpenAiProxy implements OpenAiProxy {
  final String endPoint;
  final String apiKey;

  DirectOpenAiProxy(this.endPoint, this.apiKey) {
    // Set the OpenAI API key here
    OpenAI.apiKey = apiKey;
  }

  @override
  Future<OpenAIImageModel> process(String model, String prompt, OpenAIImageSize size) async {
    final imageResponse = await OpenAI.instance.image.create(
      model: model,
      prompt: prompt,
      n: 1,
      size: size,
      responseFormat: OpenAIImageResponseFormat.b64Json,
    );
    return imageResponse;
  }
}

class CloudFunctionOpenAiProxy implements OpenAiProxy {
  final String cloudFunctionEndPoint;
  final String accessToken;

  CloudFunctionOpenAiProxy(this.cloudFunctionEndPoint, this.accessToken);

  @override
  Future<OpenAIImageModel> process(String model, String prompt, OpenAIImageSize size) async {
    var response = await http.post(
      Uri.parse(cloudFunctionEndPoint),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $accessToken'
      },
      body: jsonEncode({
        'model': model,
        'prompt': prompt,
        'n': 1,
        'size': size.toString().split('.').last,
        'responseFormat': 'b64Json'
      }),
    );

    // Assuming the cloud function returns the image model in a similar structure to the OpenAI API
    if (response.statusCode == 200) {
      var data = jsonDecode(response.body);

      return OpenAIImageModel.fromMap(data);
    } else {
      throw Exception('Failed to process image via cloud function: ${response.body}');
    }
  }
}