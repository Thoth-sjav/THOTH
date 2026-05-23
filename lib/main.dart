import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Firebase.initializeApp();

  await SystemChrome.setPreferredOrientations([
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
  String citacao;

  PerfilUsuario({
    this.nome = '',
    this.nomedeutilizador = '',
    this.descricao = '',
    this.motivos = '',
    this.citacao = '',
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

// Notifier global: true = escuro, false = claro
final ValueNotifier<bool> temaEscuro = ValueNotifier<bool>(true);

// Shorthand helpers — read current theme value
Color _tc()      => temaEscuro.value ? Colors.white    : Colors.black87;   // text/icon color
Color _tc54()    => temaEscuro.value ? Colors.white54  : Colors.black45;
Color _tc38()    => temaEscuro.value ? Colors.white38  : Colors.black38;
Color _tc24()    => temaEscuro.value ? Colors.white24  : Colors.black12;
Color _tc12()    => temaEscuro.value ? Colors.white12  : Colors.black12;
Color _bgc()     => temaEscuro.value ? Colors.black    : Colors.white;

class ThothApp extends StatelessWidget {
  const ThothApp({super.key});

  static ThemeData _buildTheme(bool escuro) {
    const azul = Color(0xFF1D81C7);
    final bg = escuro ? Colors.black : Colors.white;
    final fg = escuro ? Colors.white : Colors.black87;
    final fgMid = escuro ? Colors.white54 : Colors.black45;

    return (escuro ? ThemeData.dark() : ThemeData.light()).copyWith(
      scaffoldBackgroundColor: bg,
      primaryColor: azul,
      cardColor: bg,
      dividerColor: escuro ? Colors.white24 : Colors.black12,
      colorScheme: escuro
          ? const ColorScheme.dark(primary: azul, surface: Colors.black)
          : ColorScheme.light(primary: azul, surface: Colors.white, onSurface: Colors.black87),
      appBarTheme: AppBarTheme(
        backgroundColor: bg,
        foregroundColor: fg,
        elevation: 0,
        centerTitle: false,
        titleTextStyle: TextStyle(color: fg, fontSize: 20, fontWeight: FontWeight.bold),
      ),
      iconTheme: IconThemeData(color: fg),
      textTheme: escuro
          ? ThemeData.dark().textTheme
          : ThemeData.light().textTheme.apply(bodyColor: Colors.black87, displayColor: Colors.black87),
      sliderTheme: const SliderThemeData(
        activeTrackColor: azul,
        thumbColor: azul,
        overlayColor: Color(0x291D81C7),
        inactiveTrackColor: Color(0x22000000),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: temaEscuro,
      builder: (_, escuro, __) => MaterialApp(
        debugShowCheckedModeBanner: false,
        title: 'Thoth',
        theme: _buildTheme(escuro),
        home: const AuthGate(),
      ),
    );
  }
}
class AuthGate extends StatelessWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context) {

    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),

      builder: (context, snapshot) {

        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(
              child: CircularProgressIndicator(),
            ),
          );
        }

        if (snapshot.hasData) {
          return const PomodoroApp();
        }

        return const LoginPage();
      },
    );
  }
}

class LoginPage extends StatelessWidget {
  const LoginPage({super.key});

  Future<void> signInWithGoogle(BuildContext context) async {
    try {
      final GoogleSignIn googleSignIn = GoogleSignIn(
        serverClientId:
            '639767112265-bedturi5tv013dcd2q2ifmo1j0sv9k2h.apps.googleusercontent.com',
      );

      final GoogleSignInAccount? googleUser = await googleSignIn.signIn();

      if (googleUser == null) return; // utilizador cancelou

      final GoogleSignInAuthentication googleAuth =
          await googleUser.authentication;

      if (googleAuth.idToken == null) {
        debugPrint('ERRO: idToken é null. Verifica o SHA-1 no Firebase Console.');
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Erro de autenticação. Tenta novamente.')),
          );
        }
        return;
      }

      final credential = GoogleAuthProvider.credential(
        accessToken: googleAuth.accessToken,
        idToken: googleAuth.idToken,
      );

