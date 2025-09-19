// lib/features/auth/auth_gate.dart
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart' as fb_auth;

/// AuthGate zeigt:
/// - ein Anmelde/Registrier-Formular, wenn kein User eingeloggt ist
/// - eine einfache "Angemeldet"-Seite mit Abmelden-Button, wenn eingeloggt
///
/// Hinweis: Der Konstruktor erwartet `signedIn`, damit er zu deinem
/// bisherigen Aufruf aus main.dart kompatibel ist. Wir nutzen es hier
/// nicht aktiv, da wir ÃƒÆ’Ã‚Â¼ber den Auth-Stream reagieren.
class AuthGate extends StatelessWidget {
  const AuthGate({super.key, required this.signedIn});

  final bool signedIn;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<fb_auth.User?>(
      stream: fb_auth.FirebaseAuth.instance.authStateChanges(),
      builder: (context, snap) {
        final user = snap.data;
        if (user != null) {
          return _SignedInScreen(user: user);
        }
        return const _EmailPasswordForm();
      },
    );
  }
}

/// ---------- Eingeloggt-Ansicht ----------
class _SignedInScreen extends StatelessWidget {
  const _SignedInScreen({required this.user});

  final fb_auth.User user;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Angemeldet')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              'Eingeloggt als:\n${user.email ?? user.uid}',
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 18),
            ),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: () async {
                await fb_auth.FirebaseAuth.instance.signOut();
              },
              child: const Text('Abmelden'),
            ),
          ],
        ),
      ),
    );
  }
}

/// ---------- E-Mail/Passwort Formular ----------
class _EmailPasswordForm extends StatefulWidget {
  const _EmailPasswordForm();

  @override
  State<_EmailPasswordForm> createState() => _EmailPasswordFormState();
}

class _EmailPasswordFormState extends State<_EmailPasswordForm> {
  final _emailCtrl = TextEditingController();
  final _passCtrl = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  bool _busy = false;

  @override
  void dispose() {
    _emailCtrl.dispose();
    _passCtrl.dispose();
    super.dispose();
  }

  String _friendlyAuthError(fb_auth.FirebaseAuthException e) {
    switch (e.code) {
      case 'invalid-email':
        return 'Die E-Mail-Adresse ist ungÃƒÆ’Ã‚Â¼ltig.';
      case 'email-already-in-use':
        return 'FÃƒÆ’Ã‚Â¼r diese E-Mail existiert bereits ein Konto.';
      case 'weak-password':
        return 'Das Passwort ist zu schwach (mind. 6 Zeichen).';
      case 'user-not-found':
        return 'Kein Benutzer mit dieser E-Mail gefunden.';
      case 'wrong-password':
        return 'Das Passwort ist falsch.';
      case 'too-many-requests':
        return 'Zu viele Versuche. Bitte spÃƒÆ’Ã‚Â¤ter erneut versuchen.';
      case 'network-request-failed':
        return 'Keine Internetverbindung.';
      default:
        return 'Fehler: ${e.message ?? e.code}';
    }
  }

  Future<void> _createAccount() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _busy = true);
    try {
      await fb_auth.FirebaseAuth.instance.createUserWithEmailAndPassword(
        email: _emailCtrl.text.trim(),
        password: _passCtrl.text,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Konto erstellt ÃƒÂ¢Ã¢â€šÂ¬Ã¢â‚¬Â angemeldet.')),
      );
    } on fb_auth.FirebaseAuthException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(_friendlyAuthError(e))));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Unerwarteter Fehler: $e')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _signIn() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _busy = true);
    try {
      await fb_auth.FirebaseAuth.instance.signInWithEmailAndPassword(
        email: _emailCtrl.text.trim(),
        password: _passCtrl.text,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Erfolgreich angemeldet.')));
    } on fb_auth.FirebaseAuthException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(_friendlyAuthError(e))));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Unerwarteter Fehler: $e')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Anmelden')),
      body: AbsorbPointer(
        absorbing: _busy,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Form(
            key: _formKey,
            child: ListView(
              children: [
                const SizedBox(height: 16),
                TextFormField(
                  controller: _emailCtrl,
                  decoration: const InputDecoration(labelText: 'E-Mail'),
                  keyboardType: TextInputType.emailAddress,
                  autofillHints: const [AutofillHints.email],
                  validator: (v) {
                    if (v == null || v.trim().isEmpty) {
                      return 'Bitte E-Mail eingeben.';
                    }
                    if (!v.contains('@')) return 'UngÃƒÆ’Ã‚Â¼ltige E-Mail.';
                    return null;
                  },
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _passCtrl,
                  decoration: const InputDecoration(labelText: 'Passwort'),
                  obscureText: true,
                  validator: (v) {
                    if (v == null || v.isEmpty) return 'Bitte Passwort eingeben.';
                    if (v.length < 6) return 'Mindestens 6 Zeichen.';
                    return null;
                  },
                ),
                const SizedBox(height: 24),
                ElevatedButton(
                  onPressed: _createAccount,
                  child: _busy
                      ? const SizedBox(
                          height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Text('Konto erstellen'),
                ),
                const SizedBox(height: 8),
                TextButton(
                  onPressed: _signIn,
                  child: const Text('Schon Konto? Einloggen'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
