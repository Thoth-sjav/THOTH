import 'dart:async';
// ignore: unused_import
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);
  runApp(const ThothApp());
}

// =============================================================================
// MODELOS
// =============================================================================

class Tarefa {
  String id;
  String nome;
  int estudo;
  int descanso;
  int ciclos;
  double progressoSalvo;
  int cicloSalvo;
  bool estavaNoDescanso;
  int segundosSalvos;

  Tarefa({
    required this.id,
    this.nome = '',
    this.estudo = 1500,
    this.descanso = 300,
    this.ciclos = 4,
    this.progressoSalvo = 0.0,
    this.cicloSalvo = 1,
    this.estavaNoDescanso = false,
    this.segundosSalvos = 1500,
  });

  Tarefa clone() => Tarefa(
        id: id,
        nome: nome,
        estudo: estudo,
        descanso: descanso,
        ciclos: ciclos,
        progressoSalvo: progressoSalvo,
        cicloSalvo: cicloSalvo,
        estavaNoDescanso: estavaNoDescanso,
        segundosSalvos: segundosSalvos,
      );

  /// Tempo total estimado em segundos (todos os ciclos de estudo + descanso)
  int get tempoTotalSegundos => ciclos * estudo + (ciclos - 1) * descanso;
}

class ItemTodo {
  String id;
  String texto;
  String dataHora;
  bool concluido;

  ItemTodo({
    required this.id,
    required this.texto,
    required this.dataHora,
    this.concluido = false,
  });
}

class PerfilUsuario {
  String nome;
  String nomedeutilizador;
  String descricao;
  String motivos;

  PerfilUsuario({
    this.nome = '',
    this.nomedeutilizador = '',
    this.descricao = '',
    this.motivos = '',
  });
}

/// Registo imutável de uma sessão concluída
class SessaoConcluida {
  final String tarefaNome;
  final DateTime dataConclusao;
  final int ciclosConcluidos;
  final int tempoFocoSegundos;

  const SessaoConcluida({
    required this.tarefaNome,
    required this.dataConclusao,
    required this.ciclosConcluidos,
    required this.tempoFocoSegundos,
  });
}

// =============================================================================
// APP PRINCIPAL
// =============================================================================

class ThothApp extends StatelessWidget {
  const ThothApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Thoth',
      theme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: Colors.black,
        primaryColor: const Color(0xFF1D81C7),
        cardColor: Colors.black,
        dividerColor: Colors.white24,
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFF1D81C7),
          surface: Colors.black,
        ),
        appBarTheme: const AppBarTheme(
          backgroundColor: Colors.black,
          foregroundColor: Colors.white,
          elevation: 0,
          centerTitle: false,
          titleTextStyle: TextStyle(
            color: Colors.white,
            fontSize: 20,
            fontWeight: FontWeight.bold,
          ),
        ),
        sliderTheme: const SliderThemeData(
          activeTrackColor: Color(0xFF1D81C7),
          thumbColor: Color(0xFF1D81C7),
          overlayColor: Color(0x291D81C7),
          inactiveTrackColor: Color(0x33FFFFFF),
        ),
      ),
      home: const PomodoroApp(),
    );
  }
}

// =============================================================================
// ESTADO CENTRAL
// =============================================================================

enum EstadoApp { inicio, cronometro, fim, gerenciar }

class _PomodoroAppState extends State<PomodoroApp>
    with WidgetsBindingObserver {
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();

  static const Color _azul = Color(0xFF1D81C7);
  static const Color _preto = Colors.black;
  static const Color _branco = Colors.white;

  // Dados
  List<Tarefa> tarefas = [
    Tarefa(id: '1', nome: 'Revisão de Matemática', estudo: 1800, descanso: 600, ciclos: 3),
    Tarefa(id: '2', nome: 'Leitura de Filosofia', estudo: 2700, descanso: 900, ciclos: 2),
    Tarefa(id: '3', nome: 'Projecto Thoth (Code)', estudo: 5400, descanso: 1200, ciclos: 4),
    Tarefa(id: '4', nome: 'Prática de Inglês', estudo: 3600, descanso: 300, ciclos: 6),
  ];

  List<ItemTodo> notasTodo = [];
  List<SessaoConcluida> sessoes = [];
  PerfilUsuario perfil = PerfilUsuario();

  // Estado do timer
  Tarefa? ultimaTarefa;
  Tarefa? tarefaAtual;
  EstadoApp estadoApp = EstadoApp.inicio;
  int cicloAtual = 1;
  bool estaNoDescanso = false;
  int segundosRestantes = 0;
  Timer? _timer;
  bool pausado = false;

  // ---------------------------------------------------------------------------
  // CICLO DE VIDA
  // ---------------------------------------------------------------------------

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    _timer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  /// Pausa automática quando a app vai para background
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused && estadoApp == EstadoApp.cronometro) {
      if (!pausado) {
        setState(() => pausado = true);
        _salvarEstadoAtual();
      }
    }
  }

  // ---------------------------------------------------------------------------
  // LÓGICA POMODORO
  // ---------------------------------------------------------------------------

  void iniciarTarefa(Tarefa t, {bool retomar = false}) {
    _timer?.cancel();
    setState(() {
      tarefaAtual = t;
      estadoApp = EstadoApp.cronometro;
      pausado = false;

      if (!retomar) {
        cicloAtual = 1;
        estaNoDescanso = false;
        segundosRestantes = t.estudo;
      } else {
        cicloAtual = t.cicloSalvo.clamp(1, t.ciclos);
        estaNoDescanso = t.estavaNoDescanso;
        // Garante que segundosSalvos é válido
        final duracaoFase = estaNoDescanso ? t.descanso : t.estudo;
        segundosRestantes = (t.segundosSalvos > 0 && t.segundosSalvos <= duracaoFase)
            ? t.segundosSalvos
            : duracaoFase;
      }
    });

    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (pausado || tarefaAtual == null) return;

      if (segundosRestantes > 1) {
        setState(() {
          segundosRestantes--;
          _salvarEstadoAtual();
        });
      } else {
        _salvarEstadoAtual();
        _avancarFase();
      }
    });
  }

  void _salvarEstadoAtual() {
    if (tarefaAtual == null) return;
    tarefaAtual!
      ..cicloSalvo = cicloAtual
      ..estavaNoDescanso = estaNoDescanso
      ..segundosSalvos = segundosRestantes
      ..progressoSalvo = _calcularProgressoGlobal();
    ultimaTarefa = tarefaAtual;
  }

  double _calcularProgressoGlobal() {
    if (tarefaAtual == null) return 0.0;
    final totalFase = estaNoDescanso ? tarefaAtual!.descanso : tarefaAtual!.estudo;
    final progressoFase = totalFase <= 0 ? 0.0 : (1 - (segundosRestantes / totalFase));
    final global = ((cicloAtual - 1) + progressoFase) / tarefaAtual!.ciclos;
    return global.clamp(0.0, 1.0);
  }

  void _avancarFase() {
    if (tarefaAtual == null) return;

    if (!estaNoDescanso) {
      // Ciclo de estudo acabou
      if (cicloAtual >= tarefaAtual!.ciclos) {
        // Último ciclo concluído → finalizar
        finalizar();
        return;
      }
      // Ainda há ciclos → ir para descanso
      setState(() {
        estaNoDescanso = true;
        segundosRestantes = tarefaAtual!.descanso;
        _salvarEstadoAtual();
      });
    } else {
      // Descanso acabou → próximo ciclo de estudo
      setState(() {
        cicloAtual++;
        estaNoDescanso = false;
        segundosRestantes = tarefaAtual!.estudo;
        _salvarEstadoAtual();
      });
    }
  }

  void pularFase() {
    if (tarefaAtual == null) return;
    _avancarFase();
  }

  void alternarPausa() {
    setState(() => pausado = !pausado);
  }

  void descartarProgresso() {
    setState(() {
      if (ultimaTarefa != null) {
        ultimaTarefa!
          ..progressoSalvo = 0.0
          ..cicloSalvo = 1
          ..estavaNoDescanso = false
          ..segundosSalvos = ultimaTarefa!.estudo;
      }
      ultimaTarefa = null;
    });
  }

  void finalizar() {
    _timer?.cancel();
    if (tarefaAtual != null) {
      final t = tarefaAtual!;
      t
        ..progressoSalvo = 1.0
        ..cicloSalvo = t.ciclos
        ..estavaNoDescanso = false
        ..segundosSalvos = 0;
      ultimaTarefa = t;

      // Registar sessão concluída
      sessoes.add(SessaoConcluida(
        tarefaNome: t.nome.isEmpty ? 'Sem nome' : t.nome,
        dataConclusao: DateTime.now(),
        ciclosConcluidos: t.ciclos,
        tempoFocoSegundos: t.ciclos * t.estudo,
      ));
    }
    setState(() => estadoApp = EstadoApp.fim);
  }

  void reset() {
    _timer?.cancel();
    if (tarefaAtual != null &&
        tarefaAtual!.progressoSalvo > 0.0 &&
        tarefaAtual!.progressoSalvo < 1.0) {
      _salvarEstadoAtual();
      ultimaTarefa = tarefaAtual;
    }
    setState(() {
      estadoApp = EstadoApp.inicio;
      tarefaAtual = null;
      pausado = false;
    });
  }

  void removerTarefa(int index) {
    setState(() {
      if (ultimaTarefa != null && tarefas[index].id == ultimaTarefa!.id) {
        ultimaTarefa = null;
      }
      tarefas.removeAt(index);
    });
  }

  String formatar(int s) {
    final min = (s ~/ 60).toString().padLeft(2, '0');
    final seg = (s % 60).toString().padLeft(2, '0');
    return '$min:$seg';
  }

  // ---------------------------------------------------------------------------
  // BUILD
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    switch (estadoApp) {
      case EstadoApp.inicio:
        return _TelaInicial(state: this);
      case EstadoApp.cronometro:
        return _TelaCronometro(state: this);
      case EstadoApp.fim:
        return _TelaFim(state: this);
      case EstadoApp.gerenciar:
        return _TelaGerenciar(state: this);
    }
  }
}

