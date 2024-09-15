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

const Map<OpenAIImageSize, String> toSizeString = {
  OpenAIImageSize.size256: "256x256",
  OpenAIImageSize.size512: "512x512",
  OpenAIImageSize.size1024: "1024x1024",
  OpenAIImageSize.size1792Horizontal: "1792x1024",
  OpenAIImageSize.size1792Vertical: "1024x1792",
};

class CloudFunctionOpenAiProxy implements OpenAiProxy {
  final String cloudFunctionEndPoint;
  final String accessToken;

  CloudFunctionOpenAiProxy(this.cloudFunctionEndPoint, this.accessToken);


  static Map<String, dynamic> decodeToMap(String responseBody) {
    try {
      return jsonDecode(responseBody) as Map<String, dynamic>;
    } catch (e) {
      throw FormatException('Failed to decode JSON: $e');
    }
  }

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
        'size': toSizeString[size] ?? '1024x1024',
        'responseFormat': 'b64_json'
      }),
    );

    // Assuming the cloud function returns the image model in a similar structure to the OpenAI API
    if (response.statusCode == 200) {
      //var json = jsonDecode(response.body);

      Utf8Decoder utf8decoder = const Utf8Decoder();
      final convertedBody = utf8decoder.convert(response.bodyBytes);
      final Map<String, dynamic> decodedBody = decodeToMap(convertedBody);

      return OpenAIImageModel.fromMap(decodedBody);
      /*
      return OpenAIImageModel(
        created: DateTime.fromMillisecondsSinceEpoch(1 * 1000),
        data: (json[0] as List)
            .map((e) => OpenAIImageData.fromMap(e))
            .toList(),
      );
      */
    } else {
      throw Exception('Failed to process image via cloud function: ${response.body}');
    }
  }
}