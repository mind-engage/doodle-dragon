import 'package:flutter/material.dart';
import 'sketch_screen.dart';
import 'trace_screen.dart';
import 'imagen_screen.dart';
import 'settings_screen.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter/services.dart';

Future main() async {
  await dotenv.load(fileName: "dotenv");
  // Lock screen orientation to portrait
  WidgetsFlutterBinding.ensureInitialized();
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);
  runApp(DoodleDragon());
}

class DoodleDragon extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Doodle Dragon',
      theme: ThemeData(
        primarySwatch: Colors.deepPurple,
        fontFamily: 'ComicSansMS',
      ),
      home: HomeScreen(),
    );
  }
}

class HomeScreen extends StatefulWidget {
  @override
  _HomeScreenState createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: Duration(milliseconds: 800),
    )..repeat(reverse: true);
    _animation = CurvedAnimation(
      parent: _controller,
      curve: Curves.easeInOut,
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Doodle Dragon'),
        backgroundColor: Colors.deepOrange,
        actions: <Widget>[
          IconButton(
            icon: Icon(Icons.settings),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => SettingsScreen()),
              );
            },
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
                child: Image.asset(
                  'assets/doodle_dragon_logo.png',
                  height: 200,
                ),
              ),
              SizedBox(height: 40),
              _buildElevatedButton(
                context,
                'Start Sketching!',
                'assets/pencil_icon.png',
                    () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => SketchScreen(
                      geminiApiKey: dotenv.get('GEMINI_API_KEY', fallback: ''),
                      openaiApiKey: dotenv.get('OPENAI_API_KEY', fallback: ''),
                    ),
                  ),
                ),
              ),
              SizedBox(height: 20),
              _buildElevatedButton(
                context,
                'Start Tracing!',
                'assets/trace_icon.png',
                    () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => TraceScreen(
                      geminiApiKey: dotenv.get('GEMINI_API_KEY', fallback: ''),
                      openaiApiKey: dotenv.get('OPENAI_API_KEY', fallback: ''),
                    ),
                  ),
                ),
              ),
              SizedBox(height: 20),
              _buildElevatedButton(
                context,
                'Start Imagen!',
                'assets/imagen_icon.png',
                    () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => ImagenScreen(
                      geminiApiKey: dotenv.get('GEMINI_API_KEY', fallback: ''),
                      openaiApiKey: dotenv.get('OPENAI_API_KEY', fallback: ''),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildElevatedButton(
      BuildContext context, String text, String imagePath, VoidCallback onPressed) {
    return ElevatedButton(
      style: ElevatedButton.styleFrom(
        backgroundColor: Colors.green,
        padding: EdgeInsets.symmetric(horizontal: 20, vertical: 10),
        textStyle: TextStyle(
          fontSize: 20,         // Increase font size
          fontWeight: FontWeight.bold, // Make text bold
          fontFamily: 'ComicSansMS',
          inherit: false,     // <-- Add this line to fix the error!
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