import 'package:dart_openai/dart_openai.dart';

class OpenAiProxy {
  final String endPoint;
  final String apiKey;

  OpenAiProxy(this.endPoint, this.apiKey);

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