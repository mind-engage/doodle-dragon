enum AiMode { analysis, sketchToImage }

class SketchPrompts {

  static String getPrompt(AiMode mode, int learnerAge,
      List<Map<String, dynamic>> chatHistory, String skillsSummary) {
    String ageContext = _getAgeContext(learnerAge, mode, skillsSummary);

    switch (mode) {
      case AiMode.analysis:
        if (chatHistory.isNotEmpty) {
          return "$ageContext\n\n"
              "Analyze this drawing considering the child's developmental stage. If  the child tried any of the suggestions, give appreciation. "
              "Give them some encouragement and new ideas! Remember, you're only looking at their latest drawing. "
              "Offer specific feedback and suggestions in a conversational and encouraging tone, as if you were speaking directly to the child. ";
        } else {
          return "$ageContext\n\n"
          "Analyze this drawing considering the child's developmental stage. "
              "Offer specific feedback and suggestions in a conversational and encouraging tone, as if you were speaking directly to the child.";
        }
      case AiMode.sketchToImage:
        return "$ageContext"
            "Let's make this drawing into a super cool picture!"
            "What colors should we use? Anything shiny? Is it happy or maybe a little spooky?  Be creative!";
      default:
        return "";
    }
  }

  // Generate age-appropriate context using skillsSummary
  static String _getAgeContext(int age, AiMode mode, String skillsSummary) {
    if (mode == AiMode.analysis) {
      return "This drawing was made by a child around $age years old.\n"
          "They are working on:\n $skillsSummary";
    } else if (mode == AiMode.sketchToImage) {
      return "Imagine this drawing was made by a child who is $age years old. "
          "They are working on skills like: $skillsSummary. "
          "Turn this drawing into an amazing picture ";
    } else {
      return "";
    }
  }
}