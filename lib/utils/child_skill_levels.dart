import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'log.dart';

// Define the skills as a nested map.
final Map<int, Map<String, List<String>>> drawingSkills = {
  5: {
    'Fine Motor Skills': [
      'Holding and Controlling Crayons: Encourage proper grip and control for drawing lines and shapes.',
      'Hand-Eye Coordination: Develop hand-eye coordination through activities like tracing and coloring within lines.'
    ],
    'Visual Perception': [
      'Color Recognition and Naming: Learn to identify and name basic colors while drawing and coloring.',
      'Shape Recognition: Recognize and draw simple shapes like circles, squares, and triangles.'
    ],
    'Imagination & Creativity': [
      'Expressing Ideas Through Drawing: Encourage children to express thoughts and stories through simple drawings.',
      'Storytelling Through Art:  Help children create visual narratives by drawing scenes from stories.'
    ]
  },
  8: {
    'Fine Motor Skills': [
      'Drawing More Detailed Pictures: Develop fine motor control for drawing more intricate details and patterns.',
      'Using Different Drawing Tools: Experiment with various tools like colored pencils, markers, and crayons.'
    ],
    'Visual Perception': [
      'Spatial Awareness: Understand spatial relationships when drawing objects in relation to each other.',
      'Perspective: Introduce basic concepts of perspective, such as objects appearing smaller when further away.'
    ],
    'Imagination & Creativity': [
      'Developing Personal Style: Encourage children to explore different drawing styles and develop their own.',
      'Drawing from Observation: Help children improve observation skills by drawing objects and scenes from real life.'
    ]
  },
  11: {
    'Fine Motor Skills': [
      'Refining Line Control: Develop greater control over line weight, texture, and precision.',
      'Shading and Blending: Introduce techniques for shading and blending to create depth and realism.'
    ],
    'Visual Perception': [
      'Proportion and Scale: Understand and apply concepts of proportion and scale in drawings.',
      'Composition: Learn about arranging elements within a drawing to create a balanced and visually appealing composition.'
    ],
    'Imagination & Creativity': [
      'Exploring Different Art Styles: Introduce various art styles like realism, impressionism, and abstract art.',
      'Expressing Emotions Through Art: Encourage the use of color, line, and composition to convey emotions in drawings.'
    ]
  },
  99: {
    'Fine Motor Skills': [
      'Mastering Advanced Techniques: Explore and practice techniques like stippling, cross-hatching, and pointillism.',
      'Developing Precision and Detail:  Focus on achieving high levels of detail and accuracy in drawings.'
    ],
    'Visual Perception': [
      'Understanding Light and Shadow: Develop a deeper understanding of how light affects form and creates shadows.',
      'Advanced Perspective: Explore more complex perspective techniques, such as two-point and three-point perspective.'
    ],
    'Imagination & Creativity': [
      'Developing a Unique Artistic Voice: Encourage experimentation and the development of a personal artistic style.',
      'Conceptual Thinking: Use drawing as a tool for exploring abstract ideas, concepts, and emotions.'
    ]
  }
};

String getSkillsTextForUI(int age) {
  int key = drawingSkills.keys.firstWhere((k) => age <= k, orElse: () => drawingSkills.keys.last);
  Map<String, List<String>> skills = drawingSkills[key]!;

  // Use a StringBuffer for more efficient string concatenation
  StringBuffer text = StringBuffer();

  skills.forEach((category, skillList) {
    text.writeln('\n**$category:**'); // Category as a heading
    skillList.forEach((skill) {
      text.writeln(' • ${skill.split(':')[0]}'); // Bullet points for skills
    });
  });

  return text.toString();
}

String getSkillsTextForPrompt(int age) {
  int key = drawingSkills.keys.firstWhere((k) => age <= k, orElse: () => drawingSkills.keys.last);
  Map<String, List<String>> skills = drawingSkills[key]!;

  List<String> skillPhrases = [];
  skills.forEach((category, skillList) {
    skillList.forEach((skill) {
      // Extract only the part before ":" for the prompt
      skillPhrases.add(skill.split(':')[0]);
    });
  });

  return skillPhrases.join('. ');
}



// Example usage for saving to SharedPreferences
Future<void> saveSkillsToPreferences(int age) async {
  SharedPreferences prefs = await SharedPreferences.getInstance();
  String skillsJson = json.encode(drawingSkills);
  await prefs.setString('skillsData', skillsJson);

  // Retrieve and format the skills text
  String formattedSkills = getSkillsTextForUI(age);
  Log.d(formattedSkills);
}