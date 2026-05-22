import 'package:flutter/material.dart';
import '../services/database_service.dart';
import '../models/sessao.dart';

class TelaInsights extends StatefulWidget {
  const TelaInsights({super.key});

  @override
  State<TelaInsights> createState() => _TelaInsightsState();
}

class _TelaInsightsState extends State<TelaInsights> {
  final DatabaseService _db = DatabaseService();
  static const Color _azul = Color(0xFF1D81C7);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: const Text("Insights", style: TextStyle(color: Colors.white)),
        backgroundColor: Colors.black,
        iconTheme: const IconThemeData(color: Colors.white),
        bottom: const PreferredSize(
          preferredSize: Size.fromHeight(1),
          child: Divider(color: _azul, height: 1),
        ),
      ),
      body: FutureBuilder<Map<String, dynamic>>(
        future: _db.calcularEstatisticas(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator(color: _azul));
          }
          if (snapshot.hasError) {
            return Center(child: Text("Erro ao carregar dados", style: TextStyle(color: Colors.white.withOpacity(0.5))));
          }

          final stats = snapshot.data!;

          return SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 8),
                const Text("Resumo Geral", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: _azul)),
                const SizedBox(height: 16),

                // Cards de estatísticas
                Row(
                  children: [
                    Expanded(child: _statCard("Sessões\nTotais", "${stats['totalSessoes']}", Icons.bar_chart)),
                    const SizedBox(width: 12),
                    Expanded(child: _statCard("Concluídas", "${stats['sessoesCompletas']}", Icons.check_circle_outline)),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(child: _statCard("Foco Total", "${stats['totalFocoMinutos']} min", Icons.timer_outlined)),
                    const SizedBox(width: 12),
                    Expanded(child: _statCard("Ciclos\nCompletos", "${stats['totalCiclos']}", Icons.repeat)),
                  ],
                ),

                if ((stats['tarefaMaisEstudada'] as String).isNotEmpty) ...[
                  const SizedBox(height: 24),
                  const Text("Tarefa mais estudada", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: _azul)),
                  const SizedBox(height: 10),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      border: Border.all(color: _azul.withOpacity(0.4)),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.star_outline, color: _azul, size: 28),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            stats['tarefaMaisEstudada'],
                            style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w500),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],

                const SizedBox(height: 30),

                // Histórico de sessões
                const Text("Histórico de Sessões", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: _azul)),
                const SizedBox(height: 16),

                StreamBuilder<List<Sessao>>(
                  stream: _db.streamSessoes(),
                  builder: (context, snap) {
                    if (snap.connectionState == ConnectionState.waiting) {
                      return const Center(child: Padding(
                        padding: EdgeInsets.all(20),
                        child: CircularProgressIndicator(color: _azul),
                      ));
                    }

                    final sessoes = snap.data ?? [];

                    if (sessoes.isEmpty) {
                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 30),
                        child: Center(
                          child: Text(
                            "Ainda sem sessões registadas.\nInicia uma tarefa para começar!",
                            textAlign: TextAlign.center,
                            style: TextStyle(color: Colors.white.withOpacity(0.4), height: 1.5),
                          ),
                        ),
                      );
                    }

                    return ListView.builder(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: sessoes.length,
                      itemBuilder: (context, i) => _sessaoTile(sessoes[i]),
                    );
                  },
                ),

                const SizedBox(height: 30),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _statCard(String titulo, String valor, IconData icone) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        border: Border.all(color: Colors.white.withOpacity(0.1)),
        borderRadius: BorderRadius.circular(12),
        color: Colors.white.withOpacity(0.03),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icone, color: _azul, size: 22),
          const SizedBox(height: 10),
          Text(valor, style: const TextStyle(fontSize: 26, fontWeight: FontWeight.bold, color: Colors.white)),
          const SizedBox(height: 4),
          Text(titulo, style: TextStyle(fontSize: 12, color: Colors.white.withOpacity(0.5), height: 1.3)),
        ],
      ),
    );
  }

  Widget _sessaoTile(Sessao sessao) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        border: Border.all(color: Colors.white.withOpacity(0.08)),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          Container(
            width: 40, height: 40,
            decoration: BoxDecoration(
              color: sessao.concluida ? _azul.withOpacity(0.2) : Colors.white.withOpacity(0.05),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(
              sessao.concluida ? Icons.check : Icons.stop_circle_outlined,
              color: sessao.concluida ? _azul : Colors.white38,
              size: 20,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(sessao.tarefaNome.isEmpty ? "Sem nome" : sessao.tarefaNome,
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
                const SizedBox(height: 3),
                Text(
                  "${sessao.dataFormatada} · ${sessao.ciclosCompletos} ciclos · ${sessao.duracaoFormatada}",
                  style: TextStyle(color: Colors.white.withOpacity(0.45), fontSize: 12),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
