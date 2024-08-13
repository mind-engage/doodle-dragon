// Enumeration to define various AI modes for the application's functionality.
enum AiMode { story, transform, poetry, promptToImage }

class ImagenPrompts {
  static String getVlmPrompt(AiMode mode, int learnerAge, String userInput, String skillsSummary) {
    String ageContext = _getAgeContext(learnerAge, mode, skillsSummary);
    switch (mode) {
      case AiMode.story:
        return "Tell me a short, engaging story, suitable for $ageContext, based on the image. I want the story to be fun and maybe a little silly!";
      case AiMode.poetry:
        return "Take a look at this wonderful image  for $ageContext,  that wants to learn about! Let's write a poem together, just like they might write it, about what we see in the picture. "
            ""
            "Use fun words and rhymes that a $learnerAge year old would love!";
      case AiMode.transform:
        return "You are a storyteller and an artist. "
            "Based on this image and the idea  $userInput, tell me a short, engaging story suitable for a $ageContext. I want the story to be fun and maybe a little silly!";

      case AiMode.promptToImage:
        return "You are an AI agent helping a $ageContext to generate a creative and detailed prompt to be passed to text to image generation model."
            "Elaborate on the following topic given by tge child: $userInput. Generate a detailed prompt to create the image";
      default:
        return "";
    }
  }

  static String getImageGenPrompt(AiMode mode, int learnerAge, String vlmResponse, String skillsSummary) {
    String ageContext = _getAgeContext(learnerAge, mode, skillsSummary);
    switch (mode) {
      case AiMode.transform:
        return "Generate a kid friendly drawing for $ageContext. Use the following story line: $vlmResponse. "
            "Make the drawing in the style of a children's book illustration, with bright colors";
      default:
        return "";
    }
  }

// Generate age-appropriate context using skillsSummary
  static String _getAgeContext(int age, AiMode mode, String skillsSummary) {
    switch (mode) {
      case AiMode.story:
      case AiMode.poetry:
      case AiMode.transform:
      case AiMode.promptToImage:
        return "a child around $age years old";
      default:
        return "";
    }
  }
}
