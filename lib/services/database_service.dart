import 'package:cloud_firestore/cloud_firestore.dart';

import 'logger_service.dart';
import 'models.dart';

/// Serviço centralizado para operações de base de dados
class DatabaseService {
  static final _instance = DatabaseService._internal();
  
  factory DatabaseService() {
    return _instance;
  }
  
  DatabaseService._internal();

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  
  // Constantes de coleções
  static const String colTarefas = 'tarefas';
  static const String colTodoItems = 'todo_items';
  static const String colSessoes = 'sessoes_concluidas';
  static const String colUtilizadores = 'utilizadores';

  // ─── TAREFAS ────────────────────────────────────────────────────────────────

  /// Cria uma nova tarefa
  Future<String> criarTarefa(Tarefa tarefa) async {
    try {
      final doc = await _firestore
          .collection(colTarefas)
          .add(tarefa.toFirestore());
      
      LoggerService().info('Tarefa criada: ${doc.id}');
      return doc.id;
    } catch (e, stackTrace) {
      LoggerService().error('Erro ao criar tarefa: $e', e, stackTrace);
      throw DatabaseException(
        message: 'Erro ao criar tarefa',
        originalError: e,
        stackTrace: stackTrace,
      );
    }
  }

  /// Atualiza uma tarefa existente
  Future<void> atualizarTarefa(Tarefa tarefa) async {
    try {
      await _firestore
          .collection(colTarefas)
          .doc(tarefa.id)
          .set(tarefa.toFirestore(), SetOptions(merge: true));
      
      LoggerService().info('Tarefa atualizada: ${tarefa.id}');
    } catch (e, stackTrace) {
      LoggerService().error('Erro ao atualizar tarefa: $e', e, stackTrace);
      throw DatabaseException(
        message: 'Erro ao atualizar tarefa',
        originalError: e,
        stackTrace: stackTrace,
      );
    }
  }

  /// Apaga uma tarefa
  Future<void> apagarTarefa(String tarefaId) async {
    try {
      await _firestore
          .collection(colTarefas)
          .doc(tarefaId)
          .delete();
      
      LoggerService().info('Tarefa apagada: $tarefaId');
    } catch (e, stackTrace) {
      LoggerService().error('Erro ao apagar tarefa: $e', e, stackTrace);
      throw DatabaseException(
        message: 'Erro ao apagar tarefa',
        originalError: e,
        stackTrace: stackTrace,
      );
    }
  }

  /// Obtém tarefa por ID
  Future<Tarefa?> obterTarefa(String tarefaId) async {
    try {
      final doc = await _firestore
          .collection(colTarefas)
          .doc(tarefaId)
          .get();
      
      if (!doc.exists) return null;
      return Tarefa.fromFirestore(doc);
    } catch (e, stackTrace) {
      LoggerService().error('Erro ao obter tarefa: $e', e, stackTrace);
      throw DatabaseException(
        message: 'Erro ao obter tarefa',
        originalError: e,
        stackTrace: stackTrace,
      );
    }
  }

  /// Stream de tarefas do utilizador com filtros opcionais
  Stream<List<Tarefa>> obterTarefasStream({
    required String userUid,
    String? status,
    String? materia,
  }) {
    try {
      var query = _firestore
          .collection(colTarefas)
          .where('userUid', isEqualTo: userUid);

      if (status != null && status.isNotEmpty) {
        query = query.where('status', isEqualTo: status);
      }

      if (materia != null && materia.isNotEmpty) {
        query = query.where('materia', isEqualTo: materia);
      }

      return query
          .orderBy('dataCriacao', descending: true)
          .snapshots()
          .map((snapshot) {
            return snapshot.docs
                .map((doc) => Tarefa.fromFirestore(doc))
                .toList();
          })
          .handleError((e) {
            LoggerService().error('Erro no stream de tarefas: $e', e);
            return <Tarefa>[];
          });
    } catch (e, stackTrace) {
      LoggerService().error('Erro ao criar stream de tarefas: $e', e, stackTrace);
      return Stream.error(
        DatabaseException(
          message: 'Erro ao obter tarefas',
          originalError: e,
          stackTrace: stackTrace,
        ),
      );
    }
  }

  /// Obtém tarefas com paginação
  Future<List<Tarefa>> obterTarefasComPaginacao({
    required String userUid,
    DocumentSnapshot? startAfter,
    int limit = 20,
  }) async {
    try {
      var query = _firestore
          .collection(colTarefas)
          .where('userUid', isEqualTo: userUid)
          .orderBy('dataCriacao', descending: true)
          .limit(limit);

      if (startAfter != null) {
        query = query.startAfterDocument(startAfter);
      }

      final snapshot = await query.get();
      return snapshot.docs
          .map((doc) => Tarefa.fromFirestore(doc))
          .toList();
    } catch (e, stackTrace) {
      LoggerService().error('Erro ao obter tarefas com paginação: $e', e, stackTrace);
      throw DatabaseException(
        message: 'Erro ao obter tarefas',
        originalError: e,
        stackTrace: stackTrace,
      );
    }
  }

