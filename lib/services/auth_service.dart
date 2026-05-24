import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import 'logger_service.dart';
import 'models.dart';

class AuthService {
  static final _instance = AuthService._internal();

  factory AuthService() => _instance;
  AuthService._internal();

  final FirebaseAuth _auth = FirebaseAuth.instance;
  final GoogleSignIn _googleSignIn =
      GoogleSignIn(scopes: ['email', 'profile']);
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  Stream<User?> get authStateChanges => _auth.authStateChanges();
  User? get currentUser => _auth.currentUser;

  /// LOGIN GOOGLE (CORRIGIDO)
  Future<User?> signInWithGoogle() async {
    try {
      final googleUser = await _googleSignIn.signIn();

      if (googleUser == null) return null;

      final googleAuth = await googleUser.authentication;

      final credential = GoogleAuthProvider.credential(
        accessToken: googleAuth.accessToken,
        idToken: googleAuth.idToken,
      );

      final currentUser = _auth.currentUser;

      late UserCredential userCredential;

      /// 🔥 FIX PRINCIPAL: evitar criar novo UID
      if (currentUser != null && currentUser.isAnonymous) {
        userCredential =
            await currentUser.linkWithCredential(credential);
      } else {
        userCredential =
            await _auth.signInWithCredential(credential);
      }

      final user = userCredential.user;

      if (user != null) {
        await _ensureUserDocument(user);
      }

      return user;
    } catch (e) {
      LoggerService().error('Erro login Google: $e', e);
      rethrow;
    }
  }

  /// 🔥 GARANTE PERFIL NO FIRESTORE
  Future<void> _ensureUserDocument(User user) async {
    final ref =
        _firestore.collection('utilizadores').doc(user.uid);

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
        }
      });
    } else {
      await ref.set({
        'email': user.email ?? '',
        'name': user.displayName ?? '',
        'photoURL': user.photoURL ?? '',
      }, SetOptions(merge: true));
    }
  }

  Future<void> logout() async {
    await _auth.signOut();
    await _googleSignIn.signOut();
  }
}