class PomodoroApp extends StatefulWidget {
  const PomodoroApp({super.key});

  @override
  State<PomodoroApp> createState() => _PomodoroAppState();
}

// =============================================================================
// MENU LATERAL
// =============================================================================

class _MenuLateral extends StatelessWidget {
  final _PomodoroAppState state;

  const _MenuLateral({required this.state});

  @override
  Widget build(BuildContext context) {
    final perfil = state.perfil;
    const azul = _PomodoroAppState._azul;
    const branco = _PomodoroAppState._branco;

    return Drawer(
      backgroundColor: Colors.black,
      child: Column(
        children: [
          DrawerHeader(
            decoration: const BoxDecoration(color: azul),
            child: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const CircleAvatar(
                    radius: 35,
                    backgroundColor: Colors.black,
                    child: Icon(Icons.person, size: 40, color: branco),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    perfil.nome.isEmpty ? 'Utilizador' : perfil.nome,
                    style: const TextStyle(
                      color: branco,
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  if (perfil.nomedeutilizador.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      '@${perfil.nomedeutilizador}',
                      style: TextStyle(
                        color: branco.withOpacity(0.8),
                        fontSize: 13,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
          _drawerItem(
            icon: Icons.info_outline,
            label: 'O que é o Pomodoro',
            onTap: () {
              Navigator.pop(context);
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const TelaPomodoroInfo()),
              );
            },
          ),
          _drawerItem(
            icon: Icons.account_circle_outlined,
            label: 'Perfil',
            onTap: () async {
              Navigator.pop(context);
              final resultado = await Navigator.push<PerfilUsuario>(
                context,
                MaterialPageRoute(
                  builder: (_) => TelaPerfil(perfil: state.perfil),
                ),
              );
              if (resultado != null) {
                // ignore: invalid_use_of_protected_member
                state.setState(() => state.perfil = resultado);
              }
            },
          ),
          _drawerItem(
            icon: Icons.checklist_rtl,
            label: 'To-do List',
            onTap: () {
              Navigator.pop(context);
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => TelaTodo(lista: state.notasTodo),
                ),
              );
            },
          ),
          _drawerItem(
            icon: Icons.bar_chart,
            label: 'Insights',
            onTap: () {
              Navigator.pop(context);
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => TelaInsights(sessoes: state.sessoes),
                ),
              );
            },
          ),
          _drawerItem(
            icon: Icons.settings,
            label: 'Definições',
            onTap: () {
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Definições em breve...')),
              );
            },
          ),
          const Spacer(),
          Padding(
            padding: const EdgeInsets.all(20.0),
            child: Text(
              'Thoth',
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.bold,
                letterSpacing: 3,
                color: azul,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _drawerItem({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return ListTile(
      leading: Icon(icon, color: Colors.white),
      title: Text(label, style: const TextStyle(color: Colors.white)),
      onTap: onTap,
    );
  }
}

// =============================================================================
// TELA INICIAL
// =============================================================================

class _TelaInicial extends StatelessWidget {
  final _PomodoroAppState state;

  const _TelaInicial({required this.state});

  @override
  Widget build(BuildContext context) {
    const azul = _PomodoroAppState._azul;
    const branco = _PomodoroAppState._branco;
    final ultimaTarefa = state.ultimaTarefa;
    final tarefas = state.tarefas;

    return Scaffold(
      key: state._scaffoldKey,
      drawer: _MenuLateral(state: state),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 25),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  IconButton(
                    icon: const Icon(Icons.menu, size: 30, color: branco),
                    onPressed: () => state._scaffoldKey.currentState?.openDrawer(),
                  ),
                  CircleAvatar(
                    radius: 20,
                    backgroundColor: azul,
                    child: Text(
                      state.perfil.nome.isNotEmpty
                          ? state.perfil.nome[0].toUpperCase()
                          : 'T',
                      style: const TextStyle(
                        color: branco,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),

              // Título
              const Text(
                'Thoth',
                style: TextStyle(
                  fontSize: 32,
                  color: azul,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 4,
                ),
              ),
              const Text(
                'Study Helper — Pomodoro',
                style: TextStyle(fontSize: 14, color: branco, letterSpacing: 1.2),
              ),
              const SizedBox(height: 24),

              // Retomar última tarefa
              if (ultimaTarefa != null &&
                  ultimaTarefa.progressoSalvo > 0.0 &&
                  ultimaTarefa.progressoSalvo < 1.0) ...[
                _CartaoRetomar(state: state, ultimaTarefa: ultimaTarefa),
                const SizedBox(height: 20),
              ],

              // Secção de tarefas
              const Text(
                'Tarefas',
                style: TextStyle(
                  fontSize: 18,
                  color: azul,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 10),

              Expanded(
                child: tarefas.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.inbox_outlined,
                              size: 60,
                              color: branco.withOpacity(0.2),
                            ),
                            const SizedBox(height: 16),
                            Text(
                              'Nenhuma tarefa criada',
                              style: TextStyle(
                                color: branco.withOpacity(0.4),
                                fontSize: 16,
                                fontWeight: FontWeight.w300,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'Toca em "Gerenciar Tarefas" para começar',
                              style: TextStyle(
                                color: branco.withOpacity(0.25),
                                fontSize: 13,
                              ),
                            ),
                          ],
                        ),
                      )
                    : ListView.builder(
                        itemCount: tarefas.length,
                        itemBuilder: (ctx, i) => _CartaoTarefa(
                          tarefa: tarefas[i],
                          onTap: () => state.iniciarTarefa(tarefas[i]),
                        ),
                      ),
              ),

              // Botão gerenciar
              Padding(
                padding: const EdgeInsets.only(bottom: 20, top: 10),
                child: ElevatedButton(
                  onPressed: () =>
                      // ignore: invalid_use_of_protected_member
                      state.setState(() => state.estadoApp = EstadoApp.gerenciar),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: azul,
                    foregroundColor: branco,
                    minimumSize: const Size(double.infinity, 55),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: const Text(
                    'GERENCIAR TAREFAS',
                    style: TextStyle(fontWeight: FontWeight.bold, letterSpacing: 1),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CartaoRetomar extends StatelessWidget {
  final _PomodoroAppState state;
  final Tarefa ultimaTarefa;

  const _CartaoRetomar({required this.state, required this.ultimaTarefa});

  @override
  Widget build(BuildContext context) {
    const azul = _PomodoroAppState._azul;
    const branco = _PomodoroAppState._branco;
    final pct = (ultimaTarefa.progressoSalvo * 100).toStringAsFixed(0);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        border: Border.all(color: azul),
        borderRadius: BorderRadius.circular(15),
        color: azul.withOpacity(0.05),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.history, color: azul, size: 16),
              const SizedBox(width: 6),
              const Text(
                'Última sessão',
                style: TextStyle(color: azul, fontSize: 12, letterSpacing: 1),
              ),
              const Spacer(),
              Text(
                '$pct%',
                style: const TextStyle(
                  color: azul,
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            ultimaTarefa.nome.isEmpty ? 'Tarefa Sem Nome' : ultimaTarefa.nome,
            style: const TextStyle(
              color: branco,
              fontSize: 16,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: ultimaTarefa.progressoSalvo,
              color: azul,
              backgroundColor: branco.withOpacity(0.1),
              minHeight: 6,
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => state.iniciarTarefa(ultimaTarefa, retomar: true),
                  icon: const Icon(Icons.play_arrow, color: azul, size: 18),
                  label: const Text(
                    'PROSSEGUIR',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: branco,
                      fontSize: 12,
                    ),
                  ),
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: azul),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: state.descartarProgresso,
                  icon: const Icon(Icons.delete_sweep, color: Colors.redAccent, size: 18),
                  label: const Text(
                    'DESCARTAR',
                    style: TextStyle(color: Colors.redAccent, fontSize: 12),
                  ),
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: Colors.redAccent),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _CartaoTarefa extends StatelessWidget {
  final Tarefa tarefa;
  final VoidCallback onTap;

  const _CartaoTarefa({required this.tarefa, required this.onTap});

  @override
  Widget build(BuildContext context) {
    const azul = _PomodoroAppState._azul;
    const branco = _PomodoroAppState._branco;
    final temProgresso = tarefa.progressoSalvo > 0.0 && tarefa.progressoSalvo < 1.0;
    final concluida = tarefa.progressoSalvo >= 1.0;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        border: Border.all(
          color: concluida
              ? Colors.greenAccent.withOpacity(0.4)
              : branco.withOpacity(0.15),
        ),
        borderRadius: BorderRadius.circular(12),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      tarefa.nome.isEmpty ? 'Nova Tarefa' : tarefa.nome,
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: concluida ? Colors.greenAccent.withOpacity(0.8) : branco,
                        fontSize: 17,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Foco: ${tarefa.estudo ~/ 60}m  ·  Descanso: ${tarefa.descanso ~/ 60}m  ·  ${tarefa.ciclos} ciclos',
                      style: const TextStyle(color: azul, fontSize: 13, height: 1.4),
                    ),
                    if (temProgresso) ...[
                      const SizedBox(height: 8),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(3),
                        child: LinearProgressIndicator(
                          value: tarefa.progressoSalvo,
                          color: azul,
                          backgroundColor: branco.withOpacity(0.1),
                          minHeight: 3,
                        ),
                      ),
                    ],
                    if (concluida) ...[
                      const SizedBox(height: 6),
                      const Text(
                        '✓ Concluída',
                        style: TextStyle(color: Colors.greenAccent, fontSize: 12),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Icon(
                concluida ? Icons.check_circle : Icons.play_circle_fill,
                color: concluida ? Colors.greenAccent : azul,
                size: 38,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// =============================================================================
// TELA GERENCIAR TAREFAS
// =============================================================================

class _TelaGerenciar extends StatelessWidget {
  final _PomodoroAppState state;

  const _TelaGerenciar({required this.state});

  @override
  Widget build(BuildContext context) {
    const azul = _PomodoroAppState._azul;
    const branco = _PomodoroAppState._branco;
    final tarefas = state.tarefas;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Gerenciar Tarefas'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: branco),
          // ignore: invalid_use_of_protected_member
          onPressed: () => state.setState(() => state.estadoApp = EstadoApp.inicio),
        ),
        bottom: const PreferredSize(
          preferredSize: Size.fromHeight(1),
          child: Divider(color: azul, height: 1),
        ),
      ),
      floatingActionButton: FloatingActionButton(
        backgroundColor: azul,
        foregroundColor: branco,
        onPressed: () => _abrirEditor(context),
        child: const Icon(Icons.add),
      ),
      body: tarefas.isEmpty
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.add_task, size: 64, color: branco.withOpacity(0.2)),
                  const SizedBox(height: 16),
                  Text(
                    'Nenhuma tarefa',
                    style: TextStyle(color: branco.withOpacity(0.4), fontSize: 18),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Toca no + para criar',
                    style: TextStyle(color: branco.withOpacity(0.25), fontSize: 14),
                  ),
                ],
              ),
            )
          : ReorderableListView.builder(
              padding: const EdgeInsets.only(bottom: 80),
              itemCount: tarefas.length,
              onReorder: (oldIndex, newIndex) {
                // ignore: invalid_use_of_protected_member
                state.setState(() {
                  if (newIndex > oldIndex) newIndex--;
                  final item = state.tarefas.removeAt(oldIndex);
                  state.tarefas.insert(newIndex, item);
                });
              },
              itemBuilder: (ctx, i) => _linhaGerenciar(ctx, i, tarefas[i]),
            ),
    );
  }

  Widget _linhaGerenciar(BuildContext context, int i, Tarefa t) {
    const azul = _PomodoroAppState._azul;
    const branco = _PomodoroAppState._branco;

    return Dismissible(
      key: ValueKey(t.id),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        color: Colors.red.withOpacity(0.2),
        child: const Icon(Icons.delete, color: Colors.redAccent),
      ),
      onDismissed: (_) => state.removerTarefa(i),
      child: Container(
        key: ValueKey('${t.id}_container'),
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(color: branco.withOpacity(0.08)),
          ),
        ),
        child: ListTile(
          title: Text(
            t.nome.isEmpty ? 'Sem nome' : t.nome,
            style: const TextStyle(color: branco, fontWeight: FontWeight.bold),
          ),
          subtitle: Text(
            '${t.estudo ~/ 60}m foco · ${t.descanso ~/ 60}m descanso · ${t.ciclos} ciclos',
            style: const TextStyle(color: azul, fontSize: 13),
          ),
          leading: const Icon(Icons.drag_handle, color: Colors.white38),
          trailing: IconButton(
            icon: const Icon(Icons.edit_outlined, color: branco),
            onPressed: () => _abrirEditor(context, index: i),
          ),
          onTap: () => _abrirEditor(context, index: i),
        ),
      ),
    );
  }

  void _abrirEditor(BuildContext context, {int? index}) {
    final tarefas = state.tarefas;
    final temp = index != null
        ? tarefas[index].clone()
        : Tarefa(id: DateTime.now().millisecondsSinceEpoch.toString());

    final nomeCtrl = TextEditingController(text: temp.nome);

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.black,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
        side: BorderSide(color: Color(0xFF1D81C7), width: 2),
      ),
      builder: (ctx) => _EditorTarefa(
        temp: temp,
        nomeCtrl: nomeCtrl,
        onGuardar: () {
          // ignore: invalid_use_of_protected_member
          state.setState(() {
            if (index == null) {
              state.tarefas.add(temp);
            } else {
              state.tarefas[index] = temp;
            }
          });
          Navigator.pop(ctx);
        },
      ),
    ).whenComplete(nomeCtrl.dispose);
  }
}

class _EditorTarefa extends StatefulWidget {
  final Tarefa temp;
  final TextEditingController nomeCtrl;
  final VoidCallback onGuardar;

  const _EditorTarefa({
    required this.temp,
    required this.nomeCtrl,
    required this.onGuardar,
  });

  @override
  State<_EditorTarefa> createState() => _EditorTarefaState();
}

class _EditorTarefaState extends State<_EditorTarefa> {
  static const Color azul = _PomodoroAppState._azul;
  static const Color branco = _PomodoroAppState._branco;

  static const _presets = [
    {'label': 'G', 'foco': 1800, 'descanso': 600, 'ciclos': 3},
    {'label': 'A', 'foco': 2700, 'descanso': 900, 'ciclos': 2},
    {'label': 'M', 'foco': 5400, 'descanso': 1200, 'ciclos': 4},
    {'label': 'P', 'foco': 3600, 'descanso': 300, 'ciclos': 6},
  ];

  static const _legendas = {
    'G': 'Geografia', 'A': 'Arte', 'M': 'Matemática', 'P': 'Prática'
  };

  @override
  Widget build(BuildContext context) {
    final t = widget.temp;

    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
        left: 25,
        right: 25,
        top: 25,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Handle visual
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.white24,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 20),
            const Text(
              'Configurar Tarefa',
              style: TextStyle(
                color: azul,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 20),

            // Nome
            TextField(
              controller: widget.nomeCtrl,
              style: const TextStyle(color: branco),
              textCapitalization: TextCapitalization.sentences,
              decoration: InputDecoration(
                labelText: 'Nome da Tarefa',
                hintText: 'Ex: Estudar Matemática',
                hintStyle: TextStyle(color: branco.withOpacity(0.3)),
                labelStyle: const TextStyle(color: azul),
                enabledBorder: const UnderlineInputBorder(
                  borderSide: BorderSide(color: Colors.white24),
                ),
                focusedBorder: const UnderlineInputBorder(
                  borderSide: BorderSide(color: azul),
                ),
              ),
              onChanged: (v) => t.nome = v,
            ),
            const SizedBox(height: 30),

            // Sliders
            _labelSlider('Tempo de Foco', '${t.estudo ~/ 60} min'),
            Slider(
              value: t.estudo.toDouble(),
              min: 60,
              max: 7200,
              divisions: 119,
              label: '${t.estudo ~/ 60}m',
              onChanged: (v) => setState(() => t.estudo = (v / 60).round() * 60),
            ),

            _labelSlider('Tempo de Descanso', '${t.descanso ~/ 60} min'),
            Slider(
              value: t.descanso.toDouble(),
              min: 60,
              max: 3600,
              divisions: 59,
              label: '${t.descanso ~/ 60}m',
              onChanged: (v) => setState(() => t.descanso = (v / 60).round() * 60),
            ),

            _labelSlider('Número de Ciclos', '${t.ciclos} ciclos'),
            Slider(
              value: t.ciclos.toDouble(),
              min: 1,
              max: 10,
              divisions: 9,
              label: '${t.ciclos}',
              onChanged: (v) => setState(() => t.ciclos = v.toInt()),
            ),

            const SizedBox(height: 10),

            // Presets
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: _presets.map((p) {
                return Tooltip(
                  message: _legendas[p['label']] ?? '',
                  child: InkWell(
                    onTap: () => setState(() {
                      t.estudo = p['foco'] as int;
                      t.descanso = p['descanso'] as int;
                      t.ciclos = p['ciclos'] as int;
                    }),
                    borderRadius: BorderRadius.circular(8),
                    child: Container(
                      width: 70,
                      height: 52,
                      decoration: BoxDecoration(
                        border: Border.all(color: azul, width: 2),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      alignment: Alignment.center,
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            p['label'] as String,
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: branco,
                            ),
                          ),
                          Text(
                            '${(p['foco'] as int) ~/ 60}m',
                            style: const TextStyle(color: azul, fontSize: 10),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
            const SizedBox(height: 25),

            // Guardar
            ElevatedButton(
              onPressed: widget.onGuardar,
              style: ElevatedButton.styleFrom(
                backgroundColor: azul,
                foregroundColor: branco,
                minimumSize: const Size(double.infinity, 52),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: const Text(
                'GUARDAR',
                style: TextStyle(fontWeight: FontWeight.bold, letterSpacing: 1),
              ),
            ),
            const SizedBox(height: 30),
          ],
        ),
      ),
    );
  }

  Widget _labelSlider(String titulo, String valor) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(titulo, style: TextStyle(color: branco.withOpacity(0.7), fontSize: 13)),
        Text(valor,
            style: const TextStyle(
              color: azul,
              fontWeight: FontWeight.bold,
              fontSize: 14,
            )),
      ],
    );
  }
}

// =============================================================================
// TELA CRONÓMETRO
// =============================================================================

class _TelaCronometro extends StatelessWidget {
  final _PomodoroAppState state;

