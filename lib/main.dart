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
        primarySwatch: Colors.deepPurple, // Choose a vibrant color scheme
        fontFamily: 'ComicSansMS', // A kid-friendly font if available
      ),
      home: HomeScreen(),
    );
  }
}

class HomeScreen extends StatefulWidget {
  @override
  _HomeScreenState createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with SingleTickerProviderStateMixin {
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
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.green,
                  padding: EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                ),
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (context) => SketchScreen(
                        geminiApiKey: dotenv.get('GEMINI_API_KEY', fallback: ''),
                        openaiApiKey: dotenv.get('OPENAI_API_KEY', fallback: '')
                    )),
                  );
                },
                child: Row(
                  mainAxisSize: MainAxisSize.min, // Aligns children closely together
                  children: <Widget>[
                    Image.asset('assets/pencil_icon.png', height: 60),
                    SizedBox(width: 10), // Spacing between the image and the text
                    Text('Start Drawing!'),
                  ],
                ),
              ),
              SizedBox(height: 20),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.green,
                  padding: EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                ),
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (context) => TraceScreen(
                        geminiApiKey: dotenv.get('GEMINI_API_KEY', fallback: ''),
                        openaiApiKey: dotenv.get('OPENAI_API_KEY', fallback: '')
                    )),
                  );
                },
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Image.asset('assets/trace_icon.png', height: 60),
                    SizedBox(width: 10),
                    Text('Start Tracing!'),
                  ],
                ),
              ),
              SizedBox(height: 20),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.green,
                  padding: EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                ),
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (context) => ImagenScreen(
                        geminiApiKey: dotenv.get('GEMINI_API_KEY', fallback: ''),
                        openaiApiKey: dotenv.get('OPENAI_API_KEY', fallback: '')
                    )),
                  );
                },
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Image.asset('assets/imagen_icon.png', height: 60),
                    SizedBox(width: 10),
                    Text('Start Imagen!'),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
