import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class DatabaseService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  DocumentReference<Map<String, dynamic>> _ref() {
    final uid = FirebaseAuth.instance.currentUser!.uid;
    return _db.collection('users').doc(uid);
  }

  Future<Map<String, dynamic>?> getUser() async {
    final doc = await _ref().get();
    return doc.data();
  }

  Future<void> updateUser(Map<String, dynamic> data) async {
    await _ref().set(data, SetOptions(merge: true));
  }

  Future<void> updateSettings(Map<String, dynamic> settings) async {
    await _ref().set({
      'settings': settings,
    }, SetOptions(merge: true));
  }
}