  const _TelaCronometro({required this.state});

  @override
  Widget build(BuildContext context) {
    const azul = _PomodoroAppState._azul;
    const branco = _PomodoroAppState._branco;

    final tarefa = state.tarefaAtual;
      if (tarefa == null) return const SizedBox();
    final estaNoDescanso = state.estaNoDescanso;
    final total = estaNoDescanso ? tarefa.descanso : tarefa.estudo;
    final progresso = total <= 0
        ? 0.0
        : (1 - (state.segundosRestantes / total)).clamp(0.0, 1.0);
    final pausado = state.pausado;

    return Scaffold(
      body: SafeArea(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Nome da tarefa
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 30),
              child: Text(
                tarefa.nome.isEmpty ? 'Sem nome' : tarefa.nome,
                style: const TextStyle(
                  color: azul,
                  letterSpacing: 2,
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                ),
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(height: 6),

            // Modo (Foco / Descanso)
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 300),
              child: Text(
                estaNoDescanso ? 'DESCANSO' : 'FOCO',
                key: ValueKey(estaNoDescanso),
                style: const TextStyle(
                  fontSize: 30,
                  color: branco,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 4,
                ),
              ),
            ),
            const SizedBox(height: 40),

            // Timer circular
            Center(
              child: Stack(
                alignment: Alignment.center,
                children: [
                  SizedBox(
                    width: 260,
                    height: 260,
                    child: CircularProgressIndicator(
                      value: progresso,
                      strokeWidth: 8,
                      color: azul,
                      backgroundColor: branco.withOpacity(0.08),
                    ),
                  ),
                  Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        state.formatar(state.segundosRestantes),
                        style: const TextStyle(
                          fontSize: 58,
                          fontWeight: FontWeight.w200,
                          color: branco,
                          letterSpacing: 2,
                        ),
                      ),
                      if (pausado)
                        const Text(
                          'PAUSADO',
                          style: TextStyle(
                            color: Colors.white38,
                            fontSize: 12,
                            letterSpacing: 3,
                          ),
                        ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 28),

            // Indicador de ciclos
            _IndicadorCiclos(
              cicloAtual: state.cicloAtual,
              totalCiclos: tarefa.ciclos,
              estaNoDescanso: estaNoDescanso,
            ),
            const SizedBox(height: 48),

            // Controlos
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _BotaoTimer(
                  icon: Icons.stop_rounded,
                  color: Colors.white38,
                  onPressed: state.reset,
                  tooltip: 'Parar',
                ),
                const SizedBox(width: 24),
                _BotaoTimer(
                  icon: pausado ? Icons.play_arrow_rounded : Icons.pause_rounded,
                  color: branco,
                  size: 56,
                  onPressed: state.alternarPausa,
                  tooltip: pausado ? 'Continuar' : 'Pausar',
                ),
                const SizedBox(width: 24),
                _BotaoTimer(
                  icon: Icons.skip_next_rounded,
                  color: Colors.white38,
                  onPressed: state.pularFase,
                  tooltip: 'Pular fase',
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _IndicadorCiclos extends StatelessWidget {
  final int cicloAtual;
  final int totalCiclos;
  final bool estaNoDescanso;

  const _IndicadorCiclos({
    required this.cicloAtual,
    required this.totalCiclos,
    required this.estaNoDescanso,
  });

  @override
  Widget build(BuildContext context) {
    const azul = _PomodoroAppState._azul;

    return Column(
      children: [
        Text(
          'Ciclo $cicloAtual de $totalCiclos',
          style: const TextStyle(color: azul, fontSize: 16),
        ),
        const SizedBox(height: 10),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: List.generate(totalCiclos, (i) {
            final concluido = i < cicloAtual - 1;
            final atual = i == cicloAtual - 1;
            return Container(
              margin: const EdgeInsets.symmetric(horizontal: 3),
              width: atual ? 20 : 10,
              height: 8,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(4),
                color: concluido
                    ? azul
                    : atual
                        ? (estaNoDescanso ? Colors.greenAccent.withOpacity(0.6) : azul)
                        : Colors.white12,
              ),
            );
          }),
        ),
      ],
    );
  }
}

class _BotaoTimer extends StatelessWidget {
  final IconData icon;
  final Color color;
  final VoidCallback onPressed;
  final String tooltip;
  final double size;

  const _BotaoTimer({
    required this.icon,
    required this.color,
    required this.onPressed,
    required this.tooltip,
    this.size = 44,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(50),
        child: Padding(
          padding: const EdgeInsets.all(8.0),
          child: Icon(icon, size: size, color: color),
        ),
      ),
    );
  }
}

// =============================================================================
// TELA FIM (CONCLUÍDO)
// =============================================================================

class _TelaFim extends StatelessWidget {
  final _PomodoroAppState state;

  const _TelaFim({required this.state});

  @override
  Widget build(BuildContext context) {
    const azul = _PomodoroAppState._azul;
    const branco = _PomodoroAppState._branco;
    const _ = _PomodoroAppState._preto;

    final nome = state.ultimaTarefa?.nome ?? '';
    final ciclos = state.ultimaTarefa?.ciclos ?? 0;
    final tempoFoco = state.ultimaTarefa != null
        ? state.ultimaTarefa!.ciclos * state.ultimaTarefa!.estudo
        : 0;

    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 40),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Ícone animado
              TweenAnimationBuilder<double>(
                tween: Tween(begin: 0.0, end: 1.0),
                duration: const Duration(milliseconds: 600),
                curve: Curves.elasticOut,
                builder: (_, v, child) => Transform.scale(scale: v, child: child),
                child: const Icon(
                  Icons.check_circle_outline,
                  size: 100,
                  color: azul,
                ),
              ),
              const SizedBox(height: 24),
              const Text(
                'SESSÃO CONCLUÍDA!',
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  color: branco,
                  letterSpacing: 3,
                ),
              ),
              const SizedBox(height: 8),
              if (nome.isNotEmpty)
                Text(
                  nome,
                  style: const TextStyle(color: azul, fontSize: 16),
                  textAlign: TextAlign.center,
                ),
              const SizedBox(height: 40),

              // Stats
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _statItem(Icons.repeat, '$ciclos', 'ciclos'),
                  const SizedBox(width: 30),
                  _statItem(
                    Icons.timer_outlined,
                    '${tempoFoco ~/ 60}',
                    'minutos foco',
                  ),
                ],
              ),
              const SizedBox(height: 50),

