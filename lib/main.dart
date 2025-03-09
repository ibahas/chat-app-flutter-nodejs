import 'package:chat_app/models/user_model.dart';
import 'package:chat_app/providers/admin_provider.dart';
import 'package:chat_app/providers/auth_provider.dart';
import 'package:chat_app/providers/chat_provider.dart';
import 'package:chat_app/providers/voice_provider.dart'; // Import VoiceMessageProvider
import 'package:chat_app/screens/auth/login_screen.dart';
import 'package:chat_app/screens/home/home_screen.dart';
import 'package:chat_app/screens/splash_screen.dart';
import 'package:chat_app/services/websocket_service.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized(); // Add this line
  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => AuthProvider()),
        ChangeNotifierProvider(create: (_) => ChatProvider()),
        ChangeNotifierProvider(
            create: (_) => AdminProvider()), // ADD ADMIN PROVIDER HERE

        ChangeNotifierProvider(
            create: (_) => VoiceMessageProvider()), // Add VoiceMessageProvider
        //New for websocket
        Provider(create: (_) => WebSocketService()),
      ],
      child: const MyApp(),
    ),
  );
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Secure Group Chat',
      theme: ThemeData(
        primarySwatch: Colors.blue,
        visualDensity: VisualDensity.adaptivePlatformDensity,
      ),
      debugShowCheckedModeBanner: false,
      home: Consumer<AuthProvider>(
        builder: (context, authProvider, child) {
          // While initializing, show a splash screen
          if (authProvider.isInitializing) {
            return const SplashScreen();
          }

          // After initialization, direct to appropriate screen
          return authProvider.isAuthenticated
              ? HomeScreen(
                  isAdmin: authProvider.currentUser?.role == UserRole.admin,
                ) // Pass isAdmin
              : const LoginScreen();
        },
      ),
    );
  }
}
