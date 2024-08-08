
String getSkillsText(int age) {
  if (age <= 5) {
    return "### Cognitive Development:\n"
        "- **Language Acquisition:** Enhance vocabulary and grammatical skills through interactive storytelling.\n"
        "- **Basic Concepts Recognition:** Recognize and name colors, shapes, and objects with visual aids.\n"
        "- **Emotional Recognition:** Identify various emotions through stories and images.\n\n"
        "### Learning Skills:\n"
        "- **Listening and Comprehension:** Improve listening skills through interactive games and story sessions.\n"
        "- **Early Literacy:** Language models read aloud, highlight text, and explain words for reading introduction.";
  } else if (age <= 8) {
    return "### Cognitive Development:\n"
        "- **Reading Fluency:** Assist with reading aloud, providing feedback on pronunciation and fluency.\n"
        "- **Math Basics:** Teach basic math concepts like addition, subtraction, and geometry with visual aids.\n"
        "- **Problem Solving:** Develop critical thinking through interactive problem-solving tasks.\n\n"
        "### Learning Skills:\n"
        "- **Creative Writing:** Inspire writing and storytelling through prompts generated by LLMs.\n"
        "- **Information Retrieval:** Foster basic research skills, teaching how to ask questions and receive accurate information.";
  } else if (age <= 11) {
    return "### Cognitive Development:\n"
        "- **Advanced Reading and Comprehension:** Analyze texts, summarize information, and clarify complex topics.\n"
        "- **Scientific Concepts:** Illustrate concepts like the water cycle, plant life cycles through visuals and text.\n"
        "- **Cultural Awareness:** Introduce different cultures and languages, broadening worldview.\n\n"
        "### Learning Skills:\n"
        "- **Logical Reasoning:** Develop reasoning with logical puzzles and problems.\n"
        "- **Project-Based Learning:** Guide research, planning, and presentation of various projects.";
  } else if (age <= 14) {
    return "### Cognitive Development:\n"
        "- **Abstract Thinking:** Introduce and explain abstract concepts in algebra, science, and literature.\n"
        "- **Critical Analysis:** Analyze texts and media critically with AI-driven discussion prompts and tools.\n"
        "- **Ethics and Responsibility:** Discuss ethical scenarios like fairness or privacy.\n\n"
        "### Learning Skills:\n"
        "- **Advanced Research:** Conduct sophisticated research for papers and projects.\n"
        "- **Collaborative Learning:** Facilitate collaborative projects, solving problems and creating presentations.";
  } else {
    return "### Cognitive Development:\n"
        "- **In-depth Subject Knowledge:** Teach advanced topics in history, science, and math, solving complex problems.\n"
        "- **Language Mastery:** Assist in learning new languages, practicing grammar and writing at an advanced level.\n"
        "- **Data Literacy:** Introduce data interpretation and statistical analysis.\n\n"
        "### Learning Skills:\n"
        "- **Preparation for Higher Education:** Teach academic writing, research methodologies, and critical thinking.\n"
        "- **Career Exploration:** Assess and explore different career paths and the skills required.";
  }
}