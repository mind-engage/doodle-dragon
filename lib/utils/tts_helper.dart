import 'dart:async';
import 'package:flutter_tts/flutter_tts.dart';

class TtsHelper {
  late FlutterTts flutterTts;

  TtsHelper() {
    flutterTts = FlutterTts();
    initialize();
  }

  void initialize() {
    flutterTts.setLanguage("en-US");
    flutterTts.setPitch(1.0);  // Higher pitch often perceived as friendlier
    flutterTts.setSpeechRate(0.4);  // Slower rate for better comprehension
    flutterTts.awaitSpeakCompletion(true);  // Wait for spoken feedback to complete
  }

  Future<void> speak(String text) async {
    if (text.isNotEmpty) {
      await flutterTts.stop();
      var completion = Completer<void>();
      flutterTts.setCompletionHandler(() {
        completion.complete();
      });
      await flutterTts.speak(text);
      return completion.future; // Waits until speaking is completed
    }
  }

  void stop() {
    flutterTts.stop();
  }
}
