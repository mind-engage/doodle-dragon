import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class SettingsScreen extends StatefulWidget {
  @override
  _SettingsScreenState createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late SharedPreferences prefs;
  double speechRate = 0.5;
  String learnerName = "";
  int learnerAge = 3; // Default to the minimum age
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    loadSettings();
  }

  Future<void> loadSettings() async {
    prefs = await SharedPreferences.getInstance();
    setState(() {
      speechRate = prefs.getDouble('speechRate') ?? 0.5;
      learnerName = prefs.getString('learnerName') ?? "";
      learnerAge = prefs.getInt('learnerAge') ?? 3;
      _isLoading = false;
    });
  }

  Future<void> saveSettings(String key, dynamic value) async {
    if (value is double) {
      await prefs.setDouble(key, value);
    } else if (value is String) {
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
        actions: [
          IconButton(
            icon: Icon(Icons.save),
            onPressed: () {
              // Optionally save all settings at once if necessary
            },
          ),
        ],
      ),
      body: ListView(
        children: [
          ListTile(
            title: Text('Speech Rate'),
            subtitle: Slider(
              min: 0.1,
              max: 1.0,
              divisions: 9,
              label: speechRate.toStringAsFixed(1),
              value: speechRate,
              onChanged: (double value) {
                setState(() {
                  speechRate = value;
                });
                saveSettings('speechRate', value);
              },
            ),
          ),
          ListTile(
            title: Text('Learner Name'),
            subtitle: TextField(
              decoration: InputDecoration(
                hintText: "Enter learner's name",
              ),
              controller: TextEditingController(text: learnerName),
              onSubmitted: (String value) {
                setState(() {
                  learnerName = value;
                });
                saveSettings('learnerName', value);
              },
            ),
          ),
          ListTile(
            title: Text('Learner Age'),
            subtitle: Slider(
              min: 3,
              max: 16,
              divisions: 13,
              label: learnerAge.toString(),
              value: learnerAge.toDouble(),
              onChanged: (double value) {
                setState(() {
                  learnerAge = value.toInt();
                });
                saveSettings('learnerAge', value.toInt());
              },
            ),
          ),
        ],
      ),
    );
  }
}
