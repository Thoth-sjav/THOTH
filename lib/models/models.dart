import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:equatable/equatable.dart';

/// Representa uma tarefa de estudo
class Tarefa extends Equatable {
  /// ID único da tarefa (gerado pelo Firestore)
  final String id;
  
  /// UID do utilizador proprietário
  final String userUid;
  
  /// Título da tarefa
  final String titulo;
  
  /// Descrição opcional
  final String? descricao;
  
  /// Duração estimada em minutos
  final int duracaoEstimada;
  
  /// Prioridade (1-5, onde 5 é máxima)
  final int prioridade;
  
  /// Status: 'pendente', 'em_progresso', 'concluida'
  final String status;
  
  /// Data de criação
  final DateTime dataCriacao;
  
  /// Data de conclusão (se concluida)
  final DateTime? dataConclusao;
  
  /// Matéria/Disciplina
  final String materia;
  
  /// Sessões de estudo realizadas
  final List<String> sessoes;

  const Tarefa({
    required this.id,
    required this.userUid,
    required this.titulo,
    this.descricao,
    required this.duracaoEstimada,
    this.prioridade = 3,
    this.status = 'pendente',
    required this.dataCriacao,
    this.dataConclusao,
    required this.materia,
    this.sessoes = const [],
  });

  /// Converte para documento Firestore
  Map<String, dynamic> toFirestore() {
    return {
      'titulo': titulo,
      'descricao': descricao,
      'duracaoEstimada': duracaoEstimada,
      'prioridade': prioridade,
      'status': status,
      'dataCriacao': dataCriacao,
      'dataConclusao': dataConclusao,
      'materia': materia,
      'sessoes': sessoes,
      'userUid': userUid,
    };
  }

  /// Cria instância a partir do Firestore
  factory Tarefa.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return Tarefa(
      id: doc.id,
      userUid: data['userUid'] ?? '',
      titulo: data['titulo'] ?? '',
      descricao: data['descricao'],
      duracaoEstimada: data['duracaoEstimada'] ?? 25,
      prioridade: data['prioridade'] ?? 3,
      status: data['status'] ?? 'pendente',
      dataCriacao: (data['dataCriacao'] as Timestamp).toDate(),
      dataConclusao: data['dataConclusao'] != null 
          ? (data['dataConclusao'] as Timestamp).toDate() 
          : null,
      materia: data['materia'] ?? '',
      sessoes: List<String>.from(data['sessoes'] ?? []),
    );
  }

  /// Cria cópia com campos opcionais modificados
  Tarefa copyWith({
    String? id,
    String? userUid,
    String? titulo,
    String? descricao,
    int? duracaoEstimada,
    int? prioridade,
    String? status,
    DateTime? dataCriacao,
    DateTime? dataConclusao,
    String? materia,
    List<String>? sessoes,
  }) {
    return Tarefa(
      id: id ?? this.id,
      userUid: userUid ?? this.userUid,
      titulo: titulo ?? this.titulo,
      descricao: descricao ?? this.descricao,
      duracaoEstimada: duracaoEstimada ?? this.duracaoEstimada,
      prioridade: prioridade ?? this.prioridade,
      status: status ?? this.status,
      dataCriacao: dataCriacao ?? this.dataCriacao,
      dataConclusao: dataConclusao ?? this.dataConclusao,
      materia: materia ?? this.materia,
      sessoes: sessoes ?? this.sessoes,
    );
  }

  @override
  List<Object?> get props => [
    id,
    userUid,
    titulo,
    descricao,
    duracaoEstimada,
    prioridade,
    status,
    dataCriacao,
    dataConclusao,
    materia,
    sessoes,
  ];
}

/// Representa um item da lista TODO
class ItemTodo extends Equatable {
  final String id;
  final String userUid;
  final String titulo;
  final bool concluido;
  final int indice;
  final DateTime dataCriacao;
  final String bloco; // 'morning', 'afternoon', 'evening', 'night'

  const ItemTodo({
    required this.id,
    required this.userUid,
    required this.titulo,
    this.concluido = false,
    required this.indice,
    required this.dataCriacao,
    required this.bloco,
  });

  Map<String, dynamic> toFirestore() {
    return {
      'titulo': titulo,
      'concluido': concluido,
      'indice': indice,
      'dataCriacao': dataCriacao,
      'bloco': bloco,
      'userUid': userUid,
    };
  }

  factory ItemTodo.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return ItemTodo(
      id: doc.id,
      userUid: data['userUid'] ?? '',
      titulo: data['titulo'] ?? '',
      concluido: data['concluido'] ?? false,
      indice: data['indice'] ?? 0,
      dataCriacao: (data['dataCriacao'] as Timestamp).toDate(),
      bloco: data['bloco'] ?? 'morning',
    );
  }

  ItemTodo copyWith({
    String? id,
    String? userUid,
    String? titulo,
    bool? concluido,
    int? indice,
    DateTime? dataCriacao,
    String? bloco,
  }) {
    return ItemTodo(
      id: id ?? this.id,
      userUid: userUid ?? this.userUid,
      titulo: titulo ?? this.titulo,
      concluido: concluido ?? this.concluido,
      indice: indice ?? this.indice,
      dataCriacao: dataCriacao ?? this.dataCriacao,
      bloco: bloco ?? this.bloco,
    );
  }

  @override
  List<Object?> get props => [
    id,
    userUid,
    titulo,
    concluido,
    indice,
    dataCriacao,
    bloco,
  ];
}

