import 'package:cloud_firestore/cloud_firestore.dart';

class DatabaseService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  DocumentReference<Map<String, dynamic>> _ref(String uid) {
    return _firestore.collection('utilizadores').doc(uid);
  }

  /// LER UTILIZADOR
  Future<Map<String, dynamic>?> getUser(String uid) async {
    final doc = await _ref(uid).get();
    return doc.data();
  }

  /// ATUALIZAR PERFIL
  Future<void> updateProfile(
      String uid, Map<String, dynamic> data) async {
    await _ref(uid).set(data, SetOptions(merge: true));
  }

  /// ATUALIZAR SETTINGS
  Future<void> updateSettings(
      String uid, Map<String, dynamic> settings) async {
    await _ref(uid).set({
      'settings': settings,
    }, SetOptions(merge: true));
  }

  /// ADICIONAR XP
  Future<void> addXP(String uid, int xp) async {
    await _firestore.runTransaction((tx) async {
      final doc = await tx.get(_ref(uid));

      final data = doc.data() ?? {};
      final stats = data['stats'] ?? {'xp': 0};

      final currentXP = stats['xp'] ?? 0;

      tx.update(_ref(uid), {
        'stats.xp': currentXP + xp,
      });
    });
  }

  /// INCREMENTAR TASKS
  Future<void> incrementTasks(String uid) async {
    await _ref(uid).set({
      'stats': {
        'tasks': FieldValue.increment(1),
      }
    }, SetOptions(merge: true));
  }
}