      await FirebaseAuth.instance.signInWithCredential(credential);
    } catch (e) {
      debugPrint('Erro no login: $e');
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erro ao entrar: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {

    return Scaffold(
      backgroundColor: Colors.black,

      body: Center(
        child: ElevatedButton.icon(
          onPressed: () => signInWithGoogle(context),

          icon: const Icon(Icons.login),

          label: const Text('Entrar com Google'),

          style: ElevatedButton.styleFrom(
            padding: const EdgeInsets.symmetric(
              horizontal: 30,
              vertical: 18,
            ),
          ),
        ),
      ),
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
 List<Tarefa> tarefas = [];

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
  bool _primeiraVez = true;

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
      pausado = true;  // starts paused
      _primeiraVez = true;

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
    setState(() { pausado = !pausado; _primeiraVez = false; });
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
    final branco = _tc();

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
                  CircleAvatar(
                    radius: 35,
                    backgroundColor: Colors.black,
                    child: Icon(Icons.person, size: 40, color: branco),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    perfil.nome.isEmpty ? 'Utilizador' : perfil.nome,
                    style: TextStyle(
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
            icon: Icons.task_alt,
            label: 'Tarefas Concluídas',
            onTap: () {
              Navigator.pop(context);
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => _TelaTarefasConcluidas(state: state)),
              );
            },
          ),
          _drawerItem(
            icon: Icons.settings,
            label: 'Definições',
            onTap: () {
              Navigator.pop(context);
              Navigator.push(context, MaterialPageRoute(builder: (_) => const TelaDefinicoes()));
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
      title: Text(label, style: TextStyle(color: _tc())),
      onTap: onTap,
    );
  }
}

// =============================================================================
// TELA INICIAL
// =============================================================================

class _TelaInicial extends StatefulWidget {
  final _PomodoroAppState state;
  const _TelaInicial({required this.state});
  @override
  State<_TelaInicial> createState() => _TelaInicialState();
}

class _TelaInicialState extends State<_TelaInicial> {
  // Countdown target — editable
  DateTime _alvo = DateTime.now().add(const Duration(days: 47, hours: 9, minutes: 57));
  String _motivoAlvo = 'Exame';
  Timer? _tickTimer;

  @override
  void initState() {
    super.initState();
    // Refresh every minute so countdown stays live
    _tickTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _tickTimer?.cancel();
    super.dispose();
  }

  Duration get _restante {
    final d = _alvo.difference(DateTime.now());
    return d.isNegative ? Duration.zero : d;
  }

  Color get branco => _tc();

  void _editarAlvo() async {
    final ctrl = TextEditingController(text: _motivoAlvo);
    // Pick date first
    final data = await showDatePicker(
      context: context,
      initialDate: _alvo,
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 3650)),
      builder: (ctx, child) => Theme(
        data: Theme.of(ctx).copyWith(
          colorScheme: const ColorScheme.dark(primary: Color(0xFF1D81C7), surface: Color(0xFF111111)),
        ),
        child: child!,
      ),
    );
    if (data == null || !mounted) return;
    // Pick time
    final hora = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_alvo),
      builder: (ctx, child) => Theme(
        data: Theme.of(ctx).copyWith(
          colorScheme: const ColorScheme.dark(primary: Color(0xFF1D81C7), surface: Color(0xFF111111)),
        ),
        child: child!,
      ),
    );
    if (!mounted) return;
    final novoAlvo = hora == null
        ? DateTime(data.year, data.month, data.day)
        : DateTime(data.year, data.month, data.day, hora.hour, hora.minute);
    // Pick motivo
    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF111111),
        title: const Text('Motivo', style: TextStyle(color: Color(0xFF1D81C7))),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          style: TextStyle(color: _tc()),
          decoration: const InputDecoration(
            hintText: 'Ex: Exame de Matemática',
            hintStyle: TextStyle(color: Colors.white38),
            enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: Colors.white24)),
            focusedBorder: UnderlineInputBorder(borderSide: BorderSide(color: Color(0xFF1D81C7))),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
            child: const Text('OK', style: TextStyle(color: Color(0xFF1D81C7))),
          ),
        ],
      ),
    );
    if (!mounted) return;
    setState(() {
      _alvo = novoAlvo;
      if (ctrl.text.trim().isNotEmpty) _motivoAlvo = ctrl.text.trim();
    });
  }

  @override
  Widget build(BuildContext context) {
    const azul = _PomodoroAppState._azul;
    final ultimaTarefa = widget.state.ultimaTarefa;
    // Apenas tarefas NÃO concluídas (concluídas vão para o menu "Tarefas Concluídas")
    final tarefas = widget.state.tarefas.where((t) => t.progressoSalvo < 1.0).toList();

    final restante = _restante;
    final dias = restante.inDays;
    final horas = restante.inHours % 24;
    final mins = restante.inMinutes % 60;

    return Scaffold(
      key: widget.state._scaffoldKey,
      drawer: _MenuLateral(state: widget.state),
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Blue header bar (logo + tabs + menu) ──────────────
            ValueListenableBuilder<bool>(
              valueListenable: temaEscuro,
              builder: (_, _esc2, __) => Container(
              color: azul,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Row(
                children: [
                  // Realistic tomato logo
                  GestureDetector(
                    onTap: () {},
                    child: Container(
                      width: 40, height: 40,
                      decoration: const BoxDecoration(shape: BoxShape.circle, color: Colors.white),
                      child: ClipOval(
                        child: CustomPaint(painter: const _TomatoPainter(), size: const Size(40,40)),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  const Expanded(child: SizedBox()),
                  IconButton(
                    icon: const Icon(Icons.menu, color: Colors.white, size: 26),
                    onPressed: () => widget.state._scaffoldKey.currentState?.openDrawer(),
                    padding: EdgeInsets.zero, constraints: const BoxConstraints(),
                  ),
                ],
              ),
            )),

            // ── Hero section ──────────────────────────────────────────
            Container(
              color: azul,
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Thoth',
                          style: TextStyle(fontSize: 44, color: Colors.white,
                            fontWeight: FontWeight.bold, height: 1.0)),
                        const Text('Study helper - pomodoro',
                          style: TextStyle(fontSize: 13, color: Colors.white70)),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            // ── Quote ────────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(25, 10, 25, 0),
              child: Text(widget.state.perfil.citacao.isEmpty ? '' : '"${widget.state.perfil.citacao}"',
                style: TextStyle(fontSize: 12, color: _tc().withOpacity(0.55), fontStyle: FontStyle.italic),
                maxLines: 2),
            ),
            const SizedBox(height: 14),

            // ── Countdown ───────────────────────────────────────────
            GestureDetector(
              onTap: _editarAlvo,
              child: Container(
                margin: const EdgeInsets.symmetric(horizontal: 25),
                padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 18),
                decoration: BoxDecoration(
                  color: azul.withOpacity(0.08),
                  border: Border.all(color: azul.withOpacity(0.35)),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          'Faltam para $_motivoAlvo',
                          style: TextStyle(color: azul, fontSize: 13, fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(width: 6),
                        Icon(Icons.edit_outlined, color: azul, size: 14),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        _countUnit('$dias', 'dias'),
                        const SizedBox(width: 20),
                        _countUnit('$horas', 'horas'),
                        const SizedBox(width: 20),
                        _countUnit('$mins', 'minutos'),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

            // ── Retomar / Tarefas ────────────────────────────────────
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 25),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (ultimaTarefa != null &&
                        ultimaTarefa.progressoSalvo > 0.0 &&
                        ultimaTarefa.progressoSalvo < 1.0) ...[
                      _CartaoRetomar(state: widget.state, ultimaTarefa: ultimaTarefa),
                      const SizedBox(height: 16),
                    ],
                    const Text('Tarefas',
                      style: TextStyle(fontSize: 18, color: azul, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 10),
                    Expanded(
                      child: tarefas.isEmpty
                          ? Center(
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(Icons.inbox_outlined, size: 60, color: _tc().withOpacity(0.2)),
                                  const SizedBox(height: 16),
                                  Text('Nenhuma tarefa criada',
                                    style: TextStyle(color: _tc().withOpacity(0.4), fontSize: 16, fontWeight: FontWeight.w300)),
                                  const SizedBox(height: 8),
                                  Text('Toca em "Gerenciar Tarefas" para começar',
                                    style: TextStyle(color: _tc().withOpacity(0.25), fontSize: 13)),
                                ],
                              ),
                            )
                          : ListView.builder(
                              itemCount: tarefas.length,
                              itemBuilder: (ctx, i) => _CartaoTarefa(
                                tarefa: tarefas[i],
                                onTap: () => widget.state.iniciarTarefa(tarefas[i]),
                              ),
                            ),
                    ),
                    Padding(
                      padding: const EdgeInsets.only(bottom: 20, top: 10),
                      child: ElevatedButton(
                        onPressed: () =>
                            // ignore: invalid_use_of_protected_member
                            widget.state.setState(() => widget.state.estadoApp = EstadoApp.gerenciar),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: azul,
                          foregroundColor: branco,
                          minimumSize: const Size(double.infinity, 55),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        child: const Text('GERENCIAR TAREFAS',
                          style: TextStyle(fontWeight: FontWeight.bold, letterSpacing: 1)),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _countUnit(String val, String label) {
    const azul = Color(0xFF1D81C7);
    return Column(
      children: [
        Text(val,
          style: TextStyle(fontSize: 38, fontWeight: FontWeight.bold, color: _tc(), height: 1.0)),
        Text(label, style: const TextStyle(color: azul, fontSize: 12, fontWeight: FontWeight.bold)),
      ],
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
    final branco = _tc();
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
            style: TextStyle(color: _tc(), fontSize: 16, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: ultimaTarefa.progressoSalvo,
              color: azul,
              backgroundColor: _tc().withOpacity(0.1),
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
                  label: Text(
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
    final branco = _tc();
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
    final branco = _tc();
    final tarefas = state.tarefas;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Gerenciar Tarefas'),
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: _tc()),
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
                  Icon(Icons.add_task, size: 64, color: _tc().withOpacity(0.2)),
                  const SizedBox(height: 16),
                  Text(
                    'Nenhuma tarefa',
                    style: TextStyle(color: _tc().withOpacity(0.4), fontSize: 18),
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
    final branco = _tc();

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
            style: TextStyle(color: _tc(), fontWeight: FontWeight.bold),
          ),
          subtitle: Text(
            '${t.estudo ~/ 60}m foco · ${t.descanso ~/ 60}m descanso · ${t.ciclos} ciclos',
            style: const TextStyle(color: azul, fontSize: 13),
          ),
          leading: const Icon(Icons.drag_handle, color: Colors.white38),
          trailing: IconButton(
            icon: Icon(Icons.edit_outlined, color: _tc()),
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

  static const _presets = [];

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
              style: TextStyle(color: _tc()),
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
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: _tc(),
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
    final branco = _tc();

    final tarefa = state.tarefaAtual;
    if (tarefa == null) return const SizedBox();
    final estaNoDescanso = state.estaNoDescanso;
    final total = estaNoDescanso ? tarefa.descanso : tarefa.estudo;
    final progresso = total <= 0
        ? 0.0
        : (1 - (state.segundosRestantes / total)).clamp(0.0, 1.0);
    final pausado = state.pausado;

    return ValueListenableBuilder<bool>(
      valueListenable: temaEscuro,
      builder: (context, _e, __) {
      final tc = _tc(); final tc38 = _tc38();
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [



            // ── Timer body ──────────────────────────────────────────────────
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [

                  // Task name
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 30),
                    child: Text(
                      tarefa.nome.isEmpty ? 'Sem nome' : tarefa.nome,
                      style: const TextStyle(color: azul, letterSpacing: 2, fontSize: 16, fontWeight: FontWeight.w500),
                      textAlign: TextAlign.center,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(height: 6),

                  // FOCO / DESCANSO label
                  AnimatedSwitcher(
                    duration: const Duration(milliseconds: 300),
                    child: Text(
                      estaNoDescanso ? 'DESCANSO' : 'FOCO',
                      key: ValueKey(estaNoDescanso),
                      style: TextStyle(fontSize: 30, color: tc, fontWeight: FontWeight.bold, letterSpacing: 4),
                    ),
                  ),
                  const SizedBox(height: 40),

                  // Circular timer
                  Stack(
                    alignment: Alignment.center,
                    children: [
                      SizedBox(
                        width: 260, height: 260,
                        child: CircularProgressIndicator(
                          value: progresso,
                          strokeWidth: 8,
                          color: azul,
                          backgroundColor: tc.withOpacity(0.08),
                        ),
                      ),
                      Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            state.formatar(state.segundosRestantes),
                            style: TextStyle(fontSize: 58, fontWeight: FontWeight.w200, color: tc, letterSpacing: 2),
                          ),
                          if (pausado)
                            Text('PAUSADO',
                              style: TextStyle(color: tc38, fontSize: 12, letterSpacing: 3)),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 28),

                  // Cycle indicator
                  _IndicadorCiclos(
                    cicloAtual: state.cicloAtual,
                    totalCiclos: tarefa.ciclos,
                    estaNoDescanso: estaNoDescanso,
                  ),
                  const SizedBox(height: 48),

                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      _BotaoTimer(icon: Icons.stop_rounded, color: Colors.white38, onPressed: state.reset, tooltip: 'Parar'),
                      const SizedBox(width: 24),
                      _BotaoTimer(
                        icon: pausado ? Icons.play_arrow_rounded : Icons.pause_rounded,
                        color: tc, size: 56, onPressed: state.alternarPausa,
                        tooltip: state._primeiraVez ? 'Começar' : (pausado ? 'Continuar' : 'Pausar')),
                      const SizedBox(width: 24),
                      _BotaoTimer(icon: Icons.skip_next_rounded, color: Colors.white38, onPressed: state.pularFase, tooltip: 'Pular fase'),
                    ],
                  ),

                  const SizedBox(height: 20),
                ],
              ),
            ),
          ],
        ),
      ),
    );
    }); // end ValueListenableBuilder
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
    final branco = _tc();
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
              Text(
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

}
Widget _statItem(IconData icon, String valor, String label) {
  return Column(
    children: [
      Icon(icon, color: const Color(0xFF1D81C7), size: 28),
      const SizedBox(height: 6),

      Text(
        valor,
        style: TextStyle(
          color: _tc(),
          fontSize: 28,
          fontWeight: FontWeight.bold,
        ),
      ),

      Text(
        label,
        style: TextStyle(
          color: _tc().withOpacity(0.5),
          fontSize: 12,
        ),
      ),
    ],
  );
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
                      style: TextStyle(
                        fontSize: 50,
                        color: _tc(),
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
        style: TextStyle(color: _tc()),
        textCapitalization: TextCapitalization.sentences,
        decoration: InputDecoration(
          labelText: label,
          hintText: hint,
          hintStyle: TextStyle(color: _tc().withOpacity(0.3)),
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
                Text(
                  'To-do List',
                  style: TextStyle(
                    fontSize: 32,
                    fontWeight: FontWeight.bold,
                    color: _tc(),
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _todoCtrl,
                  style: TextStyle(color: _tc()),
                  textCapitalization: TextCapitalization.sentences,
                  decoration: InputDecoration(
                    hintText: 'Nova tarefa...',
                    hintStyle: const TextStyle(color: Colors.white54),
                    isDense: true,
                    enabledBorder: const UnderlineInputBorder(
                      borderSide: BorderSide(color: Colors.white30),
                    ),
                    focusedBorder: UnderlineInputBorder(
                      borderSide: BorderSide(color: _tc()),
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
                            style: TextStyle(color: _tc()),
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
                            style: TextStyle(color: _tc()),
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
                          style: TextStyle(color: _tc()),
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
                ? Border.all(color: _tc(), width: 2)
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
        child: Transform.rotate(
          angle: 0.03,
          child: Container(
            width: 160,
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(
              color: _tc(),
              borderRadius: BorderRadius.circular(10),
              boxShadow: [
                BoxShadow(color: Colors.black38, blurRadius: 14, offset: Offset(0, 6)),
              ],
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.drag_indicator, size: 14, color: Colors.black38),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(
                    item.texto,
                    style: const TextStyle(fontSize: 13, color: Colors.black87, fontWeight: FontWeight.w600),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
      childWhenDragging: Opacity(opacity: 0.25, child: _buildUI()),
      child: _buildUI(),
    );
  }

  Widget _buildUI() {
    return InkWell(
      onTap: () => onToggle(item),
      onLongPress: () => onRemover(item),
      borderRadius: BorderRadius.circular(6),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          children: [
            const Icon(Icons.drag_indicator, size: 13, color: Colors.black26),
            const SizedBox(width: 4),
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
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                item.texto,
                style: TextStyle(
                  fontSize: 13,
                  color: Colors.black87,
                  decoration: item.concluido ? TextDecoration.lineThrough : TextDecoration.none,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
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
                  Icon(Icons.bar_chart, size: 64, color: _tc().withOpacity(0.15)),
                  const SizedBox(height: 16),
                  Text(
                    'Nenhuma sessão concluída',
                    style: TextStyle(
                      color: _tc().withOpacity(0.4),
                      fontSize: 18,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Completa uma tarefa para ver os insights',
                    style: TextStyle(
                      color: _tc().withOpacity(0.25),
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

                  // Gráfico de barras
                  if (contagem.isNotEmpty) ...[
                    const Text(
                      'Tempo de foco por tarefa',
                      style: TextStyle(color: Color(0xFF1D81C7), fontSize: 16, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 16),
                    _GraficoBarras(contagem: contagem),
                    const SizedBox(height: 24),
                  ],

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
              color: _tc(),
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
              color: _tc().withOpacity(0.4),
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
        border: Border.all(color: _tc().withOpacity(0.1)),
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
                  style: TextStyle(
                    color: _tc(),
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                  ),
                ),
                Text(
                  '${s.ciclosConcluidos} ciclos · ${_formatarTempo(s.tempoFocoSegundos)} foco',
                  style: TextStyle(
                    color: _tc().withOpacity(0.5),
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          Text(
            data,
            style: TextStyle(color: _tc().withOpacity(0.3), fontSize: 11),
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
                text: TextSpan(
                  style: TextStyle(
                    fontSize: tamanhoTexto,
                    height: 1.6,
                    color: _tc(),
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
                style: TextStyle(
                  color: _tc(),
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
          Expanded(
            child: Text(
              texto,
              style: TextStyle(
                color: _tc(),
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

// =============================================================================
// GRÁFICO DE BARRAS
// =============================================================================

class _GraficoBarras extends StatelessWidget {
  final Map<String, int> contagem;
  const _GraficoBarras({required this.contagem});

  static const List<Color> _cores = [
    Color(0xFF4CAF50), Color(0xFF9C27B0),
    Color(0xFFFF9800), Color(0xFFFFEB3B),
    Color(0xFF2196F3), Color(0xFFE91E63),
  ];

  String _fmt(int s) {
    if (s >= 3600) {
      final h = s ~/ 3600;
      final m = (s % 3600) ~/ 60;
      return m > 0 ? '${h}h${m}m' : '${h}h';
    }
    return '${s ~/ 60}m';
  }

  @override
  Widget build(BuildContext context) {
    final entries = contagem.entries.toList();
    final maxVal = entries.map((e) => e.value).reduce((a, b) => a > b ? a : b);
    const maxH = 130.0;

    return SizedBox(
      height: maxH + 50,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          // Y axis
          Column(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(_fmt(maxVal), style: TextStyle(fontSize: 9, color: _tc38())),
              Text(_fmt(maxVal ~/ 2), style: TextStyle(fontSize: 9, color: _tc38())),
              Text('0', style: TextStyle(fontSize: 9, color: _tc38())),
              const SizedBox(height: 28),
            ],
          ),
          const SizedBox(width: 6),
          // Bars
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: entries.asMap().entries.map((e) {
                final idx = e.key;
                final kv = e.value;
                final ratio = maxVal == 0 ? 0.0 : kv.value / maxVal;
                final barH = (ratio * maxH).clamp(4.0, maxH);
                final cor = _cores[idx % _cores.length];
                final label = kv.key.length > 7 ? kv.key.substring(0, 7) : kv.key;
                return Column(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    Text(_fmt(kv.value), style: TextStyle(color: cor, fontSize: 9, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 3),
                    Container(
                      width: 32,
                      height: barH,
                      decoration: BoxDecoration(
                        color: cor,
                        borderRadius: const BorderRadius.vertical(top: Radius.circular(5)),
                      ),
                    ),
                    const SizedBox(height: 5),
                    SizedBox(
                      width: 44,
                      child: Text(label,
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: Colors.white54, fontSize: 9),
                        maxLines: 2, overflow: TextOverflow.ellipsis),
                    ),
                  ],
                );
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }
}

// =============================================================================
// TELA DEFINIÇÕES
// =============================================================================

class TelaDefinicoes extends StatefulWidget {
  const TelaDefinicoes({super.key});
  @override
  State<TelaDefinicoes> createState() => _TelaDefinicoesState();
}

class _TelaDefinicoesState extends State<TelaDefinicoes> {
  String _account  = 'ABCD_1234';
  String _email    = 'abcd1234@gmail.com';
  bool   _notifs   = true;
  bool   _privado  = false;

  static const azul = Color(0xFF1D81C7);

  // Generic editable text dialog
  Future<String?> _editText(String titulo, String atual, {bool email = false}) {
    final ctrl = TextEditingController(text: atual);
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: temaEscuro.value ? const Color(0xFF111111) : Colors.white,
        title: Text(titulo, style: const TextStyle(color: azul)),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          keyboardType: email ? TextInputType.emailAddress : TextInputType.text,
          style: TextStyle(color: temaEscuro.value ? Colors.white : Colors.black87),
          decoration: InputDecoration(
            enabledBorder: const UnderlineInputBorder(borderSide: BorderSide(color: Colors.white24)),
            focusedBorder: const UnderlineInputBorder(borderSide: BorderSide(color: azul)),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
            child: const Text('Guardar', style: TextStyle(color: azul)),
          ),
        ],
      ),
    );
  }

  void _confirmarEliminar() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: temaEscuro.value ? const Color(0xFF111111) : Colors.white,
        title: const Text('Eliminar conta?', style: TextStyle(color: Colors.redAccent)),
        content: Text('Esta acção é irreversível.',
          style: TextStyle(color: temaEscuro.value ? Colors.white70 : Colors.black54)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')),
          TextButton(
            onPressed: () { Navigator.pop(ctx); Navigator.pop(context); },
            child: const Text('Eliminar', style: TextStyle(color: Colors.redAccent)),
          ),
        ],
      ),
    );
  }

  void _confirmarLogout() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: temaEscuro.value ? const Color(0xFF111111) : Colors.white,
        title: Text('Terminar sessão?',
          style: TextStyle(color: temaEscuro.value ? Colors.white : Colors.black87)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')),
          TextButton(
           onPressed: () async {

  await GoogleSignIn().signOut();

  await FirebaseAuth.instance.signOut();

  if (context.mounted) {
    Navigator.pop(ctx);
  }
},
            child: const Text('Log out', style: TextStyle(color: azul)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: temaEscuro,
      builder: (context, escuro, _) {
        final bg      = escuro ? Colors.black : Colors.white;
        final fg      = escuro ? Colors.white : Colors.black87;
        final fgMuted = escuro ? Colors.white54 : Colors.black45;
        final border  = escuro ? Colors.white12 : Colors.black12;
        final tileBg  = escuro ? const Color(0xFF111111) : const Color(0xFFF5F5F5);

        return Scaffold(
          backgroundColor: bg,
          appBar: AppBar(
            backgroundColor: bg,
            foregroundColor: fg,
            title: Text('Definições', style: TextStyle(color: fg, fontWeight: FontWeight.bold)),
            bottom: const PreferredSize(
              preferredSize: Size.fromHeight(1),
              child: Divider(color: azul, height: 1),
            ),
          ),
          body: ListView(
            padding: const EdgeInsets.all(20),
            children: [

              // ── Aparência ──────────────────────────────────────
              Text('APARÊNCIA', style: const TextStyle(color: azul, fontSize: 12, fontWeight: FontWeight.bold, letterSpacing: 1.5)),
              const SizedBox(height: 10),
              Container(
                decoration: BoxDecoration(color: tileBg, borderRadius: BorderRadius.circular(14), border: Border.all(color: border)),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
                  child: Row(
                    children: [
                      AnimatedSwitcher(
                        duration: const Duration(milliseconds: 250),
                        child: Icon(escuro ? Icons.dark_mode_outlined : Icons.light_mode_outlined,
                          key: ValueKey(escuro), color: azul, size: 26),
                      ),
                      const SizedBox(width: 16),
                      Expanded(child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(escuro ? 'Tema escuro' : 'Tema claro',
                            style: TextStyle(color: fg, fontSize: 16, fontWeight: FontWeight.w600)),
                          Text(escuro ? 'Fundo preto' : 'Fundo branco',
                            style: TextStyle(color: fgMuted, fontSize: 12)),
                        ],
                      )),
                      GestureDetector(
                        onTap: () => temaEscuro.value = !escuro,
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 250),
                          width: 52, height: 28,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(14),
                            color: escuro ? azul : Colors.grey.shade300,
                          ),
                          child: AnimatedAlign(
                            duration: const Duration(milliseconds: 250),
                            alignment: escuro ? Alignment.centerRight : Alignment.centerLeft,
                            child: Padding(
                              padding: const EdgeInsets.all(3),
                              child: Container(
                                width: 22, height: 22,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle, color: _tc(),
                                  boxShadow: [BoxShadow(color: Colors.black26, blurRadius: 3)]),
                                child: Icon(escuro ? Icons.nightlight_round : Icons.wb_sunny_rounded,
                                  size: 13, color: escuro ? azul : Colors.orange),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(color: tileBg, borderRadius: BorderRadius.circular(14), border: Border.all(color: border)),
                child: Row(children: [
                  _MiniPreview(dark: true,  selected: escuro,  onTap: () => temaEscuro.value = true,  label: 'Escuro'),
                  const SizedBox(width: 12),
                  _MiniPreview(dark: false, selected: !escuro, onTap: () => temaEscuro.value = false, label: 'Claro'),
                ]),
              ),
              const SizedBox(height: 28),

              // ── Conta ──────────────────────────────────────────
              Text('CONTA', style: const TextStyle(color: azul, fontSize: 12, fontWeight: FontWeight.bold, letterSpacing: 1.5)),
              const SizedBox(height: 10),

              // Account
              _tile(Icons.account_circle_outlined, 'Account', _account, fg, fgMuted, tileBg, border,
                onTap: () async {
                  final v = await _editText('Account', _account);
                  if (v != null && v.isNotEmpty) setState(() => _account = v);
                }),

              // Email
              _tile(Icons.mail_outline, 'Email', _email, fg, fgMuted, tileBg, border,
                onTap: () async {
                  final v = await _editText('Email', _email, email: true);
                  if (v != null && v.isNotEmpty) setState(() => _email = v);
                }),

              // Notificações (toggle)
              _tileToggle(Icons.notifications_outlined, 'Notificações', _notifs, fg, fgMuted, tileBg, border,
                onChanged: (v) => setState(() => _notifs = v)),

              // Privacidade (toggle)
              _tileToggle(Icons.lock_outline, 'Privacidade', _privado, fg, fgMuted, tileBg, border,
                onChanged: (v) => setState(() => _privado = v)),

              // Log out
              _tile(Icons.logout, 'Log out', null, fg, fgMuted, tileBg, border,
                onTap: _confirmarLogout),

              const SizedBox(height: 8),

              // Eliminar conta
              _tile(Icons.delete_outline, 'Eliminar conta!', null,
                Colors.redAccent, Colors.redAccent.withOpacity(0.6),
                Colors.red.withOpacity(0.04), Colors.redAccent.withOpacity(0.25),
                onTap: _confirmarEliminar, bold: true),
            ],
          ),
        );
      },
    );
  }

  Widget _tile(IconData icon, String titulo, String? valor,
      Color fg, Color fgMuted, Color bg, Color border,
      {required VoidCallback onTap, bool bold = false}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: bg, borderRadius: BorderRadius.circular(14), border: Border.all(color: border)),
        child: Row(children: [
          Icon(icon, color: bold ? Colors.redAccent : azul, size: 22),
          const SizedBox(width: 14),
          Expanded(child: Text(titulo,
            style: TextStyle(color: fg, fontSize: 15,
              fontWeight: bold ? FontWeight.bold : FontWeight.normal))),
          if (valor != null)
            Text(valor, style: TextStyle(color: fgMuted, fontSize: 13))
          else if (!bold)
            Icon(Icons.chevron_right, color: fgMuted, size: 20),
        ]),
      ),
    );
  }

  Widget _tileToggle(IconData icon, String titulo, bool valor,
      Color fg, Color fgMuted, Color bg, Color border,
      {required ValueChanged<bool> onChanged}) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: bg, borderRadius: BorderRadius.circular(14), border: Border.all(color: border)),
      child: Row(children: [
        Icon(icon, color: azul, size: 22),
        const SizedBox(width: 14),
        Expanded(child: Text(titulo, style: TextStyle(color: fg, fontSize: 15))),
        Switch(
          value: valor,
          onChanged: onChanged,
          activeColor: azul,
        ),
      ]),
    );
  }
}

class _MiniPreview extends StatelessWidget {
  final bool dark;
  final bool selected;
  final VoidCallback onTap;
  final String label;
  const _MiniPreview({required this.dark, required this.selected, required this.onTap, required this.label});

  @override
  Widget build(BuildContext context) {
    const azul = Color(0xFF1D81C7);
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: dark ? Colors.black : Colors.white,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: selected ? azul : Colors.transparent, width: 2),
            boxShadow: [BoxShadow(color: Colors.black26, blurRadius: 6, offset: const Offset(0, 2))],
          ),
          child: Column(
            children: [
              Container(height: 7, width: 55, margin: const EdgeInsets.only(bottom: 5),
                decoration: BoxDecoration(color: azul, borderRadius: BorderRadius.circular(4))),
              Container(height: 4, width: 45, margin: const EdgeInsets.only(bottom: 4),
                decoration: BoxDecoration(
                  color: dark ? Colors.white24 : Colors.black26,
                  borderRadius: BorderRadius.circular(3))),
              Container(height: 4, width: 35,
                decoration: BoxDecoration(
                  color: dark ? Colors.white12 : Colors.black12,
                  borderRadius: BorderRadius.circular(3))),
              const SizedBox(height: 7),
              Text(label, style: TextStyle(
                color: dark ? Colors.white70 : Colors.black54,
                fontSize: 11, fontWeight: FontWeight.w600)),
              if (selected)
                const Padding(padding: EdgeInsets.only(top: 3),
                  child: Icon(Icons.check_circle, color: azul, size: 13)),
            ],
          ),
        ),
      ),
    );
  }
}

// =============================================================================
// TOMATO PAINTER
// =============================================================================

// =============================================================================
// TELA: TAREFAS CONCLUÍDAS
// =============================================================================
class _TelaTarefasConcluidas extends StatefulWidget {
  final _PomodoroAppState state;
  const _TelaTarefasConcluidas({required this.state});
  @override
  State<_TelaTarefasConcluidas> createState() => _TelaTarefasConcluidasState();
}

class _TelaTarefasConcluidasState extends State<_TelaTarefasConcluidas> {
  @override
  Widget build(BuildContext context) {
    const azul = _PomodoroAppState._azul;
    final concluidas = widget.state.tarefas.where((t) => t.progressoSalvo >= 1.0).toList();
    return Scaffold(
      appBar: AppBar(
        title: const Text('Tarefas Concluídas'),
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: _tc()),
          onPressed: () => Navigator.pop(context),
        ),
        bottom: const PreferredSize(
          preferredSize: Size.fromHeight(1),
          child: Divider(color: azul, height: 1),
        ),
      ),
      body: concluidas.isEmpty
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.emoji_events_outlined, size: 70, color: _tc().withOpacity(0.2)),
                  const SizedBox(height: 16),
                  Text('Ainda sem tarefas concluídas',
                      style: TextStyle(color: _tc().withOpacity(0.5), fontSize: 16)),
                  const SizedBox(height: 6),
                  Text('Quando terminares uma tarefa, ela aparece aqui.',
                      style: TextStyle(color: _tc().withOpacity(0.3), fontSize: 12)),
                ],
              ),
            )
          : ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: concluidas.length,
              itemBuilder: (ctx, i) {
                final t = concluidas[i];
                return Container(
                  margin: const EdgeInsets.only(bottom: 12),
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.greenAccent.withOpacity(0.5)),
                    borderRadius: BorderRadius.circular(12),
                    color: Colors.greenAccent.withOpacity(0.05),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.check_circle, color: Colors.greenAccent, size: 32),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(t.nome.isEmpty ? 'Sem nome' : t.nome,
                                style: TextStyle(color: _tc(), fontWeight: FontWeight.bold, fontSize: 16)),
                            const SizedBox(height: 4),
                            Text(
                              'Foco: ${t.estudo ~/ 60}m  ·  Descanso: ${t.descanso ~/ 60}m  ·  ${t.ciclos} ciclos',
                              style: const TextStyle(color: azul, fontSize: 12),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        tooltip: 'Reabrir tarefa',
                        icon: Icon(Icons.refresh, color: _tc().withOpacity(0.7)),
                        onPressed: () {
                          // ignore: invalid_use_of_protected_member
                          widget.state.setState(() {
                            t.progressoSalvo = 0.0;
                            t.cicloSalvo = 1;
                            t.estavaNoDescanso = false;
                            t.segundosSalvos = t.estudo;
                          });
                          setState(() {});
                        },
                      ),
                      IconButton(
                        tooltip: 'Eliminar definitivamente',
                        icon: const Icon(Icons.delete_outline, color: Colors.redAccent),
                        onPressed: () {
                          // ignore: invalid_use_of_protected_member
                          widget.state.setState(() {
                            widget.state.tarefas.removeWhere((x) => x.id == t.id);
                            if (widget.state.ultimaTarefa?.id == t.id) {
                              widget.state.ultimaTarefa = null;
                            }
                          });
                          setState(() {});
                        },
                      ),
                    ],
                  ),
                );
              },
            ),
    );
  }
}


/// Logo de tomate realista: corpo esférico com gradiente radial,
/// sulco vertical, sombra inferior, brilho especular, sépalas (folhas
/// estreladas em volta do pedúnculo) e haste curva.
class _TomatoPainter extends CustomPainter {
  const _TomatoPainter();
  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final cy = size.height / 2 + size.height * 0.10;
    final r  = size.width * 0.40;

    // ── 1. Sombra debaixo (no canvas, parece "assenta") ─────────────────
    final shadow = Paint()
      ..color = Colors.black.withOpacity(0.18)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3);
    canvas.drawOval(
      Rect.fromCenter(center: Offset(cx, cy + r * 0.95), width: r * 1.6, height: r * 0.32),
      shadow,
    );

    // ── 2. Corpo do tomate ─ esfera achatada com gradiente radial ───────
    final bodyRect = Rect.fromCenter(center: Offset(cx, cy), width: r * 2.05, height: r * 1.95);
    final body = Paint()
      ..shader = RadialGradient(
        center: const Alignment(-0.35, -0.45), radius: 1.05,
        colors: const [
          Color(0xFFFF8A65), // highlight quente
          Color(0xFFEF5350), // vermelho médio
          Color(0xFFD32F2F), // vermelho saturado
          Color(0xFF8B1B1B), // sombra escura
        ],
        stops: const [0.0, 0.45, 0.78, 1.0],
      ).createShader(bodyRect);
    canvas.drawOval(bodyRect, body);

    // ── 3. Sulco vertical (acanaladuras típicas do tomate) ──────────────
    final groove = Paint()
      ..color = const Color(0xFF7A1212).withOpacity(0.25)
      ..style = PaintingStyle.stroke
      ..strokeWidth = r * 0.04;
    for (final dx in [-0.55, 0.0, 0.55]) {
      final path = Path()
        ..moveTo(cx + r * dx * 0.9, cy - r * 0.85)
        ..quadraticBezierTo(cx + r * dx, cy, cx + r * dx * 0.9, cy + r * 0.85);
      canvas.drawPath(path, groove);
    }

    // ── 4. Brilho especular suave (gota de luz) ─────────────────────────
    canvas.drawOval(
      Rect.fromCenter(center: Offset(cx - r * 0.30, cy - r * 0.45), width: r * 0.55, height: r * 0.30),
      Paint()
        ..color = Colors.white.withOpacity(0.40)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 1.5),
    );
    // brilho secundário pequeno
    canvas.drawCircle(
      Offset(cx - r * 0.15, cy - r * 0.55),
      r * 0.06,
      Paint()..color = Colors.white.withOpacity(0.75),
    );

    // ── 5. Sépalas (estrela verde de 5 pontas sobre o topo) ─────────────
    final calyxCenter = Offset(cx, cy - r * 0.85);
    final calyxColor = const Color(0xFF2E7D32);
    final calyxLight = const Color(0xFF66BB6A);
    final sepalPath = Path();
    const numLeaves = 5;
    for (int i = 0; i < numLeaves; i++) {
      final angle = -math.pi / 2 + (i * 2 * math.pi / numLeaves);
      final tip = Offset(
        calyxCenter.dx + math.cos(angle) * r * 0.55,
        calyxCenter.dy + math.sin(angle) * r * 0.42 - r * 0.05,
      );
      final leftCtrl = Offset(
        calyxCenter.dx + math.cos(angle - 0.45) * r * 0.32,
        calyxCenter.dy + math.sin(angle - 0.45) * r * 0.20,
      );
      final rightCtrl = Offset(
        calyxCenter.dx + math.cos(angle + 0.45) * r * 0.32,
        calyxCenter.dy + math.sin(angle + 0.45) * r * 0.20,
      );
      sepalPath
        ..moveTo(calyxCenter.dx, calyxCenter.dy)
        ..quadraticBezierTo(leftCtrl.dx, leftCtrl.dy, tip.dx, tip.dy)
        ..quadraticBezierTo(rightCtrl.dx, rightCtrl.dy, calyxCenter.dx, calyxCenter.dy)
        ..close();
    }
    // Sombra das sépalas
    canvas.drawPath(
      sepalPath.shift(Offset(0, r * 0.04)),
      Paint()..color = Colors.black.withOpacity(0.25)..maskFilter = const MaskFilter.blur(BlurStyle.normal, 1.2),
    );
    // Sépalas com gradiente
    final sepalShader = RadialGradient(
      center: const Alignment(-0.2, -0.4),
      colors: [calyxLight, calyxColor],
    ).createShader(Rect.fromCenter(center: calyxCenter, width: r * 1.2, height: r * 0.8));
    canvas.drawPath(sepalPath, Paint()..shader = sepalShader);
    // Linhas centrais nas sépalas para definição
    final veinPaint = Paint()
      ..color = const Color(0xFF1B5E20).withOpacity(0.55)
      ..style = PaintingStyle.stroke
      ..strokeWidth = r * 0.025
      ..strokeCap = StrokeCap.round;
    for (int i = 0; i < numLeaves; i++) {
      final angle = -math.pi / 2 + (i * 2 * math.pi / numLeaves);
      canvas.drawLine(
        calyxCenter,
        Offset(
          calyxCenter.dx + math.cos(angle) * r * 0.45,
          calyxCenter.dy + math.sin(angle) * r * 0.35 - r * 0.05,
        ),
        veinPaint,
      );
    }

    // ── 6. Haste castanha curva ─────────────────────────────────────────
    final stemPath = Path()
      ..moveTo(calyxCenter.dx, calyxCenter.dy)
      ..quadraticBezierTo(
        calyxCenter.dx + r * 0.18, calyxCenter.dy - r * 0.30,
        calyxCenter.dx + r * 0.08, calyxCenter.dy - r * 0.55,
      );
    canvas.drawPath(
      stemPath,
      Paint()
        ..color = const Color(0xFF5D4037)
        ..strokeWidth = r * 0.10
        ..strokeCap = StrokeCap.round
        ..style = PaintingStyle.stroke,
    );
    // brilho na haste
    canvas.drawPath(
      stemPath,
      Paint()
        ..color = const Color(0xFF8D6E63).withOpacity(0.6)
        ..strokeWidth = r * 0.04
        ..strokeCap = StrokeCap.round
        ..style = PaintingStyle.stroke,
    );
  }

  @override bool shouldRepaint(covariant CustomPainter _) => false;
}
