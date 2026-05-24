import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_sign_in/google_sign_in.dart';

class AuthService {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  /// LOGIN COM GOOGLE (CORRIGIDO + SEM PERDA DE DADOS)
  Future<UserCredential> signInWithGoogle() async {
    final GoogleSignIn googleSignIn = GoogleSignIn();

    final GoogleSignInAccount? googleUser = await googleSignIn.signIn();

    if (googleUser == null) {
      throw Exception("Login cancelado pelo utilizador");
    }

    final GoogleSignInAuthentication googleAuth =
        await googleUser.authentication;

    final AuthCredential credential = GoogleAuthProvider.credential(
      accessToken: googleAuth.accessToken,
      idToken: googleAuth.idToken,
    );

    final User? currentUser = _auth.currentUser;

    late UserCredential userCredential;

    /// 🔥 IMPORTANTE: evita criação de novo UID
    if (currentUser != null && currentUser.isAnonymous) {
      userCredential =
          await currentUser.linkWithCredential(credential);
    } else {
      userCredential =
          await _auth.signInWithCredential(credential);
    }

    final user = userCredential.user;

    if (user != null) {
      await _createUserIfNotExists(user);
    }

    return userCredential;
  }

  /// 🔥 CRIA PERFIL NO FIRESTORE (SE NÃO EXISTIR)
  Future<void> _createUserIfNotExists(User user) async {
    final docRef = _firestore.collection('users').doc(user.uid);

    final doc = await docRef.get();

    if (!doc.exists) {
      await docRef.set({
        'uid': user.uid,
        'email': user.email ?? '',
        'name': user.displayName ?? '',
        'photoURL': user.photoURL ?? '',
        'createdAt': FieldValue.serverTimestamp(),

        // defaults da tua app
        'settings': {
          'pomodoroTime': 25,
          'breakTime': 5,
          'soundEnabled': true,
        }
      });
    } else {
      // garante atualização mínima sem apagar dados
      await docRef.set({
        'email': user.email ?? '',
        'name': user.displayName ?? '',
        'photoURL': user.photoURL ?? '',
      }, SetOptions(merge: true));
    }
  }

  /// LOGOUT
  Future<void> signOut() async {
    await _auth.signOut();
    await GoogleSignIn().signOut();
  }

  /// USER ATUAL
  User? get currentUser => _auth.currentUser;
}
