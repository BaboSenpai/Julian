//lib/ui/team_tab.dart
import 'package:flutter/material.dart';

// alle Models inkl. UserMember
import 'package:van_inventory/models/models.dart';

// globale Listen/State (falls hier z. B. items/teamMembers genutzt werden)
import 'package:van_inventory/models/state.dart';




class TeamTab extends StatelessWidget {
  const TeamTab({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<UserMember>>(
      stream: Cloud.watchMembers(),
      builder: (context, snap) {
        if (!snap.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final members = snap.data!;
        return Scaffold(
          body: ListView.separated(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 80),
            itemCount: members.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (_, i) {
              final m = members[i];
              return ListTile(
                leading: CircleAvatar(child: Text(m.email.isNotEmpty ? m.email[0].toUpperCase() : '?')),
                title: Text(m.email),
                subtitle: Text('Rolle: ${m.role}${m.uid == null ? ' • (noch nicht registriert)' : ''}'),
                trailing: PopupMenuButton<String>(
                  onSelected: (v) async {
                    if (v == 'admin' || v == 'member') {
                      await Cloud.updateMemberRole(m.id, v);
                    } else if (v == 'delete') {
                      final ok = await showDialog<bool>(
                        context: context,
                        builder: (ctx) => AlertDialog(
                          title: const Text('Benutzer entfernen?'),
                          content: Text('„${m.email}“ wirklich aus dem Team entfernen?'),
                          actions: [
                            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Abbrechen')),
                            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Entfernen')),
                          ],
                        ),
                      );
                      if (ok == true) await Cloud.removeMember(m.id);
                    } else if (v == 'reset') {
                      await fb_auth.FirebaseAuth.instance.sendPasswordResetEmail(email: m.email);
                      // ignore: use_build_context_synchronously
                      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Reset-Mail gesendet')));
                    }
                  },
                  itemBuilder: (_) => const [
                    PopupMenuItem(value: 'admin', child: Text('Rolle: Admin')),
                    PopupMenuItem(value: 'member', child: Text('Rolle: Member')),
                    PopupMenuDivider(),
                    PopupMenuItem(value: 'reset', child: Text('Passwort zurücksetzen')),
                    PopupMenuDivider(),
                    PopupMenuItem(
                      value: 'delete',
                      child: Text('Aus Team entfernen', style: TextStyle(color: Colors.red)),
                    ),
                  ],
                ),
              );
            },
          ),
          floatingActionButton: FloatingActionButton.extended(
            icon: const Icon(Icons.person_add),
            label: const Text('Benutzer hinzufügen'),
            onPressed: () async {
              final emailCtrl = TextEditingController();
              String role = 'member';
              final ok = await showDialog<bool>(
                context: context,
                builder: (ctx) => StatefulBuilder(
                  builder: (ctx, setSB) => AlertDialog(
                    title: const Text('Benutzer einladen'),
                    content: Column(mainAxisSize: MainAxisSize.min, children: [
                      TextField(controller: emailCtrl, keyboardType: TextInputType.emailAddress, decoration: const InputDecoration(labelText: 'E-Mail')),
                      const SizedBox(height: 8),
                      DropdownButtonFormField<String>(
                        value: role,
                        decoration: const InputDecoration(labelText: 'Rolle'),
                        items: const [
                          DropdownMenuItem(value: 'member', child: Text('Member')),
                          DropdownMenuItem(value: 'admin', child: Text('Admin')),
                        ],
                        onChanged: (v) => setSB(() => role = v ?? 'member'),
                      ),
                      const SizedBox(height: 8),
                      const Text('Der Nutzer registriert sich mit dieser E-Mail in der App. '
                          'Beim ersten Login wird er automatisch dem Team zugeordnet.'),
                    ]),
                    actions: [
                      TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Abbrechen')),
                      FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Einladen')),
                    ],
                  ),
                ),
              );
              if (ok == true) {
                await Cloud.addMemberByEmail(emailCtrl.text.trim(), role: role);
              }
            },
          ),
        );
      },
    );
  }
}
