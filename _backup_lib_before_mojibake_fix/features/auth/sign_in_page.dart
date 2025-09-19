// lib/features/auth/sign_in_page.dart
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart' as fb_auth;

class SignInPage extends StatefulWidget {
  const SignInPage({super.key});
  @override
  State<SignInPage> createState() => _SignInPageState();
}

class _SignInPageState extends State<SignInPage> {
  final email = TextEditingController();
  final pw = TextEditingController();
  bool isRegister = false;
  String? error;

  Future<void> _submit() async {
    try {
      if (isRegister) {
        await fb_auth.FirebaseAuth.instance.createUserWithEmailAndPassword(
          email: email.text.trim(),
          password: pw.text.trim(),
        );
      } else {
        await fb_auth.FirebaseAuth.instance.signInWithEmailAndPassword(
          email: email.text.trim(),
          password: pw.text.trim(),
        );
      }
    } on fb_auth.FirebaseAuthException catch (e) {
      setState(() => error = e.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Anmelden')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            TextField(
              controller: email,
              keyboardType: TextInputType.emailAddress,
              decoration: const InputDecoration(labelText: 'E-Mail'),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: pw,
              obscureText: true,
              decoration: const InputDecoration(labelText: 'Passwort'),
            ),
            if (error != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(error!, style: const TextStyle(color: Colors.red)),
              ),
            const SizedBox(height: 12),
            FilledButton(onPressed: _submit, child: Text(isRegister ? 'Konto erstellen' : 'Anmelden')),
            TextButton(
              onPressed: () => setState(() => isRegister = !isRegister),
              child: Text(isRegister ? 'Schon Konto? Einloggen' : 'Neu hier? Registrieren'),
            ),
            if (!isRegister)
              TextButton(
                onPressed: () async {
                  if (email.text.trim().isEmpty) {
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('E-Mail eingeben')));
                    return;
                  }
                  await fb_auth.FirebaseAuth.instance
                      .sendPasswordResetEmail(email: email.text.trim());
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Passwort-Reset gesendet')));
                  }
                },
                child: const Text('Passwort vergessen?'),
              ),
          ],
        ),
      ),
    );
  }
}
