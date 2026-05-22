import 'package:cloud_firestore/cloud_firestore.dart';

class Sessao {
  final String id;
  final String tarefaId;
  final String tarefaNome;
  final DateTime dataInicio;
  final DateTime? dataFim;
  final int ciclosCompletos;
  final int totalFocoSegundos;
  final int totalDescansoSegundos;
  final bool concluida;

  Sessao({
    required this.id,
    required this.tarefaId,
    required this.tarefaNome,
    required this.dataInicio,
    this.dataFim,
    required this.ciclosCompletos,
    required this.totalFocoSegundos,
    required this.totalDescansoSegundos,
    required this.concluida,
  });

  Map<String, dynamic> toMap() {
    return {
      'tarefaId': tarefaId,
      'tarefaNome': tarefaNome,
      'dataInicio': Timestamp.fromDate(dataInicio),
      'dataFim': dataFim != null ? Timestamp.fromDate(dataFim!) : null,
      'ciclosCompletos': ciclosCompletos,
      'totalFocoSegundos': totalFocoSegundos,
      'totalDescansoSegundos': totalDescansoSegundos,
      'concluida': concluida,
    };
  }

  factory Sessao.fromMap(String id, Map<String, dynamic> map) {
    return Sessao(
      id: id,
      tarefaId: map['tarefaId'] ?? '',
      tarefaNome: map['tarefaNome'] ?? '',
      dataInicio: (map['dataInicio'] as Timestamp).toDate(),
      dataFim: (map['dataFim'] as Timestamp?)?.toDate(),
      ciclosCompletos: map['ciclosCompletos'] ?? 0,
      totalFocoSegundos: map['totalFocoSegundos'] ?? 0,
      totalDescansoSegundos: map['totalDescansoSegundos'] ?? 0,
      concluida: map['concluida'] ?? false,
    );
  }

  String get duracaoFormatada {
    final total = totalFocoSegundos + totalDescansoSegundos;
    final h = total ~/ 3600;
    final m = (total % 3600) ~/ 60;
    if (h > 0) return "${h}h ${m}min";
    return "${m}min";
  }

  String get dataFormatada {
    return "${dataInicio.day.toString().padLeft(2, '0')}/"
        "${dataInicio.month.toString().padLeft(2, '0')}/"
        "${dataInicio.year}";
  }
}
