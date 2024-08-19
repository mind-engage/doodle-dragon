## Doodle Dragon: A Creative Playground for Kids with AI! 🎨🤖

Doodle Dragon is a Flutter application designed to spark creativity and learning in young children. Using the power of Google's Gemini and OpenAI's APIs, Doodle Dragon transforms simple sketches into engaging experiences.

### Features

* **Sketching:** Unleash freehand drawing with various colors and brush sizes. Kids can erase and start over, experimenting to their heart's content.
* **Tracing:**  Choose from a library of age-appropriate images or let the app generate one from a spoken description!  Doodle Dragon provides helpful feedback on tracing accuracy to encourage improvement.
* **Imagening:** Turn drawings into interactive adventures! Doodle Dragon generates stories, poems, and even transforms images based on spoken prompts.


### How to Use Doodle Dragon
[The user guide will walk you through all UI feature](./docs/UserGuide.md)

### Watch Doodle Dragon in Action
[Watch the Demo Video Now](https://youtu.be/PIbCCbIpTz8)

### How It Works

Doodle Dragon leverages the following technologies:

* **Flutter:** For building a beautiful and responsive user interface.
* **Google Gemini:** A powerful multimodal AI model that analyzes images and text to generate creative content.
* **OpenAI API (Optional):** Used for text-to-image generation, allowing kids to bring their spoken ideas to life.
* **Speech-to-Text & Text-to-Speech:**  Makes the app accessible and engaging for young children.

### Getting Started

1. **Prerequisites:**  You will need a Flutter development environment set up.
2. **API Keys:**
    * Obtain a Gemini API key from Google Cloud Platform.
    * (Optional) Get an OpenAI API key for expanded image generation features.
3. **Clone the Repository:**  `git clone https://github.com/your-username/doodle-dragon.git`
4. **Install Dependencies:** `flutter pub get`
5. **Configure API Keys:** You can provide the API keys through the app's settings screen once it is launched.
6. **Run the App:** `flutter run`



**Currently tested only on Android Phones and Tablets with API level 33 and above**

### Configuration

The app can be customized through the settings screen:

* **General Settings:**
    * **Learner Name:** Used to personalize interactions with the child.
    * **Learner Age:** Helps the AI models tailor content appropriately.
* **API Keys:**
    * **Gemini API Key:** Your Google Gemini API key.
    * **OpenAI API Key:** Your OpenAI API key (optional).

### Future Enhancements
* **User Accounts:** Allow multiple children to save their drawings and progress.
* **Offline Mode:** Explore options for limited offline functionality.
* **Text/Image to Video:** Support for Video generation prompts in addition to text/image
* **Backend:** Backend for aggregating and sharing content.

Let's make learning fun and creative with Doodle Dragon! 🐲
