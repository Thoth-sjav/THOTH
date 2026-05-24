import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class DatabaseService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  /// REFERÊNCIA BASE DO UTILIZADOR ATUAL
  DocumentReference<Map<String, dynamic>> _userRef(String uid) {
    return _firestore.collection('utilizadores').doc(uid);
  }

  /// 🔥 CRIAR OU GARANTIR UTILIZADOR
  Future<void> ensureUserExists(User user) async {
    final ref = _userRef(user.uid);

    final doc = await ref.get();

    if (!doc.exists) {
      await ref.set({
        'uid': user.uid,
        'email': user.email ?? '',
        'name': user.displayName ?? '',
        'photoURL': user.photoURL ?? '',
        'createdAt': FieldValue.serverTimestamp(),

        'settings': {
          'pomodoro': 25,
          'break': 5,
          'sound': true,
        },

        'stats': {
          'xp': 0,
          'level': 1,
          'tasksCompleted': 0,
        }
      });
    } else {
      // Atualização leve sem apagar dados
      await ref.set({
        'email': user.email ?? '',
        'name': user.displayName ?? '',
        'photoURL': user.photoURL ?? '',
      }, SetOptions(merge: true));
    }
  }

  /// 🔥 GUARDAR SETTINGS
  Future<void> updateSettings(String uid, Map<String, dynamic> settings) async {
    await _userRef(uid).set({
      'settings': settings,
    }, SetOptions(merge: true));
  }

  /// 🔥 LER SETTINGS
  Future<Map<String, dynamic>?> getSettings(String uid) async {
    final doc = await _userRef(uid).get();

    final data = doc.data();
    if (data == null) return null;

    return data['settings'] as Map<String, dynamic>?;
  }

  /// 🔥 ATUALIZAR PERFIL
  Future<void> updateProfile(String uid, Map<String, dynamic> data) async {
    await _userRef(uid).set(data, SetOptions(merge: true));
  }

  /// 🔥 LER PERFIL COMPLETO
  Future<Map<String, dynamic>?> getUser(String uid) async {
    final doc = await _userRef(uid).get();
    return doc.data();
  }

  /// 🔥 ADICIONAR XP / STATS
  Future<void> addXP(String uid, int xpToAdd) async {
    final ref = _userRef(uid);

    await _firestore.runTransaction((transaction) async {
      final snapshot = await transaction.get(ref);

      final data = snapshot.data() ?? {};

      final stats = data['stats'] ?? {
        'xp': 0,
        'level': 1,
        'tasksCompleted': 0,
      };

      final currentXP = stats['xp'] ?? 0;

      transaction.update(ref, {
        'stats.xp': currentXP + xpToAdd,
      });
    });
  }

  /// 🔥 INCREMENTAR TAREFAS
  Future<void> incrementTasks(String uid) async {
    await _userRef(uid).set({
      'stats': {
        'tasksCompleted': FieldValue.increment(1),
      }
    }, SetOptions(merge: true));
  }
}