  // ─── TODO ITEMS ──────────────────────────────────────────────────────────────

  /// Cria um novo item TODO
  Future<String> criarItemTodo(ItemTodo item) async {
    try {
      final doc = await _firestore
          .collection(colTodoItems)
          .add(item.toFirestore());
      
      LoggerService().info('Item TODO criado: ${doc.id}');
      return doc.id;
    } catch (e, stackTrace) {
      LoggerService().error('Erro ao criar item TODO: $e', e, stackTrace);
      throw DatabaseException(
        message: 'Erro ao criar item TODO',
        originalError: e,
        stackTrace: stackTrace,
      );
    }
  }

  /// Atualiza um item TODO
  Future<void> atualizarItemTodo(ItemTodo item) async {
    try {
      await _firestore
          .collection(colTodoItems)
          .doc(item.id)
          .set(item.toFirestore(), SetOptions(merge: true));
      
      LoggerService().info('Item TODO atualizado: ${item.id}');
    } catch (e, stackTrace) {
      LoggerService().error('Erro ao atualizar item TODO: $e', e, stackTrace);
      throw DatabaseException(
        message: 'Erro ao atualizar item TODO',
        originalError: e,
        stackTrace: stackTrace,
      );
    }
  }

  /// Apaga um item TODO
  Future<void> apagarItemTodo(String itemId) async {
    try {
      await _firestore
          .collection(colTodoItems)
          .doc(itemId)
          .delete();
      
      LoggerService().info('Item TODO apagado: $itemId');
    } catch (e, stackTrace) {
      LoggerService().error('Erro ao apagar item TODO: $e', e, stackTrace);
      throw DatabaseException(
        message: 'Erro ao apagar item TODO',
        originalError: e,
        stackTrace: stackTrace,
      );
    }
  }

  /// Stream de itens TODO do utilizador por bloco
  Stream<List<ItemTodo>> obterItensTodoStream({
    required String userUid,
    required String bloco,
  }) {
    try {
      return _firestore
          .collection(colTodoItems)
          .where('userUid', isEqualTo: userUid)
          .where('bloco', isEqualTo: bloco)
          .orderBy('indice')
          .snapshots()
          .map((snapshot) {
            return snapshot.docs
                .map((doc) => ItemTodo.fromFirestore(doc))
                .toList();
          })
          .handleError((e) {
            LoggerService().error('Erro no stream de TODO items: $e', e);
            return <ItemTodo>[];
          });
    } catch (e, stackTrace) {
      LoggerService().error('Erro ao criar stream de TODO items: $e', e, stackTrace);
      return Stream.error(
        DatabaseException(
          message: 'Erro ao obter itens TODO',
          originalError: e,
          stackTrace: stackTrace,
        ),
      );
    }
  }

  // ─── SESSÕES ─────────────────────────────────────────────────────────────────

  /// Registra uma nova sessão de estudo
  Future<String> registarSessao(SessaoConcluida sessao) async {
    try {
      final doc = await _firestore
          .collection(colSessoes)
          .add(sessao.toFirestore());
      
      LoggerService().info('Sessão registada: ${doc.id}');
      return doc.id;
    } catch (e, stackTrace) {
      LoggerService().error('Erro ao registar sessão: $e', e, stackTrace);
      throw DatabaseException(
        message: 'Erro ao registar sessão',
        originalError: e,
        stackTrace: stackTrace,
      );
    }
  }

  /// Obtém sessões do utilizador dentro de um período
  Future<List<SessaoConcluida>> obterSessoesPeriodo({
    required String userUid,
    required DateTime inicio,
    required DateTime fim,
  }) async {
    try {
      final snapshot = await _firestore
          .collection(colSessoes)
          .where('userUid', isEqualTo: userUid)
          .where('dataConclusao', isGreaterThanOrEqualTo: inicio)
          .where('dataConclusao', isLessThanOrEqualTo: fim)
          .orderBy('dataConclusao', descending: true)
          .get();

      return snapshot.docs
          .map((doc) => SessaoConcluida.fromFirestore(doc))
          .toList();
    } catch (e, stackTrace) {
      LoggerService().error('Erro ao obter sessões: $e', e, stackTrace);
      throw DatabaseException(
        message: 'Erro ao obter sessões',
        originalError: e,
        stackTrace: stackTrace,
      );
    }
  }

