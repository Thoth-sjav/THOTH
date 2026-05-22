import 'package:cloud_firestore/cloud_firestore.dart';

class Tarefa {
  String id;
  String nome;
  int estudo;
  int descanso;
  int ciclos;
  double progressoSalvo;
  DateTime? criadaEm;

  Tarefa({
    required this.id,
    this.nome = "",
    this.estudo = 1500,
    this.descanso = 300,
    this.ciclos = 4,
    this.progressoSalvo = 0.0,
    this.criadaEm,
  });

  Map<String, dynamic> toMap() {
    return {
      'nome': nome,
      'estudo': estudo,
      'descanso': descanso,
      'ciclos': ciclos,
      'progressoSalvo': progressoSalvo,
      'criadaEm': criadaEm != null
          ? Timestamp.fromDate(criadaEm!)
          : FieldValue.serverTimestamp(),
    };
  }

  factory Tarefa.fromMap(String id, Map<String, dynamic> map) {
    return Tarefa(
      id: id,
      nome: map['nome'] ?? '',
      estudo: map['estudo'] ?? 1500,
      descanso: map['descanso'] ?? 300,
      ciclos: map['ciclos'] ?? 4,
      progressoSalvo: (map['progressoSalvo'] ?? 0.0).toDouble(),
      criadaEm: (map['criadaEm'] as Timestamp?)?.toDate(),
    );
  }

  Tarefa copyWith({
    String? id,
    String? nome,
    int? estudo,
    int? descanso,
    int? ciclos,
    double? progressoSalvo,
  }) {
    return Tarefa(
      id: id ?? this.id,
      nome: nome ?? this.nome,
      estudo: estudo ?? this.estudo,
      descanso: descanso ?? this.descanso,
      ciclos: ciclos ?? this.ciclos,
      progressoSalvo: progressoSalvo ?? this.progressoSalvo,
      criadaEm: criadaEm,
    );
  }
}
