import 'package:flutter/material.dart';
import 'sketch_screen.dart';

void main() {
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
      body: Center(
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
                  MaterialPageRoute(builder: (context) => SketchScreen()),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}