/// Perfil do utilizador
class PerfilUsuario extends Equatable {
  final String uid;
  final String email;
  final String? username;
  final String? nomePerfil;
  final String? fotoPerfil;
  final int duracaoPadrao;
  final int pausaPadrao;
  final int pausaLongaPadrao;
  final bool notificacoesAtivas;
  final DateTime dataCriacao;
  final List<String> amigos;
  final int freezesDisponiveis;

  const PerfilUsuario({
    required this.uid,
    required this.email,
    this.username,
    this.nomePerfil,
    this.fotoPerfil,
    this.duracaoPadrao = 25,
    this.pausaPadrao = 5,
    this.pausaLongaPadrao = 15,
    this.notificacoesAtivas = true,
    required this.dataCriacao,
    this.amigos = const [],
    this.freezesDisponiveis = 2,
  });

  Map<String, dynamic> toFirestore() {
    return {
      'email': email,
      'username': username,
      'nomePerfil': nomePerfil,
      'fotoPerfil': fotoPerfil,
      'duracaoPadrao': duracaoPadrao,
      'pausaPadrao': pausaPadrao,
      'pausaLongaPadrao': pausaLongaPadrao,
      'notificacoesAtivas': notificacoesAtivas,
      'dataCriacao': dataCriacao,
      'amigos': amigos,
      'freezesDisponiveis': freezesDisponiveis,
    };
  }

  factory PerfilUsuario.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return PerfilUsuario(
      uid: doc.id,
      email: data['email'] ?? '',
      username: data['username'],
      nomePerfil: data['nomePerfil'],
      fotoPerfil: data['fotoPerfil'],
      duracaoPadrao: data['duracaoPadrao'] ?? 25,
      pausaPadrao: data['pausaPadrao'] ?? 5,
      pausaLongaPadrao: data['pausaLongaPadrao'] ?? 15,
      notificacoesAtivas: data['notificacoesAtivas'] ?? true,
      dataCriacao: (data['dataCriacao'] as Timestamp).toDate(),
      amigos: List<String>.from(data['amigos'] ?? []),
      freezesDisponiveis: data['freezesDisponiveis'] ?? 2,
    );
  }

  PerfilUsuario copyWith({
    String? uid,
    String? email,
    String? username,
    String? nomePerfil,
    String? fotoPerfil,
    int? duracaoPadrao,
    int? pausaPadrao,
    int? pausaLongaPadrao,
    bool? notificacoesAtivas,
    DateTime? dataCriacao,
    List<String>? amigos,
    int? freezesDisponiveis,
  }) {
    return PerfilUsuario(
      uid: uid ?? this.uid,
      email: email ?? this.email,
      username: username ?? this.username,
      nomePerfil: nomePerfil ?? this.nomePerfil,
      fotoPerfil: fotoPerfil ?? this.fotoPerfil,
      duracaoPadrao: duracaoPadrao ?? this.duracaoPadrao,
      pausaPadrao: pausaPadrao ?? this.pausaPadrao,
      pausaLongaPadrao: pausaLongaPadrao ?? this.pausaLongaPadrao,
      notificacoesAtivas: notificacoesAtivas ?? this.notificacoesAtivas,
      dataCriacao: dataCriacao ?? this.dataCriacao,
      amigos: amigos ?? this.amigos,
      freezesDisponiveis: freezesDisponiveis ?? this.freezesDisponiveis,
    );
  }

  @override
  List<Object?> get props => [
    uid,
    email,
    username,
    nomePerfil,
    fotoPerfil,
    duracaoPadrao,
    pausaPadrao,
    pausaLongaPadrao,
    notificacoesAtivas,
    dataCriacao,
    amigos,
    freezesDisponiveis,
  ];
}

/// Sessão de estudo concluida
class SessaoConcluida extends Equatable {
  final String id;
  final String userUid;
  final String tarefaId;
  final int ciclosCompletos;
  final int ciclosPausa;
  final int duracaoTotal; // segundos
  final DateTime dataConclusao;
  final List<String> reacoes; // emojis de reação de amigos

  const SessaoConcluida({
    required this.id,
    required this.userUid,
    required this.tarefaId,
    required this.ciclosCompletos,
    required this.ciclosPausa,
    required this.duracaoTotal,
    required this.dataConclusao,
    this.reacoes = const [],
  });

  Map<String, dynamic> toFirestore() {
    return {
      'userUid': userUid,
      'tarefaId': tarefaId,
      'ciclosCompletos': ciclosCompletos,
      'ciclosPausa': ciclosPausa,
      'duracaoTotal': duracaoTotal,
      'dataConclusao': dataConclusao,
      'reacoes': reacoes,
    };
  }

  factory SessaoConcluida.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return SessaoConcluida(
      id: doc.id,
      userUid: data['userUid'] ?? '',
      tarefaId: data['tarefaId'] ?? '',
      ciclosCompletos: data['ciclosCompletos'] ?? 0,
      ciclosPausa: data['ciclosPausa'] ?? 0,
      duracaoTotal: data['duracaoTotal'] ?? 0,
      dataConclusao: (data['dataConclusao'] as Timestamp).toDate(),
      reacoes: List<String>.from(data['reacoes'] ?? []),
    );
  }

  @override
  List<Object?> get props => [
    id,
    userUid,
    tarefaId,
    ciclosCompletos,
    ciclosPausa,
    duracaoTotal,
    dataConclusao,
    reacoes,
  ];
}

/// Informações de streak do utilizador
class StreakInfo extends Equatable {
  final int dias;
  final DateTime? ultimoEstudo;
  final bool frozenHoje;

  const StreakInfo({
    this.dias = 0,
    this.ultimoEstudo,
    this.frozenHoje = false,
  });

  @override
  List<Object?> get props => [dias, ultimoEstudo, frozenHoje];
}
