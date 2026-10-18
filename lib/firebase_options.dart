import 'package:firebase_core/firebase_core.dart';

/// Values from google-services.json (Firebase console -> Project settings -> your Android app).
/// They are not secrets: every installed app contains them.
class DefaultFirebaseOptions {
  static const String _apiKey = 'AIzaSyCEjOiEwi2xGnoxUETp8mHCHrfd2w6se9s';
  static const String _appId = '1:460112027055:android:02a43f305038a1e61e635a';
  static const String _senderId = '460112027055';
  static const String _projectId = 'mvp-353a6';

  static bool get isConfigured => !_apiKey.startsWith('PASTE');

  static const FirebaseOptions android = FirebaseOptions(
    apiKey: _apiKey,
    appId: _appId,
    messagingSenderId: _senderId,
    projectId: _projectId,
  );
}
