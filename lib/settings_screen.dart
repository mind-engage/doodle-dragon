import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'utils/child_skill_levels.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

// Define a StatefulWidget to handle the settings screen of the app
class SettingsScreen extends StatefulWidget {

  SettingsScreen();

  @override
  _SettingsScreenState createState() => _SettingsScreenState();
}

// State class for SettingsScreen
class _SettingsScreenState extends State<SettingsScreen> with SingleTickerProviderStateMixin {
  late SharedPreferences prefs; // To handle local storage for settings
  late TabController _tabController; // To control tab switching in the app bar
  String learnerName = ""; // Store learner's name
  int learnerAge = 3; // Store learner's age, default set to 3
  String skillsText = ""; // Store descriptive text about skills based on age
  bool _isLoading = true; // Boolean to handle display of loading spinner
  String geminiApiKey = ""; // Store Gemini API key
  String openaiApiKey = ""; // Store OpenAI API key
  bool isUserKey = false;

  @override
  void initState() {
    super.initState();
    String serviceType = dotenv.get('SERVICE_TYPE', fallback: "AppKey");
    isUserKey = serviceType == "UserKey";
    _tabController = TabController(length: isUserKey ? 2 : 1, vsync: this);

    loadSettings();
  }

  // Load settings from SharedPreferences
  Future<void> loadSettings() async {
    prefs = await SharedPreferences.getInstance();
    setState(() {
      learnerName = prefs.getString('learnerName') ?? "";
      learnerAge = prefs.getInt('learnerAge') ?? 3;
      skillsText = getSkillsTextForUI(learnerAge);
      geminiApiKey = prefs.getString('GEMINI_API_KEY') ?? "";
      openaiApiKey = prefs.getString('OPENAI_API_KEY') ?? "";
      _isLoading = false;
    });
  }

  // Save settings to SharedPreferences
  Future<void> saveSettings(String key, dynamic value) async {
    if (value is String) {
      await prefs.setString(key, value);
    } else if (value is int) {
      await prefs.setInt(key, value);
    }
    loadSettings(); // Reload settings to ensure UI is up to date
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Scaffold(
        appBar: AppBar(title: Text('Settings')),
        body: Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text('Settings'),
        bottom: TabBar(
          controller: _tabController,
          tabs: [
            Tab(text: 'General'),
            if (isUserKey) Tab(text: 'API Keys'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          buildGeneralSettings(),
          if(isUserKey)  buildApiKeysSettings(),
        ],
      ),
    );
  }

  // Widget to build general settings tab
  Widget buildGeneralSettings() {
    return ListView(
      children: [
        ListTile(
          title: Text('Learner Name', style: TextStyle(color: Color(0xFF330066))),
          subtitle: TextField(
            decoration: InputDecoration(
              hintText: "Enter learner's name",
              hintStyle: TextStyle(color: Color(0xFF9D86D2)),
            ),
            controller: TextEditingController(text: learnerName),
            onSubmitted: (String value) {
              saveSettings('learnerName', value);
            },
          ),
        ),
        ListTile(
          title: Text('Learner Age'),
          subtitle: Slider(
            min: 3,
            max: 12,
            divisions: 12,
            label: learnerAge.toString(),
            value: learnerAge.toDouble(),
            onChanged: (double value) {
              setState(() {
                learnerAge = value.toInt();
                skillsText = getSkillsTextForUI(learnerAge);
              });
              saveSettings('learnerAge', learnerAge);
            },
          ),
        ),
        ListTile(
          title: Text(
            'Cognitive and Learning Skills for Age $learnerAge',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: Colors.deepPurple,
            ),
          ),
          subtitle: MarkdownBody(
            data: skillsText,
          ),
        ),
      ],
    );
  }

  Future<void> _launchUrl(String url) async {
    if (!await launchUrl(Uri.parse(url))) {
      throw 'Could not launch $url';
    }
  }

// Widget to build API keys settings tab
  Widget buildApiKeysSettings() {
    return ListView(
      children: [
        ListTile(
          title: Text('Gemini API Key', style: TextStyle(color: Color(0xFF330066))),
          subtitle: TextField(
            decoration: InputDecoration(
              hintText: "Enter Gemini API Key",
              hintStyle: TextStyle(color: Color(0xFF9D86D2)),
            ),
            controller: TextEditingController(text: geminiApiKey),
            onSubmitted: (String value) {
              saveSettings('GEMINI_API_KEY', value);
            },
          ),
        ),
        ListTile(
          leading: Icon(Icons.link, color: Colors.blue),
          title: Text('Get Gemini API Key', style: TextStyle(color: Colors.blue, decoration: TextDecoration.underline)),
          onTap: () => _launchUrl('https://ai.google.dev/aistudio'),
        ),
        Divider(color: Colors.grey[300], thickness: 3, height: 30),  // Adding a divider with spacing
        ListTile(
          title: Text('OpenAI API Key', style: TextStyle(color: Color(0xFF330066))),
          subtitle: TextField(
            decoration: InputDecoration(
              hintText: "Enter OpenAI API Key",
              hintStyle: TextStyle(color: Color(0xFF9D86D2)),
            ),
            controller: TextEditingController(text: openaiApiKey),
            onSubmitted: (String value) {
              saveSettings('OPENAI_API_KEY', value);
            },
          ),
        ),
        ListTile(
          leading: Icon(Icons.link, color: Colors.blue),
          title: Text('Get OpenAI API Key', style: TextStyle(color: Colors.blue, decoration: TextDecoration.underline)),
          onTap: () => _launchUrl('https://openai.com/index/openai-api/'),
        ),
      ],
    );
  }
}
