import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class AuthService {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final GoogleSignIn _googleSignIn = GoogleSignIn();

  /// LOGIN GOOGLE (ESTÁVEL)
  Future<User?> signInWithGoogle() async {
    final GoogleSignInAccount? googleUser =
        await _googleSignIn.signIn();

    if (googleUser == null) {
      return null;
    }

    final GoogleSignInAuthentication googleAuth =
        await googleUser.authentication;

    final credential = GoogleAuthProvider.credential(
      accessToken: googleAuth.accessToken,
      idToken: googleAuth.idToken,
    );

    final userCredential =
        await _auth.signInWithCredential(credential);

    final user = userCredential.user;

    if (user != null) {
      await _createUserIfNotExists(user);
    }

    return user;
  }

  /// CRIAR PERFIL FIRESTORE
  Future<void> _createUserIfNotExists(User user) async {
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
        },
        'stats': {
          'xp': 0,
          'level': 1,
          'tasks': 0,
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

  Future<void> signOut() async {
    await _auth.signOut();
    await _googleSignIn.signOut();
  }

  User? get currentUser => _auth.currentUser;
}
