import 'package:chat_app/models/user_model.dart';
import 'package:chat_app/providers/auth_provider.dart';
import 'package:chat_app/providers/chat_provider.dart';
import 'package:chat_app/providers/voice_provider.dart';
import 'package:chat_app/screens/auth/login_screen.dart';
import 'package:chat_app/screens/home/home_screen.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'sample_feature/sample_item_details_view.dart';
import 'sample_feature/sample_item_list_view.dart';
import 'settings/settings_controller.dart';
import 'settings/settings_view.dart';

/// The Widget that configures your application.
class MyApp extends StatelessWidget {
  const MyApp({
    super.key,
    required this.settingsController,
  });

  final SettingsController settingsController;

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      // Use MultiProvider
      providers: [
        ChangeNotifierProvider(create: (_) => AuthProvider()),
        ChangeNotifierProvider(create: (_) => ChatProvider()),
        ChangeNotifierProvider(
            create: (_) => VoiceMessageProvider()), // Add VoiceMessageProvider
      ],
      child: ListenableBuilder(
        listenable: settingsController,
        builder: (BuildContext context, Widget? child) {
          return MaterialApp(
            // Title of the app.
            restorationScopeId: 'app',
            // SettingsController to display the correct theme.
            theme: ThemeData(),
            darkTheme: ThemeData.dark(),
            themeMode: settingsController.themeMode,
            //Debuging mode false.
            debugShowCheckedModeBanner: false,
            // Flutter web url navigation and deep linking.
            onGenerateRoute: (RouteSettings routeSettings) {
              return MaterialPageRoute(
                settings: routeSettings,
                builder: (BuildContext context) {
                  switch (routeSettings.name) {
                    case SettingsView.routeName:
                      return SettingsView(controller: settingsController);
                    case SampleItemDetailsView.routeName:
                      return const SampleItemDetailsView();
                    case SampleItemListView.routeName:
                    default:
                      // Check authentication status and navigate accordingly
                      final authProvider =
                          Provider.of<AuthProvider>(context, listen: false);
                      if (authProvider.isAuthenticated) {
                        return HomeScreen(
                          isAdmin:
                              authProvider.currentUser?.role == UserRole.admin,
                        );
                      } else {
                        return const LoginScreen();
                      }
                  }
                },
              );
            },
          );
        },
      ),
    );
  }
}
