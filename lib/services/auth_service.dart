import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import 'logger_service.dart';
import 'models.dart';

/// Serviço de autenticação com Firebase
class AuthService {
  static final _instance = AuthService._internal();
  
  factory AuthService() {
    return _instance;
  }
  
  AuthService._internal();

  final FirebaseAuth _auth = FirebaseAuth.instance;
  final GoogleSignIn _googleSignIn = GoogleSignIn(scopes: ['email', 'profile']);
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  /// Stream do utilizador autenticado
  Stream<User?> get authStateChanges => _auth.authStateChanges();

  /// Utilizador atualmente autenticado
  User? get currentUser => _auth.currentUser;

  /// Faz login com Google
  Future<User?> signInWithGoogle() async {
    try {
      LoggerService().info('Iniciando login com Google...');
      
      final googleUser = await _googleSignIn.signIn();
      if (googleUser == null) {
        LoggerService().info('Login com Google cancelado');
        throw AuthException(message: 'Login cancelado pelo utilizador');
      }

      final googleAuth = await googleUser.authentication;
      final credential = GoogleAuthProvider.credential(
        accessToken: googleAuth.accessToken,
        idToken: googleAuth.idToken,
      );

      final userCredential = await _auth.signInWithCredential(credential);
      final user = userCredential.user;

      if (user != null) {
        await _criarPerfilSeNaoExistir(user);
        LoggerService().info('Login com Google bem-sucedido: ${user.email}');
      }

      return user;
    } on FirebaseAuthException catch (e) {
      LoggerService().error('FirebaseAuthException: ${e.message}', e);
      throw AuthException(
        message: _parseAuthError(e),
        originalError: e,
      );
    } catch (e, stackTrace) {
      LoggerService().error('Erro no login com Google: $e', e, stackTrace);
      throw AuthException(
        message: 'Erro ao fazer login com Google',
        originalError: e,
        stackTrace: stackTrace,
      );
    }
  }

  /// Faz logout
  Future<void> logout() async {
    try {
      LoggerService().info('Realizando logout...');
      
      await Future.wait([
        _auth.signOut(),
        _googleSignIn.signOut(),
      ]);
      
      LoggerService().info('Logout bem-sucedido');
    } catch (e, stackTrace) {
      LoggerService().error('Erro no logout: $e', e, stackTrace);
      throw AuthException(
        message: 'Erro ao fazer logout',
        originalError: e,
        stackTrace: stackTrace,
      );
    }
  }

  /// Carrega o perfil do utilizador
  Future<PerfilUsuario?> carregarPerfil(String uid) async {
    try {
      final doc = await _firestore.collection('utilizadores').doc(uid).get();
      
      if (!doc.exists) {
        LoggerService().warning('Perfil não encontrado para UID: $uid');
        return null;
      }

      return PerfilUsuario.fromFirestore(doc);
    } catch (e, stackTrace) {
      LoggerService().error('Erro ao carregar perfil: $e', e, stackTrace);
      throw DatabaseException(
        message: 'Erro ao carregar perfil',
        originalError: e,
        stackTrace: stackTrace,
      );
    }
  }

  /// Atualiza o perfil do utilizador
  Future<void> atualizarPerfil(PerfilUsuario perfil) async {
    try {
      await _firestore
          .collection('utilizadores')
          .doc(perfil.uid)
          .set(perfil.toFirestore(), SetOptions(merge: true));
      
      LoggerService().info('Perfil atualizado: ${perfil.uid}');
    } catch (e, stackTrace) {
      LoggerService().error('Erro ao atualizar perfil: $e', e, stackTrace);
      throw DatabaseException(
        message: 'Erro ao atualizar perfil',
        originalError: e,
        stackTrace: stackTrace,
      );
    }
  }

  /// Verifica se um username está disponível
  Future<bool> verificarUsernameDisponivel(String username) async {
    try {
      final query = await _firestore
          .collection('utilizadores')
          .where('username', isEqualTo: username)
          .limit(1)
          .get();
      
      return query.docs.isEmpty;
    } catch (e, stackTrace) {
      LoggerService().error('Erro ao verificar disponibilidade: $e', e, stackTrace);
      throw DatabaseException(
        message: 'Erro ao verificar username',
        originalError: e,
        stackTrace: stackTrace,
      );
    }
  }

  /// Cria perfil padrão se não existir
  Future<void> _criarPerfilSeNaoExistir(User user) async {
    try {
      final uid = user.uid;
      final doc = await _firestore.collection('utilizadores').doc(uid).get();
      
      if (!doc.exists) {
        final perfil = PerfilUsuario(
          uid: uid,
          email: user.email ?? '',
          nomePerfil: user.displayName,
          fotoPerfil: user.photoURL,
          dataCriacao: DateTime.now(),
        );

        await _firestore
            .collection('utilizadores')
            .doc(uid)
            .set(perfil.toFirestore());

        LoggerService().info('Novo perfil criado: $uid');
      }
    } catch (e, stackTrace) {
      LoggerService().error('Erro ao criar perfil: $e', e, stackTrace);
      // Não relança a exceção pois o utilizador conseguiu fazer login
    }
  }

  /// Parseia erros de autenticação
  String _parseAuthError(FirebaseAuthException e) {
    switch (e.code) {
      case 'account-exists-with-different-credential':
        return 'A conta já existe com um método de login diferente';
      case 'invalid-credential':
        return 'Credenciais inválidas';
      case 'operation-not-allowed':
        return 'Operação não permitida';
      case 'user-disabled':
        return 'Conta desativada';
      case 'user-not-found':
        return 'Utilizador não encontrado';
      case 'wrong-password':
        return 'Palavra-passe incorreta';
      case 'invalid-email':
        return 'Email inválido';
      case 'email-already-in-use':
        return 'Email já está em uso';
      case 'weak-password':
        return 'Palavra-passe muito fraca';
      case 'network-request-failed':
        return 'Erro de rede. Verifique a sua conexão';
      default:
        return 'Erro de autenticação: ${e.message}';
    }
  }
}

/// Exceção de autenticação
class AuthException implements Exception {
  final String message;
  final dynamic originalError;
  final StackTrace? stackTrace;

  AuthException({
    required this.message,
    this.originalError,
    this.stackTrace,
  });

  @override
  String toString() => message;
}

/// Exceção de base de dados
class DatabaseException implements Exception {
  final String message;
  final dynamic originalError;
  final StackTrace? stackTrace;

  DatabaseException({
    required this.message,
    this.originalError,
    this.stackTrace,
  });

  @override
  String toString() => message;
}
