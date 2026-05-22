import 'dart:async';
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'firebase_options.dart';
import 'services/auth_service.dart';
import 'services/database_service.dart';
import 'models/tarefa.dart';
import 'models/sessao.dart';
import 'models/item_todo.dart';
import 'models/perfil_usuario.dart';
import 'screens/tela_login.dart';
import 'screens/tela_insights.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  runApp(const ThothApp());
}

// --- APP PRINCIPAL ---

class ThothApp extends StatelessWidget {
  const ThothApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: Colors.black,
        primaryColor: const Color(0xFF1D81C7),
        cardColor: Colors.black,
        dividerColor: Colors.white,
      ),
      home: const AuthWrapper(),
    );
  }
}

// --- AUTH WRAPPER (decide se mostra Login ou App) ---

class AuthWrapper extends StatelessWidget {
  const AuthWrapper({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: AuthService().authStateChanges,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            backgroundColor: Colors.black,
            body: Center(child: CircularProgressIndicator(color: Color(0xFF1D81C7))),
          );
        }
        if (snapshot.hasData) {
          return const PomodoroApp();
        }
        return const TelaLogin();
      },
    );
  }
}

// --- POMODORO APP ---

class PomodoroApp extends StatefulWidget {
  const PomodoroApp({super.key});

  @override
  State<PomodoroApp> createState() => _PomodoroAppState();
}

class _PomodoroAppState extends State<PomodoroApp> {
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  final AuthService _auth = AuthService();
  final DatabaseService _db = DatabaseService();

  List<Tarefa> tarefas = [];
  List<ItemTodo> notasTodo = [];
  PerfilUsuario perfil = PerfilUsuario();

  Tarefa? ultimaTarefa;
  Tarefa? tarefaAtual;
  DateTime? _sessaoInicio;

  int estadoApp = 0;
  int cicloAtual = 1;
  bool estaNoDescanso = false;
  int segundosRestantes = 0;
  int _totalFocoAcumulado = 0;
  int _totalDescansoAcumulado = 0;

  Timer? timer;
  bool pausado = false;

  final Color azul = const Color(0xFF1D81C7);
  final Color preto = Colors.black;
  final Color branco = Colors.white;

  @override
  void initState() {
    super.initState();
    _carregarPerfil();
  }

  Future<void> _carregarPerfil() async {
    final p = await _db.carregarPerfil();
    if (mounted) setState(() => perfil = p);
  }

  // ---------------- LÓGICA POMODORO ----------------

