import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'utils/child_skill_levels.dart';

class SettingsScreen extends StatefulWidget {
  @override
  _SettingsScreenState createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> with SingleTickerProviderStateMixin {
  late SharedPreferences prefs;
  late TabController _tabController;
  String learnerName = "";
  int learnerAge = 3;
  String skillsText = "";
  bool _isLoading = true;
  String geminiApiKey = "";
  String openaiApiKey = "";

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    loadSettings();
  }

  Future<void> loadSettings() async {
    prefs = await SharedPreferences.getInstance();
    setState(() {
      learnerName = prefs.getString('learnerName') ?? "";
      learnerAge = prefs.getInt('learnerAge') ?? 3;
      skillsText = getSkillsText(learnerAge);
      geminiApiKey = prefs.getString('GEMINI_API_KEY') ?? "";
      openaiApiKey = prefs.getString('OPENAI_API_KEY') ?? "";
      _isLoading = false;
    });
  }

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
            Tab(text: 'API Keys'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          buildGeneralSettings(),
          buildApiKeysSettings(),
        ],
      ),
    );
  }

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
                skillsText = getSkillsText(learnerAge);
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
      ],
    );
  }
}
