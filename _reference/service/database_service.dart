import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../models/tarefa.dart';
import '../models/sessao.dart';
import '../models/perfil_usuario.dart';

class DatabaseService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  String get _uid => FirebaseAuth.instance.currentUser!.uid;

  // ─── Referências ───────────────────────────────────────────────────────────

  DocumentReference get _perfilRef => _db.collection('users').doc(_uid);

  CollectionReference get _tarefasRef =>
      _db.collection('users').doc(_uid).collection('tarefas');

  CollectionReference get _sessoesRef =>
      _db.collection('users').doc(_uid).collection('sessoes');

  // ─── Perfil ────────────────────────────────────────────────────────────────

  Future<void> guardarPerfil(PerfilUsuario perfil) async {
    await _perfilRef.set(perfil.toMap(), SetOptions(merge: true));
  }

  Future<PerfilUsuario> carregarPerfil() async {
    final doc = await _perfilRef.get();
    if (!doc.exists) return PerfilUsuario();
    return PerfilUsuario.fromMap(doc.data() as Map<String, dynamic>);
  }

  // ─── Tarefas ───────────────────────────────────────────────────────────────

  Stream<List<Tarefa>> streamTarefas() {
    return _tarefasRef
        .orderBy('criadaEm', descending: false)
        .snapshots()
        .map((snapshot) => snapshot.docs
            .map((doc) =>
                Tarefa.fromMap(doc.id, doc.data() as Map<String, dynamic>))
            .toList());
  }

  Future<void> guardarTarefa(Tarefa tarefa) async {
    await _tarefasRef.doc(tarefa.id).set(tarefa.toMap());
  }

  Future<void> atualizarProgressoTarefa(String tarefaId, double progresso) async {
    await _tarefasRef.doc(tarefaId).update({'progressoSalvo': progresso});
  }

  Future<void> removerTarefa(String tarefaId) async {
    await _tarefasRef.doc(tarefaId).delete();
  }

  // ─── Sessões ───────────────────────────────────────────────────────────────

  Future<void> guardarSessao(Sessao sessao) async {
    await _sessoesRef.add(sessao.toMap());
  }

  Stream<List<Sessao>> streamSessoes() {
    return _sessoesRef
        .orderBy('dataInicio', descending: true)
        .snapshots()
        .map((snapshot) => snapshot.docs
            .map((doc) =>
                Sessao.fromMap(doc.id, doc.data() as Map<String, dynamic>))
            .toList());
  }

  Future<List<Sessao>> carregarSessoes({int limite = 50}) async {
    final snapshot = await _sessoesRef
        .orderBy('dataInicio', descending: true)
        .limit(limite)
        .get();
    return snapshot.docs
        .map((doc) =>
            Sessao.fromMap(doc.id, doc.data() as Map<String, dynamic>))
        .toList();
  }

  // ─── Estatísticas ──────────────────────────────────────────────────────────

  Future<Map<String, dynamic>> calcularEstatisticas() async {
    final sessoes = await carregarSessoes(limite: 500);

    if (sessoes.isEmpty) {
      return {
        'totalSessoes': 0,
        'sessoesCompletas': 0,
        'totalFocoMinutos': 0,
        'totalDescansoMinutos': 0,
        'totalCiclos': 0,
        'mediaCiclosPorSessao': 0.0,
        'tarefaMaisEstudada': '',
      };
    }

    int totalFoco = 0;
    int totalDescanso = 0;
    int totalCiclos = 0;
    int sessoesCompletas = 0;
    Map<String, int> contagemTarefas = {};

    for (final s in sessoes) {
      totalFoco += s.totalFocoSegundos;
      totalDescanso += s.totalDescansoSegundos;
      totalCiclos += s.ciclosCompletos;
      if (s.concluida) sessoesCompletas++;
      contagemTarefas[s.tarefaNome] =
          (contagemTarefas[s.tarefaNome] ?? 0) + 1;
    }

    final tarefaMaisEstudada = contagemTarefas.entries.isEmpty
        ? ''
        : contagemTarefas.entries
            .reduce((a, b) => a.value >= b.value ? a : b)
            .key;

    return {
      'totalSessoes': sessoes.length,
      'sessoesCompletas': sessoesCompletas,
      'totalFocoMinutos': totalFoco ~/ 60,
      'totalDescansoMinutos': totalDescanso ~/ 60,
      'totalCiclos': totalCiclos,
      'mediaCiclosPorSessao': totalCiclos / sessoes.length,
      'tarefaMaisEstudada': tarefaMaisEstudada,
    };
  }
}
