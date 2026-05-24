import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class DatabaseService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  DocumentReference<Map<String, dynamic>> _ref(String uid) {
    return _db.collection('users').doc(uid);
  }

  Future<Map<String, dynamic>?> getUser() async {
    final uid = FirebaseAuth.instance.currentUser!.uid;

    final doc = await _ref(uid).get();
    return doc.data();
  }

  Future<void> updateProfile(Map<String, dynamic> data) async {
    final uid = FirebaseAuth.instance.currentUser!.uid;

    await _ref(uid).set(data, SetOptions(merge: true));
  }

  Future<void> updateSettings(Map<String, dynamic> settings) async {
    final uid = FirebaseAuth.instance.currentUser!.uid;

    await _ref(uid).set({
      'settings': settings,
    }, SetOptions(merge: true));
  }

  Future<void> addXP(int xp) async {
    final uid = FirebaseAuth.instance.currentUser!.uid;

    await _db.runTransaction((tx) async {
      final ref = _ref(uid);
      final snap = await tx.get(ref);

      final data = snap.data() ?? {};
      final stats = data['stats'] ?? {'xp': 0};

      tx.update(ref, {
        'stats.xp': (stats['xp'] ?? 0) + xp,
      });
    });
  }
}
