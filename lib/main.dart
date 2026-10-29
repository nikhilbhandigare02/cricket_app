import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'screens/admin_home.dart';
import 'widgets/animations.dart';
import 'screens/login_screen.dart';
import 'screens/owner_home.dart';
import 'services/db.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    // Reads android/app/google-services.json (see README).
    await Firebase.initializeApp().timeout(const Duration(seconds: 15));
  } catch (e) {
    runApp(MaterialApp(
      home: Scaffold(
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text(
              'Firebase failed to initialize.\n'
              'Check that android/app/google-services.json exists.\n\n$e',
              textAlign: TextAlign.center,
            ),
          ),
        ),
      ),
    ));
    return;
  }
  runApp(const AplLeagueApp());
}

ThemeData _theme() {
  final scheme = ColorScheme.fromSeed(seedColor: const Color(0xFF1B7F4B));
  final fieldBorder = OutlineInputBorder(
    borderRadius: BorderRadius.circular(12),
    borderSide: BorderSide(color: Colors.grey.shade300),
  );
  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: const Color(0xFFF2F6F3),
    appBarTheme: AppBarTheme(
      backgroundColor: scheme.primary,
      foregroundColor: scheme.onPrimary,
      centerTitle: true,
      elevation: 0,
      scrolledUnderElevation: 0,
    ),
    cardTheme: CardThemeData(
      color: Colors.white,
      elevation: 1.5,
      shadowColor: Colors.black26,
      surfaceTintColor: Colors.transparent,
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
    ),
    pageTransitionsTheme: const PageTransitionsTheme(builders: {
      TargetPlatform.android: FadeForwardsPageTransitionsBuilder(),
    }),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: const Color(0xFFF6F8F7),
      border: fieldBorder,
      enabledBorder: fieldBorder,
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: scheme.primary, width: 1.6),
      ),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: Colors.white,
      surfaceTintColor: Colors.transparent,
      indicatorColor: scheme.primaryContainer,
      elevation: 8,
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 20),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    ),
    floatingActionButtonTheme: FloatingActionButtonThemeData(
      backgroundColor: scheme.primary,
      foregroundColor: scheme.onPrimary,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: Colors.white,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
    ),
    bottomSheetTheme: const BottomSheetThemeData(
      backgroundColor: Colors.white,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
    ),
  );
}

class AplLeagueApp extends StatelessWidget {
  const AplLeagueApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'APL League',
      debugShowCheckedModeBanner: false,
      theme: _theme(),
      builder: (context, child) {
        final showFooter = MediaQuery.of(context).viewInsets.bottom == 0;
        return Column(children: [
          Expanded(
            child: MediaQuery.removePadding(
              context: context,
              removeBottom: showFooter,
              child: child!,
            ),
          ),
          if (showFooter)
            Material(
              color: const Color(0xFFE3EBE6),
              child: SafeArea(
                top: false,
                child: SizedBox(
                  width: double.infinity,
                  height: 24,
                  child: Center(
                    child: Text(
                      'Developed by Nikhil Bhandigare',
                      style: TextStyle(
                        fontSize: 11,
                        letterSpacing: 0.3,
                        color: Colors.grey.shade700,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ]);
      },
      home: const AuthGate(),
    );
  }
}

/// Shows login, or the admin / owner home depending on users/{uid}.role.
class AuthGate extends StatelessWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Scaffold(body: AplLoader());
        }
        final user = snap.data;
        if (user == null) return const LoginScreen();
        return FutureBuilder<Map<String, dynamic>?>(
          future: Db.profile(user.uid),
          builder: (context, p) {
            if (p.connectionState != ConnectionState.done) {
              return const Scaffold(body: AplLoader());
            }
            final profile = p.data;
            if (profile == null) {
              return Scaffold(
                appBar: AppBar(title: const Text('APL League')),
                body: Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Text('No role assigned to this account.\nAsk the admin to set it up.',
                            textAlign: TextAlign.center),
                        const SizedBox(height: 16),
                        FilledButton(onPressed: Db.signOut, child: const Text('Logout')),
                      ],
                    ),
                  ),
                ),
              );
            }
            if (profile['role'] == 'admin') return const AdminHome();
            return OwnerHome(ownerId: profile['ownerId'] ?? '', ownerName: profile['name'] ?? 'Owner');
          },
        );
      },
    );
  }
}
