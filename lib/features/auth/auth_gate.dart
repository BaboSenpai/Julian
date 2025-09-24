import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart' as fb_auth;
import 'package:van_inventory/ui/screens.dart'; // HomeScreen
import 'sign_in_page.dart'; // dein bestehender Login

class AuthGate extends StatelessWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<fb_auth.User?>(
      stream: fb_auth.FirebaseAuth.instance.authStateChanges(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(body: Center(child: CircularProgressIndicator()));
        }
        if (snapshot.hasData) {
          // ✅ Eingeloggt: zeige dein ursprüngliches Home/Dashboard
          return const HomeScreen();
        } else {
          // ❌ Nicht eingeloggt: zeige deinen vorhandenen Login
          return const SignInPage();
        }
      },
    );
  }
}
