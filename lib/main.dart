import 'package:flutter/material.dart';
import 'sketch_screen.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

Future main() async {
  await dotenv.load(fileName: "dotenv");
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
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Colors.pink, Colors.yellow, Colors.lightBlueAccent], // Use a playful gradient
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
                  height: 200, // Adjust size as needed
                ),
              ),
              SizedBox(height: 40),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.green, // Make the button visually appealing
                  padding: EdgeInsets.symmetric(horizontal: 30, vertical: 15),
                  textStyle: TextStyle(fontSize: 20),
                ),
                child: Text('Start Drawing!'),
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (context) => SketchScreen(
                        geminiApiKey: dotenv.get('GEMINI_API_KEY', fallback: ''),
                        openaiApiKey: dotenv.get('OPENAI_API_KEY', fallback: '')
                    )),
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}