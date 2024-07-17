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
      title: 'Sketch App',
      home: HomeScreen(),
    );
  }
}

class HomeScreen extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Welcome'),
      ),
      body: Container(
        decoration: BoxDecoration(
          image: DecorationImage(
            image: AssetImage('assets/doodle_dragon_logo.png'),
            fit: BoxFit.contain,  // This will cover the entire background of the container
          ),
        ),
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              Text('Please agree to the terms and conditions.'),
              SizedBox(height: 20),
              ElevatedButton(
                child: Text('Agree'),
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