              // Botões
              ElevatedButton(
                onPressed: state.reset,
                style: ElevatedButton.styleFrom(
                  backgroundColor: azul,
                  foregroundColor: branco,
                  minimumSize: const Size(200, 52),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: const Text(
                  'VOLTAR AO INÍCIO',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
              const SizedBox(height: 12),
              TextButton(
                onPressed: () {
                  if (state.ultimaTarefa != null) {
                    // Reiniciar a mesma tarefa
                    final t = state.ultimaTarefa!;
                    t
                      ..progressoSalvo = 0.0
                      ..cicloSalvo = 1
                      ..estavaNoDescanso = false
                      ..segundosSalvos = t.estudo;
                    state.iniciarTarefa(t);
                  }
                },
                child: const Text(
                  'Repetir esta tarefa',
                  style: TextStyle(color: Colors.white38),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _statItem(IconData icon, String valor, String label) {
    return Column(
      children: [
        Icon(icon, color: const Color(0xFF1D81C7), size: 28),
        const SizedBox(height: 6),
        Text(
          valor,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 28,
            fontWeight: FontWeight.bold,
          ),
        ),
        Text(
          label,
          style: TextStyle(color: Colors.white.withOpacity(0.5), fontSize: 12),
        ),
      ],
    );
  }
}

// =============================================================================
// TELA PERFIL
// =============================================================================

class TelaPerfil extends StatefulWidget {
  final PerfilUsuario perfil;

  const TelaPerfil({super.key, required this.perfil});

  @override
  State<TelaPerfil> createState() => _TelaPerfilState();
}

class _TelaPerfilState extends State<TelaPerfil> {
  late final TextEditingController _nomeCtrl;
  late final TextEditingController _usernameCtrl;
  late final TextEditingController _descCtrl;
  late final TextEditingController _motivosCtrl;

  static const Color azul = Color(0xFF1D81C7);

  @override
  void initState() {
    super.initState();
    _nomeCtrl = TextEditingController(text: widget.perfil.nome);
    _usernameCtrl = TextEditingController(text: widget.perfil.nomedeutilizador);
    _descCtrl = TextEditingController(text: widget.perfil.descricao);
    _motivosCtrl = TextEditingController(text: widget.perfil.motivos);
  }

  @override
  void dispose() {
    _nomeCtrl.dispose();
    _usernameCtrl.dispose();
    _descCtrl.dispose();
    _motivosCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Editar Perfil'),
        actions: [
          IconButton(
            icon: const Icon(Icons.check, color: azul),
            tooltip: 'Guardar',
            onPressed: _guardar,
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(25),
        child: Column(
          children: [
            // Avatar
            Center(
              child: Stack(
                children: [
                  CircleAvatar(
                    radius: 60,
                    backgroundColor: azul,
                    child: Text(
                      _nomeCtrl.text.isNotEmpty
                          ? _nomeCtrl.text[0].toUpperCase()
                          : 'T',
                      style: const TextStyle(
                        fontSize: 50,
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  Positioned(
                    bottom: 0,
                    right: 0,
                    child: CircleAvatar(
                      radius: 18,
                      backgroundColor: Colors.white,
                      child: Icon(Icons.camera_alt, size: 18, color: azul),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 30),

            _campo('Nome', _nomeCtrl, 'Insira o seu nome...'),
            _campo('Nome de Utilizador', _usernameCtrl, 'Ex: Mestre do Foco'),
            _campo('Descrição', _descCtrl, 'Escreva algo sobre si...', maxLines: 3),
            _campo(
              'Motivações para usar o Thoth',
              _motivosCtrl,
              'Ex: Melhorar a gestão de tempo...',
              maxLines: 3,
            ),
            const SizedBox(height: 20),

            ElevatedButton(
              onPressed: _guardar,
              style: ElevatedButton.styleFrom(
                backgroundColor: azul,
                foregroundColor: Colors.white,
                minimumSize: const Size(double.infinity, 52),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: const Text(
                'GUARDAR PERFIL',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _guardar() {
    Navigator.pop(
      context,
      PerfilUsuario(
        nome: _nomeCtrl.text.trim(),
        nomedeutilizador: _usernameCtrl.text.trim(),
        descricao: _descCtrl.text.trim(),
        motivos: _motivosCtrl.text.trim(),
      ),
    );
  }

  Widget _campo(String label, TextEditingController ctrl, String hint,
      {int maxLines = 1}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: TextField(
        controller: ctrl,
        maxLines: maxLines,
        style: const TextStyle(color: Colors.white),
        textCapitalization: TextCapitalization.sentences,
        decoration: InputDecoration(
          labelText: label,
          hintText: hint,
          hintStyle: TextStyle(color: Colors.white.withOpacity(0.3)),
          labelStyle: const TextStyle(color: azul),
          enabledBorder: const UnderlineInputBorder(
            borderSide: BorderSide(color: Colors.white24),
          ),
          focusedBorder: const UnderlineInputBorder(
            borderSide: BorderSide(color: azul),
          ),
        ),
      ),
    );
  }
}

// =============================================================================
// TELA TO-DO LIST
// =============================================================================

class TelaTodo extends StatefulWidget {
  final List<ItemTodo> lista;

  const TelaTodo({super.key, required this.lista});

  @override
  State<TelaTodo> createState() => _TelaTodoState();
}

class _TelaTodoState extends State<TelaTodo> {
  final TextEditingController _todoCtrl = TextEditingController();
  final TextEditingController _horaCtrl = TextEditingController();
  final TextEditingController _dataCtrl = TextEditingController();
  String _blocoSelecionado = 'Tarefas para hoje';

  final Map<String, List<ItemTodo>> _blocos = {
    'Tarefas para hoje': [],
    'Esta semana': [],
    'Urgente': [],
    'Acabadas': [],
    'Por fazer!!': [],
  };

  static const Map<String, Color> _coresBlocos = {
    'Tarefas para hoje': Color(0xFFD99AA2),
    'Esta semana': Color(0xFF8FAFBB),
    'Urgente': Color(0xFFE5DFA7),
    'Acabadas': Color(0xFFA8C9A3),
    'Por fazer!!': Color(0xFFF06A6A),
  };

  @override
  void initState() {
    super.initState();
    // Inicializar restantes blocos vazios
    for (final key in _blocos.keys) {
      _blocos[key] = [];
    }
    // Carregar itens existentes para o bloco inicial
    _blocos['Tarefas para hoje']!.addAll(widget.lista);
  }

  @override
  void dispose() {
    _todoCtrl.dispose();
    _horaCtrl.dispose();
    _dataCtrl.dispose();
    super.dispose();
  }

  void _adicionarItem() {
    final texto = _todoCtrl.text.trim();
    if (texto.isEmpty) return;

    final hora = _horaCtrl.text.trim().isEmpty ? '--:--' : _horaCtrl.text.trim();
    final data = _dataCtrl.text.trim().isEmpty ? '--/--' : _dataCtrl.text.trim();

    setState(() {
      _blocos[_blocoSelecionado]!.add(ItemTodo(
        id: DateTime.now().microsecondsSinceEpoch.toString(),
        texto: texto,
        dataHora: '$hora | $data',
        concluido: _blocoSelecionado == 'Acabadas',
      ));
      _todoCtrl.clear();
      _horaCtrl.clear();
      _dataCtrl.clear();
    });
  }

  void _moverItem(ItemTodo item, String destino) {
    setState(() {
      for (final lista in _blocos.values) {
        lista.removeWhere((i) => i.id == item.id);
      }
      item.concluido = destino == 'Acabadas';
      _blocos[destino]!.add(item);
    });
  }

  void _removerItem(ItemTodo item) {
    setState(() {
      for (final lista in _blocos.values) {
        lista.removeWhere((i) => i.id == item.id);
      }
    });
  }

  void _alternarConcluido(ItemTodo item) {
    setState(() {
      item.concluido = !item.concluido;
      // Remover do bloco atual
      for (final lista in _blocos.values) {
        lista.removeWhere((i) => i.id == item.id);
      }
      // Mover para bloco adequado
      _blocos[item.concluido ? 'Acabadas' : 'Por fazer!!']!.add(item);
    });
  }

  Future<void> _selecionarData() async {
    final hoje = DateTime.now();
    final escolha = await showDatePicker(
      context: context,
      initialDate: hoje,
      firstDate: hoje,
      lastDate: DateTime(hoje.year + 2),
      builder: (ctx, child) => Theme(
        data: Theme.of(ctx).copyWith(
          colorScheme: const ColorScheme.dark(
            primary: Color(0xFF1D81C7),
            surface: Colors.black87,
          ),
        ),
        child: child!,
      ),
    );
    if (escolha != null && mounted) {
      setState(() {
        _dataCtrl.text =
            '${escolha.day.toString().padLeft(2, '0')}/${escolha.month.toString().padLeft(2, '0')}';
      });
    }
  }

  Future<void> _selecionarHora() async {
    final escolha = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.now(),
      builder: (ctx, child) => Theme(
        data: Theme.of(ctx).copyWith(
          colorScheme: const ColorScheme.dark(
            primary: Color(0xFF1D81C7),
            surface: Colors.black87,
          ),
        ),
        child: child!,
      ),
    );
    if (escolha != null && mounted) {
      setState(() {
        _horaCtrl.text =
            '${escolha.hour.toString().padLeft(2, '0')}:${escolha.minute.toString().padLeft(2, '0')}';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    const azul = Color(0xFF1D81C7);

    return Scaffold(
      appBar: AppBar(
        title: const Text('To-do List'),
        bottom: const PreferredSize(
          preferredSize: Size.fromHeight(1),
          child: Divider(color: azul, height: 1),
        ),
      ),
      body: Column(
        children: [
          // Painel de entrada
          Container(
            width: double.infinity,
            color: const Color(0xFF0D6E9E),
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'To-do List',
                  style: TextStyle(
                    fontSize: 32,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _todoCtrl,
                  style: const TextStyle(color: Colors.white),
                  textCapitalization: TextCapitalization.sentences,
                  decoration: const InputDecoration(
                    hintText: 'Nova tarefa...',
                    hintStyle: TextStyle(color: Colors.white54),
                    isDense: true,
                    enabledBorder: UnderlineInputBorder(
                      borderSide: BorderSide(color: Colors.white30),
                    ),
                    focusedBorder: UnderlineInputBorder(
                      borderSide: BorderSide(color: Colors.white),
                    ),
                  ),
                  onSubmitted: (_) => _adicionarItem(),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: GestureDetector(
                        onTap: _selecionarHora,
                        child: AbsorbPointer(
                          child: TextField(
                            controller: _horaCtrl,
                            style: const TextStyle(color: Colors.white),
                            decoration: const InputDecoration(
                              hintText: 'Hora',
                              hintStyle: TextStyle(color: Colors.white54),
                              prefixIcon: Icon(Icons.access_time, color: Colors.white54, size: 18),
                              isDense: true,
                              enabledBorder: UnderlineInputBorder(
                                borderSide: BorderSide(color: Colors.white30),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: GestureDetector(
                        onTap: _selecionarData,
                        child: AbsorbPointer(
                          child: TextField(
                            controller: _dataCtrl,
                            style: const TextStyle(color: Colors.white),
                            decoration: const InputDecoration(
                              hintText: 'Data',
                              hintStyle: TextStyle(color: Colors.white54),
                              prefixIcon: Icon(Icons.calendar_today, color: Colors.white54, size: 18),
                              isDense: true,
                              enabledBorder: UnderlineInputBorder(
                                borderSide: BorderSide(color: Colors.white30),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: DropdownButtonHideUnderline(
                        child: DropdownButton<String>(
                          value: _blocoSelecionado,
                          dropdownColor: Colors.black,
                          isExpanded: true,
                          style: const TextStyle(color: Colors.white),
                          icon: const Icon(Icons.arrow_drop_down, color: Colors.white54),
                          items: _blocos.keys.map((b) {
                            return DropdownMenuItem(value: b, child: Text(b));
                          }).toList(),
                          onChanged: (v) {
                            if (v != null) setState(() => _blocoSelecionado = v);
                          },
                        ),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.add_task, color: Colors.white),
                      tooltip: 'Adicionar',
                      onPressed: _adicionarItem,
                    ),
                  ],
                ),
              ],
            ),
          ),

          // Grelha de blocos
          Expanded(
            child: GridView.count(
              crossAxisCount: 2,
              padding: const EdgeInsets.all(14),
              crossAxisSpacing: 12,
              mainAxisSpacing: 12,
              children: _blocos.entries.map((entry) {
                return _BlocoTodo(
                  titulo: entry.key,
                  itens: entry.value,
                  cor: _coresBlocos[entry.key] ?? Colors.grey,
                  onMover: (item) => _moverItem(item, entry.key),
                  onToggle: _alternarConcluido,
                  onRemover: _removerItem,
                );
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }
}

class _BlocoTodo extends StatelessWidget {
  final String titulo;
  final List<ItemTodo> itens;
  final Color cor;
  final void Function(ItemTodo) onMover;
  final void Function(ItemTodo) onToggle;
  final void Function(ItemTodo) onRemover;

  const _BlocoTodo({
    required this.titulo,
    required this.itens,
    required this.cor,
    required this.onMover,
    required this.onToggle,
    required this.onRemover,
  });

  @override
  Widget build(BuildContext context) {
    return DragTarget<ItemTodo>(
      onAcceptWithDetails: (details) => onMover(details.data),
      builder: (ctx, candidateData, _) {
        return Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: cor,
            borderRadius: BorderRadius.circular(18),
            border: candidateData.isNotEmpty
                ? Border.all(color: Colors.white, width: 2)
                : null,
            boxShadow: [
              BoxShadow(
                color: cor.withOpacity(0.3),
                blurRadius: 8,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                titulo,
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                  color: Colors.black,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 8),
              Expanded(
                child: itens.isEmpty
                    ? Center(
                        child: Text(
                          'Vazio',
                          style: TextStyle(
                            color: Colors.black.withOpacity(0.3),
                            fontSize: 12,
                          ),
                        ),
                      )
                    : ListView(
                        children: itens
                            .map((item) => _ItemArrastaveel(
                                  item: item,
                                  onToggle: onToggle,
                                  onRemover: onRemover,
                                ))
                            .toList(),
                      ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _ItemArrastaveel extends StatelessWidget {
  final ItemTodo item;
  final void Function(ItemTodo) onToggle;
  final void Function(ItemTodo) onRemover;

  const _ItemArrastaveel({
    required this.item,
    required this.onToggle,
    required this.onRemover,
  });

  @override
  Widget build(BuildContext context) {
    return Draggable<ItemTodo>(
      data: item,
      feedback: Material(
        color: Colors.transparent,
        child: _buildUI(isDragging: true),
      ),
      childWhenDragging: Opacity(opacity: 0.3, child: _buildUI()),
      child: _buildUI(),
    );
  }

  Widget _buildUI({bool isDragging = false}) {
    return GestureDetector(
      onLongPress: null,
      child: InkWell(
        onTap: () => onToggle(item),
        onLongPress: () => onRemover(item),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Row(
            children: [
              Container(
                width: 14,
                height: 14,
                decoration: BoxDecoration(
                  color: item.concluido ? Colors.black54 : Colors.transparent,
                  border: Border.all(color: Colors.black54, width: 1.5),
                  borderRadius: BorderRadius.circular(2),
                ),
                child: item.concluido
                    ? const Icon(Icons.check, size: 10, color: Colors.white)
                    : null,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  item.texto,
                  style: TextStyle(
                    fontSize: 13,
                    color: Colors.black87,
                    decoration: item.concluido
                        ? TextDecoration.lineThrough
                        : TextDecoration.none,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// =============================================================================
// TELA INSIGHTS
// =============================================================================

class TelaInsights extends StatelessWidget {
  final List<SessaoConcluida> sessoes;

  const TelaInsights({super.key, required this.sessoes});

  @override
  Widget build(BuildContext context) {
    const azul = Color(0xFF1D81C7);

    final totalFoco = sessoes.fold<int>(0, (s, e) => s + e.tempoFocoSegundos);
    final totalCiclos = sessoes.fold<int>(0, (s, e) => s + e.ciclosConcluidos);

    // Tarefa mais estudada
    final contagem = <String, int>{};
    for (final s in sessoes) {
      contagem[s.tarefaNome] = (contagem[s.tarefaNome] ?? 0) + s.tempoFocoSegundos;
    }
    String? tarefaMaisEstudada;
    if (contagem.isNotEmpty) {
      tarefaMaisEstudada =
          contagem.entries.reduce((a, b) => a.value > b.value ? a : b).key;
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Insights'),
        bottom: const PreferredSize(
          preferredSize: Size.fromHeight(1),
          child: Divider(color: azul, height: 1),
        ),
      ),
      body: sessoes.isEmpty
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.bar_chart, size: 64, color: Colors.white.withOpacity(0.15)),
                  const SizedBox(height: 16),
                  Text(
                    'Nenhuma sessão concluída',
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.4),
                      fontSize: 18,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Completa uma tarefa para ver os insights',
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.25),
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
            )
          : SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Cards de resumo
                  Row(
                    children: [
                      Expanded(
                        child: _cardInsight(
                          icon: Icons.timer_outlined,
                          valor: _formatarTempo(totalFoco),
                          label: 'Tempo total de foco',
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _cardInsight(
                          icon: Icons.repeat,
                          valor: '$totalCiclos',
                          label: 'Ciclos concluídos',
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: _cardInsight(
                          icon: Icons.task_alt,
                          valor: '${sessoes.length}',
                          label: 'Sessões completas',
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _cardInsight(
                          icon: Icons.star_outline,
                          valor: tarefaMaisEstudada ?? '—',
                          label: 'Mais estudada',
                          pequeno: true,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 30),

                  // Histórico
                  const Text(
                    'Histórico de Sessões',
                    style: TextStyle(
                      color: azul,
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 12),
                  ...sessoes.reversed.map((s) => _linhaHistorico(s)),
                ],
              ),
            ),
    );
  }

  Widget _cardInsight({
    required IconData icon,
    required String valor,
    required String label,
    bool pequeno = false,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        border: Border.all(color: const Color(0xFF1D81C7).withOpacity(0.4)),
        borderRadius: BorderRadius.circular(12),
        color: const Color(0xFF1D81C7).withOpacity(0.05),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: const Color(0xFF1D81C7), size: 22),
          const SizedBox(height: 8),
          Text(
            valor,
            style: TextStyle(
              color: Colors.white,
              fontSize: pequeno ? 14 : 22,
              fontWeight: FontWeight.bold,
            ),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: TextStyle(
              color: Colors.white.withOpacity(0.4),
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }

  Widget _linhaHistorico(SessaoConcluida s) {
    final d = s.dataConclusao;
    final data =
        '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')} ${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        border: Border.all(color: Colors.white.withOpacity(0.1)),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          const Icon(Icons.check_circle, color: Color(0xFF1D81C7), size: 20),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  s.tarefaNome,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                  ),
                ),
                Text(
                  '${s.ciclosConcluidos} ciclos · ${_formatarTempo(s.tempoFocoSegundos)} foco',
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.5),
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          Text(
            data,
            style: TextStyle(color: Colors.white.withOpacity(0.3), fontSize: 11),
          ),
        ],
      ),
    );
  }

  String _formatarTempo(int segundos) {
    if (segundos >= 3600) {
      final h = segundos ~/ 3600;
      final m = (segundos % 3600) ~/ 60;
      return '${h}h${m > 0 ? ' ${m}m' : ''}';
    }
    return '${segundos ~/ 60}m';
  }
}

// =============================================================================
// TELA INFO POMODORO
// =============================================================================

class TelaPomodoroInfo extends StatelessWidget {
  const TelaPomodoroInfo({super.key});

  @override
  Widget build(BuildContext context) {
    const azul = Color(0xFF1D81C7);
    const tamanhoTexto = 16.5;

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: const Text('Técnica Pomodoro'),
        bottom: const PreferredSize(
          preferredSize: Size.fromHeight(1),
          child: Divider(color: azul, height: 1),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(25),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Ícone central
            Center(
              child: Container(
                width: 80,
                height: 80,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: azul, width: 2),
                ),
                child: const Icon(Icons.timer_outlined, color: azul, size: 40),
              ),
            ),
            const SizedBox(height: 30),

            const Text(
              'O que é o Pomodoro?',
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.bold,
                color: azul,
              ),
            ),
            const SizedBox(height: 12),
            const Text(
              'É uma técnica de gestão de tempo que divide o estudo ou trabalho em blocos curtos de foco intenso, intercalados com descansos breves.',
              style: TextStyle(fontSize: tamanhoTexto, height: 1.6, color: Colors.white),
            ),
            const SizedBox(height: 28),

            const Text(
              'Como funciona:',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: azul,
              ),
            ),
            const SizedBox(height: 12),
            _passo(1, 'Define uma tarefa a completar.'),
            _passo(2, 'Estuda/trabalha 25 minutos sem interrupções (1 Pomodoro).'),
            _passo(3, 'Faz uma pausa de 5 minutos.'),
            _passo(4, 'Repete os ciclos necessários.'),
            _passo(5, 'A cada 4 ciclos, faz uma pausa longa de 15–30 min.'),
            const SizedBox(height: 28),

            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                color: azul.withOpacity(0.08),
                border: Border.all(color: azul.withOpacity(0.3)),
              ),
              child: RichText(
                text: const TextSpan(
                  style: TextStyle(
                    fontSize: tamanhoTexto,
                    height: 1.6,
                    color: Colors.white,
                  ),
                  children: [
                    TextSpan(
                      text: 'Objetivo: ',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: azul,
                      ),
                    ),
                    TextSpan(
                      text:
                          'manter a concentração, evitar fadiga mental e aumentar a produtividade através de intervalos regulares.',
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 20),
            const Text(
              'No Thoth, podes personalizar totalmente os tempos de foco e descanso, bem como o número de ciclos para cada tarefa.',
              style: TextStyle(
                fontSize: tamanhoTexto,
                color: Colors.white70,
                height: 1.6,
              ),
            ),
            const SizedBox(height: 40),
            const Divider(color: Colors.white12),
          ],
        ),
      ),
    );
  }

  Widget _passo(int num, String texto) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 26,
            height: 26,
            margin: const EdgeInsets.only(right: 12, top: 2),
            decoration: const BoxDecoration(
              color: Color(0xFF1D81C7),
              shape: BoxShape.circle,
            ),
            child: Center(
              child: Text(
                '$num',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
          Expanded(
            child: Text(
              texto,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 15.5,
                height: 1.5,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