  void iniciarTarefa(Tarefa t, {bool retomar = false}) {
    _sessaoInicio = DateTime.now();
    _totalFocoAcumulado = 0;
    _totalDescansoAcumulado = 0;

    setState(() {
      tarefaAtual = t;
      estadoApp = 1;
      if (!retomar) {
        cicloAtual = 1;
        segundosRestantes = t.estudo;
        estaNoDescanso = false;
      } else {
        cicloAtual = (t.progressoSalvo * t.ciclos).ceil().clamp(1, t.ciclos);
        segundosRestantes = t.estudo;
      }
      pausado = false;
    });

    timer?.cancel();
    timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!pausado) {
        setState(() {
          if (segundosRestantes > 0) {
            segundosRestantes--;
            if (estaNoDescanso) {
              _totalDescansoAcumulado++;
            } else {
              _totalFocoAcumulado++;
            }
            tarefaAtual!.progressoSalvo = progressoGlobal();
            ultimaTarefa = tarefaAtual;
            _db.atualizarProgressoTarefa(tarefaAtual!.id, tarefaAtual!.progressoSalvo);
          } else {
            proximaFase();
          }
        });
      }
    });
  }

  double progressoGlobal() {
    if (tarefaAtual == null) return 0.0;
    double p = ((cicloAtual - 1) +
            (1 -
                segundosRestantes /
                    (estaNoDescanso
                        ? tarefaAtual!.descanso
                        : tarefaAtual!.estudo))) /
        tarefaAtual!.ciclos;
    return p.clamp(0.0, 1.0);
  }

  void proximaFase() {
    if (!estaNoDescanso) {
      if (cicloAtual >= tarefaAtual!.ciclos) {
        finalizar();
      } else {
        setState(() {
          estaNoDescanso = true;
          segundosRestantes = tarefaAtual!.descanso;
        });
      }
    } else {
      setState(() {
        cicloAtual++;
        estaNoDescanso = false;
        segundosRestantes = tarefaAtual!.estudo;
      });
    }
  }

  Future<void> finalizar() async {
    timer?.cancel();
    tarefaAtual!.progressoSalvo = 1.0;
    await _db.atualizarProgressoTarefa(tarefaAtual!.id, 1.0);
    await _guardarSessao(concluida: true);
    if (mounted) setState(() => estadoApp = 2);
  }

  Future<void> _guardarSessao({required bool concluida}) async {
    if (tarefaAtual == null || _sessaoInicio == null) return;
    final sessao = Sessao(
      id: '',
      tarefaId: tarefaAtual!.id,
      tarefaNome: tarefaAtual!.nome.isEmpty ? "Sem nome" : tarefaAtual!.nome,
      dataInicio: _sessaoInicio!,
      dataFim: DateTime.now(),
      ciclosCompletos: concluida ? tarefaAtual!.ciclos : cicloAtual - 1,
      totalFocoSegundos: _totalFocoAcumulado,
      totalDescansoSegundos: _totalDescansoAcumulado,
      concluida: concluida,
    );
    await _db.guardarSessao(sessao);
  }

  Future<void> reset() async {
    timer?.cancel();
    if (tarefaAtual != null && estadoApp == 1) {
      await _guardarSessao(concluida: false);
    }
    if (mounted) setState(() => estadoApp = 0);
  }

  Future<void> removerTarefa(String tarefaId) async {
    await _db.removerTarefa(tarefaId);
    setState(() {
      if (ultimaTarefa?.id == tarefaId) ultimaTarefa = null;
    });
  }

  String formatar(int s) =>
      "${(s ~/ 60).toString().padLeft(2, '0')}:${(s % 60).toString().padLeft(2, '0')}";

  // ---------------- BUILD ----------------

  @override
  Widget build(BuildContext context) {
    if (estadoApp == 1) return telaCronometro();
    if (estadoApp == 2) return telaFim();
    if (estadoApp == 3) return telaGerenciar();
    return telaInicial();
  }

  // ---------------- MENU LATERAL ----------------

  Widget menuLateral() {
    final user = FirebaseAuth.instance.currentUser;
    return Drawer(
      backgroundColor: preto,
      child: Column(
        children: [
          DrawerHeader(
            decoration: BoxDecoration(color: azul),
            child: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  CircleAvatar(
                    radius: 35,
                    backgroundColor: preto,
                    backgroundImage: user?.photoURL != null
                        ? NetworkImage(user!.photoURL!)
                        : null,
                    child: user?.photoURL == null
                        ? Icon(Icons.person, size: 40, color: branco)
                        : null,
                  ),
                  const SizedBox(height: 10),
                  Text(
                    perfil.nome.isNotEmpty
                        ? perfil.nome
                        : (user?.displayName ?? "Utilizador"),
                    style: TextStyle(color: branco, fontSize: 20, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    user?.email ?? '',
                    style: TextStyle(color: branco.withOpacity(0.6), fontSize: 11),
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (perfil.cognome.isNotEmpty)
                    Text(perfil.cognome, style: TextStyle(color: branco.withOpacity(0.8), fontSize: 12)),
                ],
              ),
            ),
          ),
          ListTile(
            leading: Icon(Icons.info_outline, color: branco),
            title: Text("O que é o Pomodoro", style: TextStyle(color: branco)),
            onTap: () {
              Navigator.pop(context);
              Navigator.push(context, MaterialPageRoute(builder: (_) => const TelaPomodoroInfo()));
            },
          ),
          ListTile(
            leading: Icon(Icons.account_circle_outlined, color: branco),
            title: Text("Perfil", style: TextStyle(color: branco)),
            onTap: () async {
              Navigator.pop(context);
              final resultado = await Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => TelaPerfil(perfil: perfil)),
              );
              if (resultado != null) {
                setState(() => perfil = resultado);
                await _db.guardarPerfil(resultado);
              }
            },
          ),
          ListTile(
            leading: Icon(Icons.checklist_rtl, color: branco),
            title: Text("To-do List", style: TextStyle(color: branco)),
            onTap: () {
              Navigator.pop(context);
              Navigator.push(context, MaterialPageRoute(builder: (_) => TelaTodo(lista: notasTodo)));
            },
          ),
          ListTile(
            leading: Icon(Icons.bar_chart, color: branco),
            title: Text("Insights", style: TextStyle(color: branco)),
            onTap: () {
              Navigator.pop(context);
              Navigator.push(context, MaterialPageRoute(builder: (_) => const TelaInsights()));
            },
          ),
          ListTile(
            leading: Icon(Icons.settings, color: branco),
            title: Text("Definições", style: TextStyle(color: branco)),
            onTap: () {},
          ),
          const Spacer(),
          ListTile(
            leading: Icon(Icons.logout, color: Colors.redAccent.withOpacity(0.8)),
            title: Text("Terminar Sessão", style: TextStyle(color: Colors.redAccent.withOpacity(0.8))),
            onTap: () async {
              Navigator.pop(context);
              await _auth.logout();
            },
          ),
          Padding(
            padding: const EdgeInsets.all(20.0),
            child: Text("Thoth", style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, letterSpacing: 3, color: azul)),
          ),
        ],
      ),
    );
  }

  // ---------------- TELA INICIAL ----------------

  Widget telaInicial() {
    return Scaffold(
      key: _scaffoldKey,
      drawer: menuLateral(),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 25),
          child: Column(
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  IconButton(
                    icon: Icon(Icons.menu, size: 30, color: branco),
                    onPressed: () => _scaffoldKey.currentState?.openDrawer(),
                  ),
                  CircleAvatar(radius: 20, backgroundColor: azul, child: Icon(Icons.image, size: 20, color: branco)),
                ],
              ),
              const SizedBox(height: 20),
              Text("Thoth", style: TextStyle(fontSize: 32, color: azul, fontWeight: FontWeight.bold, letterSpacing: 4)),
              Text("Study Helper - Pomodoro", style: TextStyle(fontSize: 14, color: branco, letterSpacing: 1.2)),
              const SizedBox(height: 30),

              // Card última tarefa
              if (ultimaTarefa != null) ...[
                Container(
                  padding: const EdgeInsets.all(15),
                  decoration: BoxDecoration(border: Border.all(color: azul), borderRadius: BorderRadius.circular(15)),
                  child: Column(
                    children: [
                      Text("Último: ${ultimaTarefa!.nome.isEmpty ? "Tarefa Sem Nome" : ultimaTarefa!.nome}", style: TextStyle(color: branco)),
                      const SizedBox(height: 10),
                      LinearProgressIndicator(value: ultimaTarefa!.progressoSalvo, color: azul, backgroundColor: branco.withOpacity(0.1)),
                      if (ultimaTarefa!.progressoSalvo < 1.0)
                        TextButton.icon(
                          onPressed: () => iniciarTarefa(ultimaTarefa!, retomar: true),
                          icon: Icon(Icons.play_arrow, color: azul),
                          label: Text("PROSSEGUIR", style: TextStyle(fontWeight: FontWeight.bold, color: branco)),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
              ],

              Align(
                alignment: Alignment.centerLeft,
                child: Text("Tarefas", style: TextStyle(fontSize: 18, color: azul, fontWeight: FontWeight.bold)),
              ),
              const SizedBox(height: 10),

              // Lista de tarefas em stream do Firestore
              Expanded(
                child: StreamBuilder<List<Tarefa>>(
                  stream: _db.streamTarefas(),
                  builder: (context, snapshot) {
                    if (snapshot.connectionState == ConnectionState.waiting) {
                      return Center(child: CircularProgressIndicator(color: azul));
                    }
                    final lista = snapshot.data ?? [];
                    if (lista.isEmpty) {
                      return Center(
                        child: Text(
                          "Nenhuma tarefa criada",
                          style: TextStyle(color: branco.withOpacity(0.5), fontSize: 20, fontWeight: FontWeight.w300),
                        ),
                      );
                    }
                    return ListView.builder(
                      itemCount: lista.length,
                      itemBuilder: (context, i) => Container(
                        margin: const EdgeInsets.only(bottom: 12),
                        decoration: BoxDecoration(
                          border: Border.all(color: branco.withOpacity(0.2)),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: ListTile(
                          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                          title: Text(
                            lista[i].nome.isEmpty ? "Nova Tarefa" : lista[i].nome,
                            style: TextStyle(fontWeight: FontWeight.bold, color: branco, fontSize: 18),
                          ),
                          subtitle: Padding(
                            padding: const EdgeInsets.only(top: 8),
                            child: Text(
                              "Estudo: ${lista[i].estudo ~/ 60}m | Descanso: ${lista[i].descanso ~/ 60}m\nCiclos: ${lista[i].ciclos}",
                              style: TextStyle(color: azul, height: 1.4),
                            ),
                          ),
                          trailing: Icon(Icons.play_circle_fill, color: azul, size: 40),
                          onTap: () => iniciarTarefa(lista[i]),
                        ),
                      ),
                    );
                  },
                ),
              ),

              Padding(
                padding: const EdgeInsets.only(bottom: 20, top: 10),
                child: ElevatedButton(
                  onPressed: () => setState(() => estadoApp = 3),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: azul,
                    foregroundColor: branco,
                    minimumSize: const Size(double.infinity, 55),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  child: const Text("GERENCIAR TAREFAS", style: TextStyle(fontWeight: FontWeight.bold)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ---------------- TELA GERENCIAR ----------------

  Widget telaGerenciar() {
    return Scaffold(
      appBar: AppBar(
        title: Text("Gerenciar Tarefas", style: TextStyle(color: branco)),
        backgroundColor: preto,
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: branco),
          onPressed: () => setState(() => estadoApp = 0),
        ),
        bottom: PreferredSize(preferredSize: const Size.fromHeight(1), child: Divider(color: azul, height: 1)),
      ),
      floatingActionButton: FloatingActionButton(
        backgroundColor: azul,
        child: Icon(Icons.add, color: branco),
        onPressed: () => _abrirEditor(),
      ),
      body: StreamBuilder<List<Tarefa>>(
        stream: _db.streamTarefas(),
        builder: (context, snapshot) {
          final lista = snapshot.data ?? [];
          return ListView.builder(
            itemCount: lista.length,
            itemBuilder: (context, i) => Container(
              decoration: BoxDecoration(border: Border.all(color: branco.withOpacity(0.1))),
              child: ListTile(
                title: Text(
                  lista[i].nome.isEmpty ? "Sem nome" : lista[i].nome,
                  style: TextStyle(color: branco, fontWeight: FontWeight.bold),
                ),
                subtitle: Text(
                  "${lista[i].estudo ~/ 60}m estudo • ${lista[i].descanso ~/ 60}m descanso • ${lista[i].ciclos} ciclos",
                  style: TextStyle(color: azul, fontSize: 13),
                ),
                trailing: IconButton(
                  icon: Icon(Icons.delete, color: branco),
                  onPressed: () => removerTarefa(lista[i].id),
                ),
                onTap: () => _abrirEditor(tarefa: lista[i]),
              ),
            ),
          );
        },
      ),
    );
  }

  void _abrirEditor({Tarefa? tarefa}) {
    Tarefa temp = tarefa != null
        ? Tarefa(
            id: tarefa.id,
            nome: tarefa.nome,
            estudo: tarefa.estudo,
            descanso: tarefa.descanso,
            ciclos: tarefa.ciclos,
            criadaEm: tarefa.criadaEm,
          )
        : Tarefa(id: DateTime.now().millisecondsSinceEpoch.toString(), criadaEm: DateTime.now());

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: preto,
      shape: Border(top: BorderSide(color: azul, width: 2)),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setMState) => Padding(
          padding: EdgeInsets.only(
              bottom: MediaQuery.of(ctx).viewInsets.bottom, left: 25, right: 25, top: 25),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                style: TextStyle(color: branco),
                decoration: InputDecoration(
                  labelText: "Nome da Tarefa",
                  hintText: "Ex: Estudar Matemática",
                  hintStyle: TextStyle(color: branco.withOpacity(0.3)),
                  labelStyle: TextStyle(color: azul),
                  enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: branco)),
                ),
                onChanged: (v) => temp.nome = v,
                controller: TextEditingController(text: temp.nome),
              ),
              const SizedBox(height: 25),
              Text("${temp.estudo ~/ 60} min Foco", style: TextStyle(color: branco)),
              Slider(
                value: temp.estudo.toDouble(),
                min: 60, max: 7200,
                activeColor: azul,
                inactiveColor: branco.withOpacity(0.2),
                onChanged: (v) => setMState(() => temp.estudo = (v / 60).round() * 60),
              ),
              Text("${temp.descanso ~/ 60} min Descanso", style: TextStyle(color: branco)),
              Slider(
                value: temp.descanso.toDouble(),
                min: 60, max: 1200,
                activeColor: azul,
                inactiveColor: branco.withOpacity(0.2),
                onChanged: (v) => setMState(() => temp.descanso = (v / 60).round() * 60),
              ),
              Text("${temp.ciclos} Ciclos", style: TextStyle(color: branco)),
              Slider(
                value: temp.ciclos.toDouble(),
                min: 1, max: 10,
                activeColor: azul,
                inactiveColor: branco.withOpacity(0.2),
                onChanged: (v) => setMState(() => temp.ciclos = v.toInt()),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 10),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    _botaoConfig("G", 1800, 600, 3, setMState, temp),
                    _botaoConfig("A", 2700, 900, 2, setMState, temp),
                    _botaoConfig("M", 5400, 1200, 4, setMState, temp),
                    _botaoConfig("P", 3600, 300, 6, setMState, temp),
                  ],
                ),
              ),
              ElevatedButton(
                onPressed: () async {
                  await _db.guardarTarefa(temp);
                  if (ctx.mounted) Navigator.pop(ctx);
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: azul,
                  foregroundColor: branco,
                  minimumSize: const Size(double.infinity, 50),
                ),
                child: const Text("GUARDAR"),
              ),
              const SizedBox(height: 30),
            ],
          ),
        ),
      ),
    );
  }

  Widget _botaoConfig(String letra, int foco, int descanso, int ciclos, StateSetter setMState, Tarefa temp) {
    return InkWell(
      onTap: () => setMState(() {
        temp.estudo = foco;
        temp.descanso = descanso;
        temp.ciclos = ciclos;
      }),
      child: Container(
        width: 45, height: 45,
        decoration: BoxDecoration(border: Border.all(color: azul, width: 2), borderRadius: BorderRadius.circular(8)),
        alignment: Alignment.center,
        child: Text(letra, style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: branco)),
      ),
    );
  }

  // ---------------- TELA CRONOMETRO ----------------

  Widget telaCronometro() {
    return Scaffold(
      body: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(tarefaAtual!.nome.isEmpty ? "Sem nome" : tarefaAtual!.nome,
              style: TextStyle(color: azul, letterSpacing: 2)),
          Text(estaNoDescanso ? "DESCANSO" : "FOCO",
              style: TextStyle(fontSize: 32, color: branco, fontWeight: FontWeight.bold)),
          const SizedBox(height: 40),
          Center(
            child: Stack(
              alignment: Alignment.center,
              children: [
                SizedBox(
                  width: 250, height: 250,
                  child: CircularProgressIndicator(
                    value: 1 - (segundosRestantes / (estaNoDescanso ? tarefaAtual!.descanso : tarefaAtual!.estudo)),
                    strokeWidth: 8, color: azul,
                    backgroundColor: branco.withOpacity(0.1),
                  ),
                ),
                Text(formatar(segundosRestantes),
                    style: TextStyle(fontSize: 55, fontWeight: FontWeight.w100, color: branco)),
              ],
            ),
          ),
          const SizedBox(height: 30),
          Text("Ciclo $cicloAtual / ${tarefaAtual!.ciclos}",
              style: TextStyle(color: azul, fontSize: 18)),
          const SizedBox(height: 50),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              IconButton(
                icon: Icon(pausado ? Icons.play_arrow : Icons.pause, size: 45, color: branco),
                onPressed: () => setState(() => pausado = !pausado),
              ),
              IconButton(
                icon: Icon(Icons.stop, size: 45, color: azul),
                onPressed: reset,
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ---------------- TELA FIM ----------------

  Widget telaFim() {
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.check_circle_outline, size: 100, color: azul),
            const SizedBox(height: 20),
            Text("CONCLUÍDO",
                style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: branco, letterSpacing: 3)),
            const SizedBox(height: 40),
            ElevatedButton(
              onPressed: reset,
              style: ElevatedButton.styleFrom(backgroundColor: branco, foregroundColor: preto),
              child: const Text("VOLTAR"),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── TELAS AUXILIARES (mantidas do original) ───────────────────────────────

class TelaPerfil extends StatefulWidget {
  final PerfilUsuario perfil;
  const TelaPerfil({super.key, required this.perfil});

  @override
  State<TelaPerfil> createState() => _TelaPerfilState();
}

class _TelaPerfilState extends State<TelaPerfil> {
  late TextEditingController _nomeCtrl;
  late TextEditingController _cognomeCtrl;
  late TextEditingController _descCtrl;
  late TextEditingController _motivosCtrl;

  @override
  void initState() {
    super.initState();
    _nomeCtrl = TextEditingController(text: widget.perfil.nome);
    _cognomeCtrl = TextEditingController(text: widget.perfil.cognome);
    _descCtrl = TextEditingController(text: widget.perfil.descricao);
    _motivosCtrl = TextEditingController(text: widget.perfil.motivos);
  }

  @override
  Widget build(BuildContext context) {
    const Color azul = Color(0xFF1D81C7);
    return Scaffold(
      appBar: AppBar(
        title: const Text("Editar Perfil"),
        backgroundColor: Colors.black,
        actions: [
          IconButton(
            icon: const Icon(Icons.check, color: azul),
            onPressed: () {
              Navigator.pop(context, PerfilUsuario(
                nome: _nomeCtrl.text,
                cognome: _cognomeCtrl.text,
                descricao: _descCtrl.text,
                motivos: _motivosCtrl.text,
              ));
            },
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(25),
        child: Column(
          children: [
            Center(
              child: Stack(
                children: [
                  const CircleAvatar(radius: 60, backgroundColor: azul, child: Icon(Icons.person, size: 70, color: Colors.white)),
                  Positioned(
                    bottom: 0, right: 0,
                    child: CircleAvatar(radius: 18, backgroundColor: Colors.white, child: Icon(Icons.camera_alt, size: 18, color: azul)),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 30),
            _buildField("Nome", _nomeCtrl, "Insira o seu nome..."),
            _buildField("Cognome", _cognomeCtrl, "Ex: Mestre do Foco"),
            _buildField("Descrição", _descCtrl, "Escreva algo sobre si...", maxLines: 3),
            _buildField("Motivos para usar a App", _motivosCtrl, "Ex: Melhorar a gestão de tempo...", maxLines: 3),
          ],
        ),
      ),
    );
  }

  Widget _buildField(String label, TextEditingController ctrl, String hint, {int maxLines = 1}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: TextField(
        controller: ctrl,
        maxLines: maxLines,
        style: const TextStyle(color: Colors.white),
        decoration: InputDecoration(
          labelText: label,
          hintText: hint,
          hintStyle: TextStyle(color: Colors.white.withOpacity(0.3)),
          labelStyle: const TextStyle(color: Color(0xFF1D81C7)),
          enabledBorder: const UnderlineInputBorder(borderSide: BorderSide(color: Colors.white24)),
          focusedBorder: const UnderlineInputBorder(borderSide: BorderSide(color: Color(0xFF1D81C7))),
        ),
      ),
    );
  }
}

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

  void _mostrarErro(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: Colors.redAccent),
    );
  }

  void _adicionarItem() {
    if (_todoCtrl.text.isEmpty) return;
    String rawHora = _horaCtrl.text.trim();
    if (rawHora.isNotEmpty) {
      final partes = rawHora.split(':');
      if (partes.length != 2) { _mostrarErro("Hora inválida! Use hh:mm"); return; }
      int? h = int.tryParse(partes[0]);
      int? m = int.tryParse(partes[1]);
      if (h == null || m == null || h < 0 || h > 23 || m < 0 || m > 59) {
        _mostrarErro("Hora fora dos limites (00-23 : 00-59)"); return;
      }
    }
    String rawData = _dataCtrl.text.trim();
    if (rawData.isNotEmpty) {
      final partes = rawData.split('/');
      if (partes.length != 2) { _mostrarErro("Data inválida! Use dd/mm"); return; }
      int? d = int.tryParse(partes[0]);
      int? mes = int.tryParse(partes[1]);
      if (mes == null || d == null || mes < 1 || mes > 12) { _mostrarErro("Mês inválido (1-12)"); return; }
      int maxDias = 31;
      if (mes == 2) maxDias = 28;
      else if ([4, 6, 9, 11].contains(mes)) maxDias = 30;
      if (d < 1 || d > maxDias) { _mostrarErro("Dia inválido para este mês (Máx: $maxDias)"); return; }
    }
    String infoHora = _horaCtrl.text.isEmpty ? "--:--" : _horaCtrl.text;
    String infoData = _dataCtrl.text.isEmpty ? "--/--" : _dataCtrl.text;
    setState(() {
      widget.lista.add(ItemTodo(texto: _todoCtrl.text, dataHora: "$infoHora | $infoData"));
      _todoCtrl.clear(); _horaCtrl.clear(); _dataCtrl.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    const Color azul = Color(0xFF1D81C7);
    return Scaffold(
      appBar: AppBar(title: const Text("To-do List"), backgroundColor: Colors.black),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              children: [
                TextField(
                  controller: _todoCtrl,
                  style: const TextStyle(color: Colors.white),
                  decoration: InputDecoration(
                    hintText: "Nota / Possível Tarefa",
                    hintStyle: TextStyle(color: Colors.white.withOpacity(0.3)),
                    enabledBorder: const UnderlineInputBorder(borderSide: BorderSide(color: Colors.white24)),
                  ),
                ),
                const SizedBox(height: 15),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _horaCtrl, keyboardType: TextInputType.datetime,
                        style: const TextStyle(color: Colors.white),
                        decoration: InputDecoration(hintText: "hh:mm", hintStyle: TextStyle(color: Colors.white.withOpacity(0.3)), enabledBorder: const UnderlineInputBorder(borderSide: BorderSide(color: Colors.white24))),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: TextField(
                        controller: _dataCtrl, keyboardType: TextInputType.datetime,
                        style: const TextStyle(color: Colors.white),
                        decoration: InputDecoration(hintText: "dd/mm", hintStyle: TextStyle(color: Colors.white.withOpacity(0.3)), enabledBorder: const UnderlineInputBorder(borderSide: BorderSide(color: Colors.white24))),
                      ),
                    ),
                    const SizedBox(width: 15),
                    IconButton(icon: const Icon(Icons.add_task, color: azul, size: 32), onPressed: _adicionarItem),
                  ],
                ),
              ],
            ),
          ),
          Expanded(
            child: ListView.builder(
              itemCount: widget.lista.length,
              itemBuilder: (context, i) {
                final item = widget.lista[i];
                return ListTile(
                  leading: IconButton(
                    icon: Icon(item.concluido ? Icons.check_circle : Icons.radio_button_unchecked,
                        color: item.concluido ? Colors.green : Colors.white24),
                    onPressed: () => setState(() => item.concluido = !item.concluido),
                  ),
                  title: Text(item.texto, style: TextStyle(color: Colors.white, decoration: item.concluido ? TextDecoration.lineThrough : null)),
                  subtitle: Text(item.dataHora, style: const TextStyle(color: azul, fontSize: 11)),
                  trailing: IconButton(icon: const Icon(Icons.close, color: Colors.redAccent, size: 20), onPressed: () => setState(() => widget.lista.removeAt(i))),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class TelaPomodoroInfo extends StatelessWidget {
  const TelaPomodoroInfo({super.key});

  @override
  Widget build(BuildContext context) {
    const Color azulThoth = Color(0xFF1D81C7);
    const double tamanhoTexto = 17.0;
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(title: const Text("O que é o Pomodoro"), backgroundColor: Colors.black, elevation: 0),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(25),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text("Um temporizador estilo Pomodoro é uma técnica de gestão de tempo que divide o estudo ou trabalho em blocos curtos de foco intenso, intercalados com descansos.", style: TextStyle(fontSize: tamanhoTexto, height: 1.5, color: Colors.white)),
            const SizedBox(height: 30),
            const Text("Funciona assim:", style: TextStyle(fontSize: tamanhoTexto, fontWeight: FontWeight.bold, color: azulThoth)),
            const SizedBox(height: 10),
            Padding(
              padding: const EdgeInsets.only(left: 10),
              child: Column(
                children: [
                  ListTile(leading: const Icon(Icons.circle, size: 8, color: azulThoth), title: const Text("25 minutos de estudo/trabalho (1 Pomodoro / Ciclo)", style: TextStyle(fontSize: tamanhoTexto, color: Colors.white)), dense: true),
                  ListTile(leading: const Icon(Icons.circle, size: 8, color: azulThoth), title: const Text("5 minutos de descanso", style: TextStyle(fontSize: tamanhoTexto, color: Colors.white)), dense: true),
                  ListTile(leading: const Icon(Icons.circle, size: 8, color: azulThoth), title: const Text("Repetir quantos Pomodoros / Ciclos forem necessários para a sessão", style: TextStyle(fontSize: tamanhoTexto, color: Colors.white)), dense: true),
                ],
              ),
            ),
            const SizedBox(height: 30),
            RichText(
              text: const TextSpan(
                style: TextStyle(fontSize: tamanhoTexto, height: 1.5, color: Colors.white),
                children: [
                  TextSpan(text: "Objetivo: ", style: TextStyle(fontWeight: FontWeight.bold, color: azulThoth)),
                  TextSpan(text: "manter a concentração, evitar fadiga mental e aumentar a produtividade através de intervalos regulares."),
                ],
              ),
            ),
            const SizedBox(height: 15),
            const Text("É simples: usas um temporizador (telemóvel, app ou relógio) para controlar esses ciclos.", style: TextStyle(fontSize: tamanhoTexto, color: Colors.white, height: 1.5)),
            const SizedBox(height: 40),
            const Divider(color: Colors.white24),
          ],
        ),
      ),
    );
  }
}