  /// Stream de sessões recentes do utilizador
  Stream<List<SessaoConcluida>> obterSessoesRecentesStream({
    required String userUid,
    int limit = 10,
  }) {
    try {
      return _firestore
          .collection(colSessoes)
          .where('userUid', isEqualTo: userUid)
          .orderBy('dataConclusao', descending: true)
          .limit(limit)
          .snapshots()
          .map((snapshot) {
            return snapshot.docs
                .map((doc) => SessaoConcluida.fromFirestore(doc))
                .toList();
          })
          .handleError((e) {
            LoggerService().error('Erro no stream de sessões: $e', e);
            return <SessaoConcluida>[];
          });
    } catch (e, stackTrace) {
      LoggerService().error('Erro ao criar stream de sessões: $e', e, stackTrace);
      return Stream.error(
        DatabaseException(
          message: 'Erro ao obter sessões',
          originalError: e,
          stackTrace: stackTrace,
        ),
      );
    }
  }

  // ─── AMIGOS ──────────────────────────────────────────────────────────────────

  /// Adiciona um amigo
  Future<void> adicionarAmigo({
    required String userUid,
    required String amigoUid,
  }) async {
    try {
      await _firestore.collection(colUtilizadores).doc(userUid).set(
        {'amigos': FieldValue.arrayUnion([amigoUid])},
        SetOptions(merge: true),
      );
      
      LoggerService().info('Amigo adicionado: $userUid -> $amigoUid');
    } catch (e, stackTrace) {
      LoggerService().error('Erro ao adicionar amigo: $e', e, stackTrace);
      throw DatabaseException(
        message: 'Erro ao adicionar amigo',
        originalError: e,
        stackTrace: stackTrace,
      );
    }
  }

  /// Remove um amigo
  Future<void> removerAmigo({
    required String userUid,
    required String amigoUid,
  }) async {
    try {
      await _firestore.collection(colUtilizadores).doc(userUid).set(
        {'amigos': FieldValue.arrayRemove([amigoUid])},
        SetOptions(merge: true),
      );
      
      LoggerService().info('Amigo removido: $userUid -> $amigoUid');
    } catch (e, stackTrace) {
      LoggerService().error('Erro ao remover amigo: $e', e, stackTrace);
      throw DatabaseException(
        message: 'Erro ao remover amigo',
        originalError: e,
        stackTrace: stackTrace,
      );
    }
  }

  /// Obtém utilizador pelo username
  Future<PerfilUsuario?> obterUtilizadorPorUsername(String username) async {
    try {
      final snapshot = await _firestore
          .collection(colUtilizadores)
          .where('username', isEqualTo: username)
          .limit(1)
          .get();

      if (snapshot.docs.isEmpty) return null;
      return PerfilUsuario.fromFirestore(snapshot.docs.first);
    } catch (e, stackTrace) {
      LoggerService().error('Erro ao obter utilizador: $e', e, stackTrace);
      throw DatabaseException(
        message: 'Erro ao obter utilizador',
        originalError: e,
        stackTrace: stackTrace,
      );
    }
  }

  // ─── LIMPEZA ─────────────────────────────────────────────────────────────────

  /// Apaga todos os dados de um utilizador (para GDPR)
  Future<void> apagarDadosUtilizador(String userUid) async {
    try {
      final batch = _firestore.batch();

      // Apagar tarefas
      final tarefas = await _firestore
          .collection(colTarefas)
          .where('userUid', isEqualTo: userUid)
          .get();
      
      for (final doc in tarefas.docs) {
        batch.delete(doc.reference);
      }

      // Apagar TODO items
      final todos = await _firestore
          .collection(colTodoItems)
          .where('userUid', isEqualTo: userUid)
          .get();
      
      for (final doc in todos.docs) {
        batch.delete(doc.reference);
      }

      // Apagar sessões
      final sessoes = await _firestore
          .collection(colSessoes)
          .where('userUid', isEqualTo: userUid)
          .get();
      
      for (final doc in sessoes.docs) {
        batch.delete(doc.reference);
      }

      // Apagar utilizador
      batch.delete(
        _firestore.collection(colUtilizadores).doc(userUid),
      );

      await batch.commit();
      LoggerService().info('Dados do utilizador apagados: $userUid');
    } catch (e, stackTrace) {
      LoggerService().error('Erro ao apagar dados: $e', e, stackTrace);
      throw DatabaseException(
        message: 'Erro ao apagar dados',
        originalError: e,
        stackTrace: stackTrace,
      );
    }
  }
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
