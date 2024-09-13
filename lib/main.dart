// Import necessary Flutter and third-party packages.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'sketch_screen.dart';
import 'trace_screen.dart';
import 'imagen_screen.dart';
import 'settings_screen.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';
import '../utils/log.dart';
import 'firebase_options.dart'; // Make sure to create this file
import "utils/gemini_proxy.dart"; // Import the GeminiProxy class
import "utils/openai_proxy.dart";
import 'utils/api_key_manager.dart';

// Main entry point of the Flutter application.
Future<void> main() async {
  // Ensure that Flutter widgets are bound to the framework before executing any other operations.
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize Firebase
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  // Attempt to load environment variables from the .env file if it exists.
  try {
    await dotenv.load(fileName: "dotenv"); // Correct file name to ".env"
  } catch (e) {
    // Handle the case where the .env file doesn't exist or other errors occur.
    Log.d("Failed to load .env file: $e");
  }

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
  final GeminiProxy geminiProxy;
  final OpenAiProxy openaiProxy;

  // Constructor requiring the GeminiProxy instance.
  DoodleDragon({required this.geminiProxy, required this.openaiProxy});

  // Factory method to asynchronously fetch API keys from SharedPreferences or .env file before building the widget.
  static Future<DoodleDragon> initialize() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    final apiKeyManager = await APIKeyManager.getInstance();
    // Get Gemini API keys and endpoint from SharedPreferences or .env
    //String geminiApiKey = prefs.getString('GEMINI_API_KEY') ?? dotenv.env['GEMINI_API_KEY'] ?? '';
    //String geminiEndpoint = prefs.getString('GEMINI_ENDPOINT') ?? dotenv.env['GEMINI_ENDPOINT'] ?? '';

    String geminiApiKey = apiKeyManager.geminiApiKey;
    String openaiApiKey = apiKeyManager.openaiApiKey;
    String geminiEndpoint = apiKeyManager.geminiEndpoint;

    // Initialize the GeminiProxy instance
    GeminiProxy geminiProxy = GeminiProxy(geminiEndpoint, geminiApiKey);

    // Initialize the GeminiProxy instance
    OpenAiProxy openaiProxy = OpenAiProxy("", openaiApiKey);

    return DoodleDragon(geminiProxy: geminiProxy, openaiProxy: openaiProxy);
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
      home: AuthGate(geminiProxy: geminiProxy, openaiProxy: openaiProxy,), // Pass geminiProxy to AuthGate
    );
  }
}

// Widget to handle authentication state (sign-in or home screen)
class AuthGate extends StatelessWidget {
  final GeminiProxy geminiProxy;
  final OpenAiProxy openaiProxy;

  AuthGate({required this.geminiProxy, required this.openaiProxy});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, snapshot) {
        if (snapshot.hasData) {
          return HomeScreen(geminiProxy: geminiProxy, openaiProxy: openaiProxy); // Pass geminiProxy to HomeScreen
        } else {
          return SignInScreen(); // Display the sign-in screen
        }
      },
    );
  }
}

// Sign-in screen with options for Google and Apple Sign-In
class SignInScreen extends StatefulWidget {
  @override
  _SignInScreenState createState() => _SignInScreenState();
}

class _SignInScreenState extends State<SignInScreen> {
  // Function to handle Google Sign-In
  Future<UserCredential> signInWithGoogle() async {
    // Trigger the authentication flow
    final GoogleSignInAccount? googleUser = await GoogleSignIn().signIn();

    // Obtain the auth details from the request
    final GoogleSignInAuthentication? googleAuth =
    await googleUser?.authentication;

    // Create a new credential
    final credential = GoogleAuthProvider.credential(
      accessToken: googleAuth?.accessToken,
      idToken: googleAuth?.idToken,
    );

    // Once signed in, return the UserCredential
    return await FirebaseAuth.instance.signInWithCredential(credential);
  }

  // Function to handle Apple Sign-In (iOS only)
  Future<UserCredential> signInWithApple() async {
    // Request credential for the currently signed in Apple account.
    final appleCredential = await SignInWithApple.getAppleIDCredential(
      scopes: [
        AppleIDAuthorizationScopes.email,
        AppleIDAuthorizationScopes.fullName,
      ],
    );

    // Create a new credential
    final oauthCredential = OAuthProvider("apple.com").credential(
      idToken: appleCredential.identityToken,
      accessToken: appleCredential.authorizationCode,
    );

    // Once signed in, return the UserCredential
    return await FirebaseAuth.instance.signInWithCredential(oauthCredential);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Sign In'),
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Google Sign-In button
            ElevatedButton(
              onPressed: signInWithGoogle,
              child: Text('Sign in with Google'),
            ),
            SizedBox(height: 20),
            // Apple Sign-In button (iOS only)
            if (Theme.of(context).platform == TargetPlatform.iOS)
              SignInWithAppleButton(
                onPressed: signInWithApple,
              ),
          ],
        ),
      ),
    );
  }
}

// Stateful widget for the home screen.
class HomeScreen extends StatefulWidget {
  final GeminiProxy geminiProxy;
  final OpenAiProxy openaiProxy;

  // Constructor requiring the GeminiProxy instance.
  HomeScreen({required this.geminiProxy, required this.openaiProxy});

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
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (context) => SettingsScreen()),
            ),
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
              _buildElevatedButton('Start Sketching!', 'assets/pencil_icon.png', () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => SketchScreen(geminiProxy: widget.geminiProxy, openaiProxy: widget.openaiProxy),
                  ),
                );
              }),
              SizedBox(height: 20),
              _buildElevatedButton('Start Tracing!', 'assets/trace_icon.png', () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => TraceScreen(),
                  ),
                );
              }),
              SizedBox(height: 20),
              _buildElevatedButton('Start Imagen!', 'assets/imagen_icon.png', () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => ImagenScreen(),
                  ),
                );
              }),
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
