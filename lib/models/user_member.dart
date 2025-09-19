class UserMember {
  UserMember({
    required this.id,
    required this.email,
    required this.role,
    this.uid,
  });

  final String id; // Firestore Doc-ID
  final String email;
  final String role; // 'admin' | 'member'
  final String? uid;

  UserMember copyWith({String? role, String? uid}) {
    return UserMember(
      id: id,
      email: email,
      role: role ?? this.role,
      uid: uid ?? this.uid,
    );
  }
}
