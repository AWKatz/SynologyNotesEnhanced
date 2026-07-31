/// A note's sharing state. Verified against `.docs/reference/Note Sharing
/// and Permissions*.har` and `.docs/reference/Share RW*.har`: `Note.get`'s
/// `acl` field looks like `{"enabled":true,"public":{"perm":"ro"},
/// "dsm_group":{"101":{"name":"administrators","perm":"ro"}},
/// "dsm_user":{"1024":{"name":"admin","perm":"rw"}}}`. Both "ro" and "rw"
/// are confirmed perm values (rw only directly captured on a user share,
/// but the wire shape is identical across public/group/user).
class NoteGroupShare {
  final String groupId;
  final String name;
  final String perm;

  const NoteGroupShare(
      {required this.groupId, required this.name, required this.perm});
}

class NoteUserShare {
  final String uid;
  final String name;
  final String perm;

  const NoteUserShare(
      {required this.uid, required this.name, required this.perm});
}

class NoteAcl {
  final bool enabled;
  final String? publicPerm; // null = no public link
  final List<NoteGroupShare> groups;
  final List<NoteUserShare> users;

  const NoteAcl({
    this.enabled = false,
    this.publicPerm,
    this.groups = const [],
    this.users = const [],
  });

  factory NoteAcl.fromJson(Map<String, dynamic>? json) {
    if (json == null || json.isEmpty) return const NoteAcl();
    final public = json['public'] as Map<String, dynamic>?;
    final dsmGroup = json['dsm_group'] as Map<String, dynamic>?;
    final dsmUser = json['dsm_user'] as Map<String, dynamic>?;
    return NoteAcl(
      enabled: json['enabled'] as bool? ?? false,
      publicPerm: public?['perm'] as String?,
      groups: dsmGroup?.entries.map((e) {
            final v = e.value as Map<String, dynamic>;
            return NoteGroupShare(
              groupId: e.key,
              name: v['name'] as String? ?? '',
              perm: v['perm'] as String? ?? 'ro',
            );
          }).toList() ??
          const [],
      users: dsmUser?.entries.map((e) {
            final v = e.value as Map<String, dynamic>;
            return NoteUserShare(
              uid: e.key,
              name: v['name'] as String? ?? '',
              perm: v['perm'] as String? ?? 'ro',
            );
          }).toList() ??
          const [],
    );
  }

  bool get isShared =>
      enabled && (publicPerm != null || groups.isNotEmpty || users.isNotEmpty);
}
