// Import necessary Flutter and third-party packages.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'sketch_screen.dart';
import 'trace_screen.dart';
import 'imagen_screen.dart';
import 'settings_screen.dart';

// Main entry point of the Flutter application.
Future main() async {
  // Ensure that Flutter widgets are bound to the framework before executing any other operations.
  WidgetsFlutterBinding.ensureInitialized();
  // Load environment variables from the .env file.
  await dotenv.load(fileName: "dotenv");
  // Lock orientation to portrait mode.
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);
  // Run the application after initializing it.
  runApp(await DoodleDragon.initialize());
}

// Stateless widget for the main application.
class DoodleDragon extends StatelessWidget {
  final String geminiApiKey;
  final String openaiApiKey;

  // Constructor requiring API keys.
  DoodleDragon({required this.geminiApiKey, required this.openaiApiKey});

  // Factory method to asynchronously fetch API keys from SharedPreferences or .env file before building the widget.
  static Future<DoodleDragon> initialize() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    String geminiApiKey = dotenv.get('GEMINI_API_KEY', fallback: prefs.getString('GEMINI_API_KEY') ?? '');
    String openaiApiKey = dotenv.get('OPENAI_API_KEY', fallback: prefs.getString('OPENAI_API_KEY') ?? '');
    return DoodleDragon(geminiApiKey: geminiApiKey, openaiApiKey: openaiApiKey);
  }

  // Build the MaterialApp with the specified theme and home screen.
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Doodle Dragon',
      theme: ThemeData(
        primarySwatch: Colors.deepPurple,
        fontFamily: 'ComicSansMS',
      ),
      home: HomeScreen(geminiApiKey: geminiApiKey, openaiApiKey: openaiApiKey),
    );
  }
}

// Stateful widget for the home screen.
class HomeScreen extends StatefulWidget {
  final String geminiApiKey;
  final String openaiApiKey;

  // Constructor requiring API keys.
  HomeScreen({required this.geminiApiKey, required this.openaiApiKey});

  @override
  _HomeScreenState createState() => _HomeScreenState();
}

// Private State class for HomeScreen, handling animations and UI.
class _HomeScreenState extends State<HomeScreen> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;

  // Initialize state, setting up the animation controller.
  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: Duration(milliseconds: 800),
      vsync: this,
    )..repeat(reverse: true);
    _animation = CurvedAnimation(parent: _controller, curve: Curves.easeInOut);
  }

  // Dispose the controller when the widget is removed from the tree.
  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  // Build the UI with AppBar and body containing buttons to navigate to different screens.
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Doodle Dragon'),
        backgroundColor: Colors.deepOrange,
        actions: <Widget>[
          IconButton(
            icon: Icon(Icons.settings),
            onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (context) => SettingsScreen())),
          ),
        ],
      ),
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Colors.pink, Colors.yellow, Colors.lightBlueAccent],
          ),
        ),
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              RotationTransition(
                turns: _animation,
                child: Image.asset('assets/doodle_dragon_logo.png', height: 200),
              ),
              SizedBox(height: 40),
              _buildElevatedButton('Start Sketching!', 'assets/pencil_icon.png', () => Navigator.push(
                  context, MaterialPageRoute(builder: (context) => SketchScreen(geminiApiKey: widget.geminiApiKey, openaiApiKey: widget.openaiApiKey)))),
              SizedBox(height: 20),
              _buildElevatedButton('Start Tracing!', 'assets/trace_icon.png', () => Navigator.push(
                  context, MaterialPageRoute(builder: (context) => TraceScreen(geminiApiKey: widget.geminiApiKey, openaiApiKey: widget.openaiApiKey)))),
              SizedBox(height: 20),
              _buildElevatedButton('Start Imagen!', 'assets/imagen_icon.png', () => Navigator.push(
                  context, MaterialPageRoute(builder: (context) => ImagenScreen(geminiApiKey: widget.geminiApiKey, openaiApiKey: widget.openaiApiKey)))),
            ],
          ),
        ),
      ),
    );
  }

  // Helper method to build a styled button with an icon.
  Widget _buildElevatedButton(String text, String imagePath, VoidCallback onPressed) {
    return ElevatedButton(
      style: ElevatedButton.styleFrom(
        backgroundColor: Colors.green,
        padding: EdgeInsets.symmetric(horizontal: 20, vertical: 10),
        textStyle: TextStyle(
          fontSize: 20,
          fontWeight: FontWeight.bold,
          fontFamily: 'ComicSansMS',
        ),
      ),
      onPressed: onPressed,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Image.asset(imagePath, height: 60),
          SizedBox(width: 10),
          Text(text),
        ],
      ),
    );
  }
}
