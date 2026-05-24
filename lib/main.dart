import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:image_picker/image_picker.dart';
import 'package:share_plus/share_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'dart:io' show File, Directory, Platform;

import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest_all.dart' as tz;
import 'package:timezone/timezone.dart' as tz;
import 'package:window_manager/window_manager.dart';
import 'package:audioplayers/audioplayers.dart';

import 'firebase_options.dart';

// ─── Reacções disponíveis entre amigos ──────────────────────────────────────
const List<String> _reacoes = ['🔥', '💪', '👏', '⚡', '🎯', '🏆'];

// ─── Helpers de plataforma ───────────────────────────────────────────────────
bool get _isDesktop =>
    !kIsWeb && (Platform.isWindows || Platform.isMacOS || Platform.isLinux);

// ─── Notificações globais ────────────────────────────────────────────────────
final FlutterLocalNotificationsPlugin _notifPlugin =
    FlutterLocalNotificationsPlugin();

final List<String> _mensagensNotif = [
  'Já estudaste hoje? Não? Tá bem... o teu futuro self que se desenrasque.',
  'O teu rival já estudou 2h hoje. Tu não. Parabéns.',
  'Lembras-te dos teus sonhos? O THOTH também. Vai estudar.',
  'Hoje não estudaste nada. Impressionante, mas não da boa maneira.',
  'Notificação número ${DateTime.now().day} sem estudares. Recorde pessoal?',
  'Thoth, deus egípcio do saber, chora ao ver o teu progresso.',
  'Sugestão: em vez de ignorar esta notificação, abre o app. Só uma vez.',
  'A tua mãe perguntou como vai o estudo. Não respondas.',
  'Esta notificação é mais produtiva do que tu hoje. Triste.',
  'Foste a algum lado menos estudar. Parabéns pela criatividade.',
  'Os neurónios estão à espera. Não os faças esperar mais.',
  'Estudar 20 minutos > não estudar nada. Matemática difícil, eu sei.',
  'O teu streak vai morrer hoje. Mas tu continuas aqui. A ler notificações.',
  'Esta é a tua consciência. Abre o THOTH. Por favor.',
  'Um PhD começa com uma sessão de estudo. Esta. Agora.',
  'Fact: ninguém foi a lado nenhum sem estudar. Mas ok, continua a scrollar.',
  'Já passaste 5 minutos a ler isto. Podias ter estudado.',
  'O THOTH não te julga. Mas eu sim. Vai estudar.',
  'Duolingo tem uma coruja. O THOTH tem uma notificação. Ambos te odeiam.',
  'Hoje ainda dá tempo. Amanhã tu dizes o mesmo. Entra no ciclo.',
  'Uma sessão de 25 minutos. É só isso. Consegues fazer isso num intervalo.',
  'O teu cérebro quer aprender. O teu telemóvel não deixa. Mostra quem manda.',
  'Sem pressão, mas... os teus objetivos não vão alcançar-se sozinhos. 😇',
  'Boa notícia: ainda há tempo. Má notícia: estás a usá-lo mal.',
  'Estudo pendente: SIM. Desculpas prontas: também SIM. Abre o app.',
];

Future<void> _inicializarNotificacoes() async {
  tz.initializeTimeZones();
  if (_isDesktop && !Platform.isMacOS) return;

  const android = AndroidInitializationSettings('@mipmap/ic_launcher');
  const ios = DarwinInitializationSettings(
    requestAlertPermission: true,
    requestBadgePermission: true,
    requestSoundPermission: true,
  );
  const macos = DarwinInitializationSettings(
    requestAlertPermission: true,
    requestBadgePermission: true,
    requestSoundPermission: true,
  );
  await _notifPlugin.initialize(
    const InitializationSettings(android: android, iOS: ios, macOS: macos),
  );

  if (!kIsWeb && Platform.isAndroid) {
    final androidPlugin = _notifPlugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>();
    await androidPlugin?.requestNotificationsPermission();
    await androidPlugin?.requestExactAlarmsPermission();
  }
}

Future<void> _agendarNotificacaoDiaria() async {
  if (_isDesktop && !Platform.isMacOS) return;
  await _notifPlugin.cancelAll();

  final rand = math.Random();
  final msg = _mensagensNotif[rand.nextInt(_mensagensNotif.length)];

  final agora = tz.TZDateTime.now(tz.local);
  var agendado = tz.TZDateTime(
      tz.local, agora.year, agora.month, agora.day, 20, 0);
  if (agendado.isBefore(agora)) {
    agendado = agendado.add(const Duration(days: 1));
  }

  const androidDetails = AndroidNotificationDetails(
    'thoth_daily',
    'Lembrete Diário',
    channelDescription: 'Lembrete passivo-agressivo para estudar',
    importance: Importance.max,
    priority: Priority.max,
    ticker: 'Vai estudar.',
    playSound: true,
    enableVibration: true,
    styleInformation: BigTextStyleInformation(''),
  );
  const iosDetails = DarwinNotificationDetails(
    presentAlert: true,
    presentBadge: true,
    presentSound: true,
  );

  await _notifPlugin.zonedSchedule(
    0,
    'Thoth está à tua espera 📚',
    msg,
    agendado,
    const NotificationDetails(
        android: androidDetails, iOS: iosDetails, macOS: iosDetails),
    androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
    uiLocalNotificationDateInterpretation:
        UILocalNotificationDateInterpretation.absoluteTime,
    matchDateTimeComponents: DateTimeComponents.time,
  );
}

Future<void> _cancelarNotifSeEstudouHoje(String uid) async {
  try {
    final hoje = DateTime.now();
    final inicioDia = DateTime(hoje.year, hoje.month, hoje.day);
    final snap = await FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .collection('sessoes')
        .where('dataConclusao',
            isGreaterThanOrEqualTo: inicioDia.toIso8601String())
        .limit(1)
        .get();
    if (snap.docs.isNotEmpty) {
      await _notifPlugin.cancel(0);
    }
  } catch (_) {}
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  await _inicializarNotificacoes();

  if (!_isDesktop && !kIsWeb) {
    await SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
    ]);
  }

  if (_isDesktop) {
    await windowManager.ensureInitialized();
    const windowOptions = WindowOptions(
      size: Size(1024, 720),
      minimumSize: Size(800, 600),
      center: true,
      title: 'THOTH – Study Helper',
      backgroundColor: Colors.transparent,
      skipTaskbar: false,
      titleBarStyle: TitleBarStyle.normal,
    );
    await windowManager.waitUntilReadyToShow(windowOptions, () async {
      await windowManager.show();
      await windowManager.focus();
    });
  }

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

  Map<String, dynamic> toJson() => {
        'id': id,
        'nome': nome,
        'estudo': estudo,
        'descanso': descanso,
        'ciclos': ciclos,
        'progressoSalvo': progressoSalvo,
        'cicloSalvo': cicloSalvo,
        'estavaNoDescanso': estavaNoDescanso,
        'segundosSalvos': segundosSalvos,
      };

  factory Tarefa.fromJson(Map<String, dynamic> j) => Tarefa(
        id: j['id'] as String,
        nome: j['nome'] as String? ?? '',
        estudo: j['estudo'] as int? ?? 1500,
        descanso: j['descanso'] as int? ?? 300,
        ciclos: j['ciclos'] as int? ?? 4,
        progressoSalvo:
            (j['progressoSalvo'] as num?)?.toDouble() ?? 0.0,
        cicloSalvo: j['cicloSalvo'] as int? ?? 1,
        estavaNoDescanso: j['estavaNoDescanso'] as bool? ?? false,
        segundosSalvos: j['segundosSalvos'] as int? ?? 1500,
      );

  int get tempoTotalSegundos =>
      ciclos * estudo + (ciclos - 1) * descanso;
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

  Map<String, dynamic> toJson() => {
        'id': id,
        'texto': texto,
        'dataHora': dataHora,
        'concluido': concluido,
      };

  factory ItemTodo.fromJson(Map<String, dynamic> j) => ItemTodo(
        id: j['id'] as String,
        texto: j['texto'] as String? ?? '',
        dataHora: j['dataHora'] as String? ?? '',
        concluido: j['concluido'] as bool? ?? false,
      );
}

class PerfilUsuario {
  String nome;
  String nomedeutilizador;
  String descricao;
  String motivos;
  String citacao;
  String fotoUrl;

  PerfilUsuario({
    this.nome = '',
    this.nomedeutilizador = '',
    this.descricao = '',
    this.motivos = '',
    this.citacao = '',
    this.fotoUrl = '',
  });

  Map<String, dynamic> toJson() => {
        'nome': nome,
        'nomedeutilizador': nomedeutilizador,
        'descricao': descricao,
        'motivos': motivos,
        'citacao': citacao,
        'fotoUrl': fotoUrl,
      };

  factory PerfilUsuario.fromJson(Map<String, dynamic> j) => PerfilUsuario(
        nome: j['nome'] as String? ?? '',
        nomedeutilizador: j['nomedeutilizador'] as String? ?? '',
        descricao: j['descricao'] as String? ?? '',
        motivos: j['motivos'] as String? ?? '',
        citacao: j['citacao'] as String? ?? '',
        fotoUrl: j['fotoUrl'] as String? ?? '',
      );
}

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

  Map<String, dynamic> toJson() => {
        'tarefaNome': tarefaNome,
        'dataConclusao': dataConclusao.toIso8601String(),
        'ciclosConcluidos': ciclosConcluidos,
        'tempoFocoSegundos': tempoFocoSegundos,
      };

  factory SessaoConcluida.fromJson(Map<String, dynamic> j) =>
      SessaoConcluida(
        tarefaNome: j['tarefaNome'] as String? ?? '',
        dataConclusao:
            DateTime.parse(j['dataConclusao'] as String),
        ciclosConcluidos: j['ciclosConcluidos'] as int? ?? 0,
        tempoFocoSegundos: j['tempoFocoSegundos'] as int? ?? 0,
      );
}

// =============================================================================
// STREAK
// =============================================================================

class StreakInfo {
  final int dias;
  final DateTime? ultimoEstudo;
  final bool frozenHoje;

  const StreakInfo(
      {required this.dias,
      this.ultimoEstudo,
      this.frozenHoje = false});

  bool get acendeuHoje {
    if (ultimoEstudo == null) return false;
    final agora = DateTime.now();
    final ult = ultimoEstudo!;
    return ult.year == agora.year &&
        ult.month == agora.month &&
        ult.day == agora.day;
  }

  static StreakInfo calcular(List<SessaoConcluida> sessoes) {
    if (sessoes.isEmpty) return const StreakInfo(dias: 0);
    final dias = <String>{};
    for (final s in sessoes) {
      final d = s.dataConclusao;
      dias.add('${d.year}-${d.month}-${d.day}');
    }
    final sorted = dias.toList()..sort();
    int streak = 1;
    final today = DateTime.now();
    final todayStr = '${today.year}-${today.month}-${today.day}';
    final yesterday = today.subtract(const Duration(days: 1));
    final yesterdayStr =
        '${yesterday.year}-${yesterday.month}-${yesterday.day}';
    if (!dias.contains(todayStr) && !dias.contains(yesterdayStr)) {
      return const StreakInfo(dias: 0);
    }
    for (int i = sorted.length - 1; i > 0; i--) {
      final curr = DateTime.parse(sorted[i]);
      final prev = DateTime.parse(sorted[i - 1]);
      if (curr.difference(prev).inDays == 1) {
        streak++;
      } else {
        break;
      }
    }
    final lastSession = sessoes.reduce((a, b) =>
        a.dataConclusao.isAfter(b.dataConclusao) ? a : b);
    return StreakInfo(
        dias: streak, ultimoEstudo: lastSession.dataConclusao);
  }

  static StreakInfo calcularComFreeze(
      List<SessaoConcluida> sessoes, List<String> freezeDias) {
    if (sessoes.isEmpty) return const StreakInfo(dias: 0);
    final diasEstudo = <String>{};
    for (final s in sessoes) {
      final d = s.dataConclusao;
      diasEstudo.add('${d.year}-${d.month}-${d.day}');
    }
    final diasActivos = {...diasEstudo, ...freezeDias};
    final sorted = diasActivos.toList()..sort();
    int streak = 1;
    final today = DateTime.now();
    final todayStr = '${today.year}-${today.month}-${today.day}';
    final yesterday = today.subtract(const Duration(days: 1));
    final yesterdayStr =
        '${yesterday.year}-${yesterday.month}-${yesterday.day}';
    if (!diasActivos.contains(todayStr) &&
        !diasActivos.contains(yesterdayStr)) {
      return const StreakInfo(dias: 0);
    }
    for (int i = sorted.length - 1; i > 0; i--) {
      final curr = DateTime.parse(sorted[i]);
      final prev = DateTime.parse(sorted[i - 1]);
      if (curr.difference(prev).inDays == 1) {
        streak++;
      } else {
        break;
      }
    }
    final frozenHoje = !diasEstudo.contains(todayStr) &&
        diasActivos.contains(todayStr);
    final lastSession = sessoes.reduce((a, b) =>
        a.dataConclusao.isAfter(b.dataConclusao) ? a : b);
    return StreakInfo(
        dias: streak,
        ultimoEstudo: lastSession.dataConclusao,
        frozenHoje: frozenHoje);
  }

  static const List<Map<String, dynamic>> conquistas = [
    {'dias': 3, 'label': '3 dias', 'icon': '🔥'},
    {'dias': 7, 'label': '1 semana', 'icon': '⚡'},
    {'dias': 10, 'label': '10 dias', 'icon': '💪'},
    {'dias': 30, 'label': '30 dias', 'icon': '🏅'},
    {'dias': 50, 'label': '50 dias', 'icon': '🥈'},
    {'dias': 75, 'label': '75 dias', 'icon': '🥇'},
    {'dias': 100, 'label': '100 dias', 'icon': '💎'},
    {'dias': 180, 'label': '6 meses', 'icon': '🌟'},
    {'dias': 365, 'label': '1 ano', 'icon': '👑'},
  ];
}

// =============================================================================
// TEMA GLOBAL
// =============================================================================

final ValueNotifier<bool> temaEscuro = ValueNotifier<bool>(true);

Color _tc() =>
    temaEscuro.value ? Colors.white : Colors.black87;
Color _tc54() =>
    temaEscuro.value ? Colors.white54 : Colors.black45;
Color _tc38() =>
    temaEscuro.value ? Colors.white38 : Colors.black38;
Color _tc24() =>
    temaEscuro.value ? Colors.white24 : Colors.black12;
Color _tc12() =>
    temaEscuro.value ? Colors.white12 : Colors.black12;
Color _bgc() =>
    temaEscuro.value ? Colors.black : Colors.white;

// =============================================================================
// APP PRINCIPAL
// =============================================================================

class ThothApp extends StatelessWidget {
  const ThothApp({super.key});

  static ThemeData _buildTheme(bool escuro) {
    const azul = Color(0xFF1D81C7);
    final bg = escuro ? Colors.black : Colors.white;
    final fg = escuro ? Colors.white : Colors.black87;

    return (escuro ? ThemeData.dark() : ThemeData.light()).copyWith(
      scaffoldBackgroundColor: bg,
      primaryColor: azul,
      cardColor: bg,
      dividerColor: escuro ? Colors.white24 : Colors.black12,
      colorScheme: escuro
          ? const ColorScheme.dark(
              primary: azul, surface: Colors.black)
          : ColorScheme.light(
              primary: azul,
              surface: Colors.white,
              onSurface: Colors.black87),
      appBarTheme: AppBarTheme(
        backgroundColor: bg,
        foregroundColor: fg,
        elevation: 0,
        centerTitle: false,
        titleTextStyle: TextStyle(
            color: fg,
            fontSize: 20,
            fontWeight: FontWeight.bold),
      ),
      iconTheme: IconThemeData(color: fg),
      textTheme: escuro
          ? ThemeData.dark().textTheme
          : ThemeData.light().textTheme.apply(
              bodyColor: Colors.black87,
              displayColor: Colors.black87),
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
        builder: (context, child) {
          if (_isDesktop && child != null) {
            return Center(
              child: ConstrainedBox(
                constraints:
                    const BoxConstraints(maxWidth: 480),
                child: child,
              ),
            );
          }
          return child ?? const SizedBox.shrink();
        },
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
            body: Center(child: CircularProgressIndicator()),
          );
        }
        if (snapshot.hasData) return const PomodoroApp();
        return const LoginPage();
      },
    );
  }
}

// =============================================================================
// LOGIN
// =============================================================================

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  bool _loading = false;

  Future<void> signInWithGoogle() async {
    setState(() => _loading = true);
    try {
      final GoogleSignIn googleSignIn = GoogleSignIn(
        serverClientId:
            '639767112265-bupqhsgfftmn42rkcob8cvk9ntrk2nje.apps.googleusercontent.com',
      );

      final GoogleSignInAccount? googleUser =
          await googleSignIn.signIn();
      if (googleUser == null) {
        setState(() => _loading = false);
        return;
      }

      final GoogleSignInAuthentication googleAuth =
          await googleUser.authentication;

      if (googleAuth.idToken == null) {
        debugPrint(
            'ERRO: idToken é null. Verifica o SHA-1 no Firebase Console.');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text(
                'Erro de autenticação. Verifica a ligação e tenta novamente.'),
          ));
        }
        setState(() => _loading = false);
        return;
      }

      final credential = GoogleAuthProvider.credential(
        accessToken: googleAuth.accessToken,
        idToken: googleAuth.idToken,
      );

      await FirebaseAuth.instance.signInWithCredential(credential);
    } catch (e) {
      debugPrint('Erro no login: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erro ao entrar: $e')),
        );
      }
      setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    const azul = Color(0xFF1D81C7);

    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 40),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Text(
                  'T h o t h',
                  style: TextStyle(
                    fontSize: 42,
                    fontWeight: FontWeight.bold,
                    color: azul,
                    letterSpacing: 6,
                  ),
                ),
                const SizedBox(height: 6),
                const Text(
                  'S t u d y   H e l p e r',
                  style: TextStyle(
                    fontSize: 13,
                    color: Colors.white38,
                    letterSpacing: 3,
                  ),
                ),
                const SizedBox(height: 50),
                Container(height: 1, color: Colors.white12),
                const SizedBox(height: 50),
                const Text(
                  'Bem-vindo',
                  style: TextStyle(
                    fontSize: 26,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 10),
                const Text(
                  'Inicia sessão para começares a estudar',
                  style:
                      TextStyle(fontSize: 14, color: Colors.white54),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 40),
                SizedBox(
                  width: double.infinity,
                  height: 54,
                  child: ElevatedButton.icon(
                    onPressed:
                        _loading ? null : signInWithGoogle,
                    icon: _loading
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              color: Colors.white,
                              strokeWidth: 2,
                            ),
                          )
                        : const Icon(Icons.login,
                            color: Colors.white),
                    label: Text(
                      _loading ? 'A entrar...' : 'Sign In',
                      style: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                        letterSpacing: 0.5,
                      ),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: azul,
                      disabledBackgroundColor:
                          azul.withOpacity(0.6),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                      elevation: 0,
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                const Text(
                  'Ao entrar, aceitas os termos de utilização do Thoth',
                  style: TextStyle(
                      fontSize: 12, color: Colors.white24),
                  textAlign: TextAlign.center,
                ),
              ],
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

class PomodoroApp extends StatefulWidget {
  const PomodoroApp({super.key});

  @override
  State<PomodoroApp> createState() => _PomodoroAppState();
}

class _PomodoroAppState extends State<PomodoroApp>
    with WidgetsBindingObserver {
  final GlobalKey<ScaffoldState> _scaffoldKey =
      GlobalKey<ScaffoldState>();

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

  bool _aCarregarDados = true;

  // ── Firestore helpers ──────────────────────────────────────────────
  FirebaseFirestore get _db => FirebaseFirestore.instance;
  String get _uid => FirebaseAuth.instance.currentUser!.uid;
  DocumentReference get _configDoc =>
      _db.collection('users').doc(_uid).collection('config').doc('dados');
  DocumentReference get _perfilDoc =>
      _db.collection('users').doc(_uid).collection('perfil').doc('dados');
  CollectionReference get _tarefasCol =>
      _db.collection('users').doc(_uid).collection('tarefas');
  CollectionReference get _sessoesCol =>
      _db.collection('users').doc(_uid).collection('sessoes');
  CollectionReference get _todoCol =>
      _db.collection('users').doc(_uid).collection('todo');

  String? _todoBlocosGuardados;
  DateTime? _countdownAlvoGuardado;
  String? _countdownMotivoGuardado;

  int _streakFreezes = 0;
  List<String> _freezeDias = [];
  int _metaSemanalMinutos = 0;
  bool _modoDNDAtivo = false;

  DateTime? _timerReferencia;
  int? _segundosNaReferencia;

  // ── Audio ──────────────────────────────────────────────────────────
  // FIX: AudioPlayer inicializado como late para evitar erros de dispose
  late final AudioPlayer _audioPlayer;
  bool _audioDisponivel = false;

  Future<void> _guardarEstadoTimer() async {
    if (tarefaAtual == null) return;
    try {
      await _configDoc.set({
        'timerAtivo': estadoApp == EstadoApp.cronometro,
        'timerTarefaId': tarefaAtual?.id,
        'timerSegundosRestantes': segundosRestantes,
        'timerCicloAtual': cicloAtual,
        'timerEstaNoDescanso': estaNoDescanso,
        'timerPausado': pausado,
        'timerReferencia':
            (!pausado && estadoApp == EstadoApp.cronometro)
                ? DateTime.now().toIso8601String()
                : null,
      }, SetOptions(merge: true));
    } catch (e) {
      debugPrint('Erro ao guardar estado timer: $e');
    }
  }

  Future<void> _restaurarTimerSeAtivo(
      Map<String, dynamic> d) async {
    final timerAtivo = d['timerAtivo'] as bool? ?? false;
    if (!timerAtivo) return;

    final tarefaId = d['timerTarefaId'] as String?;
    if (tarefaId == null) return;

    Tarefa? t;
    try {
      t = tarefas.firstWhere((x) => x.id == tarefaId);
    } catch (_) {
      return;
    }

    var segundos =
        (d['timerSegundosRestantes'] as int?) ?? t.estudo;
    final ciclo = (d['timerCicloAtual'] as int?) ?? 1;
    final noDesc =
        (d['timerEstaNoDescanso'] as bool?) ?? false;
    final estava = (d['timerPausado'] as bool?) ?? true;
    final refStr = d['timerReferencia'] as String?;

    if (!estava && refStr != null) {
      final ref = DateTime.tryParse(refStr);
      if (ref != null) {
        final elapsed =
            DateTime.now().difference(ref).inSeconds;
        segundos = (segundos - elapsed).clamp(0, 999999);
      }
    }

    setState(() {
      tarefaAtual = t;
      ultimaTarefa = t;
      cicloAtual = ciclo;
      estaNoDescanso = noDesc;
      segundosRestantes = segundos;
      pausado = estava;
      estadoApp = EstadoApp.cronometro;
      _primeiraVez = estava;
    });

    _timer?.cancel();
    _timer =
        Timer.periodic(const Duration(seconds: 1), (_) {
      if (pausado || tarefaAtual == null) return;
      if (segundosRestantes > 1) {
        setState(() {
          segundosRestantes--;
          _salvarEstadoAtual();
        });
        if (segundosRestantes % 30 == 0) {
          _guardarEstadoTimer();
        }
      } else {
        _salvarEstadoAtual();
        _avancarFase();
      }
    });
  }

  Future<void> _carregarDados() async {
    try {
      // Config
      final configSnap = await _configDoc.get();
      if (configSnap.exists) {
        final d = configSnap.data() as Map<String, dynamic>;
        if (d['temaEscuro'] != null) {
          temaEscuro.value = d['temaEscuro'] as bool;
        }
        // FIX: leitura garantida do countdown
        final alvoStr = d['countdownAlvo'] as String?;
        if (alvoStr != null && alvoStr.isNotEmpty) {
          _countdownAlvoGuardado = DateTime.tryParse(alvoStr);
        }
        final motivoStr = d['countdownMotivo'] as String?;
        if (motivoStr != null && motivoStr.isNotEmpty) {
          _countdownMotivoGuardado = motivoStr;
        }
        _streakFreezes = d['streakFreezes'] as int? ?? 0;
        _metaSemanalMinutos =
            d['metaSemanalMinutos'] as int? ?? 0;
        _modoDNDAtivo = d['modoDNDAtivo'] as bool? ?? false;
        _freezeDias = List<String>.from(
            d['freezeDias'] as List? ?? []);
      }

      // FIX: Perfil carregado explicitamente e completo
      final perfilSnap = await _perfilDoc.get();
      if (perfilSnap.exists) {
        perfil = PerfilUsuario.fromJson(
            perfilSnap.data() as Map<String, dynamic>);
      } else {
        // Novo utilizador — criar perfil com nome do Google
        final user = FirebaseAuth.instance.currentUser;
        if (user != null) {
          perfil = PerfilUsuario(
            nome: user.displayName ?? '',
            fotoUrl: user.photoURL ?? '',
          );
          // Guardar imediatamente para não perder
          await _perfilDoc.set(perfil.toJson());
        }
      }

      // Tarefas
      final tarefasSnap =
          await _tarefasCol.orderBy('ordem').get();
      tarefas = tarefasSnap.docs
          .map((d) =>
              Tarefa.fromJson(d.data() as Map<String, dynamic>))
          .toList();

      // Última tarefa
      final configData = configSnap.exists
          ? configSnap.data() as Map<String, dynamic>
          : {};
      final ultimaId = configData['ultimaTarefaId'] as String?;
      if (ultimaId != null) {
        try {
          ultimaTarefa =
              tarefas.firstWhere((t) => t.id == ultimaId);
        } catch (_) {}
      }

      // Sessões
      final sessoesSnap = await _sessoesCol
          .orderBy('dataConclusao')
          .get();
      sessoes = sessoesSnap.docs
          .map((d) => SessaoConcluida.fromJson(
              d.data() as Map<String, dynamic>))
          .toList();

      // Todo blocos
      final todoSnap = await _todoCol.get();
      if (todoSnap.docs.isNotEmpty) {
        final m = <String, dynamic>{};
        for (final doc in todoSnap.docs) {
          m[doc.id] = doc.data();
        }
        _todoBlocosGuardados = jsonEncode(m);
      }

      if (mounted) {
        setState(() => _aCarregarDados = false);
        if (configSnap.exists) {
          await _restaurarTimerSeAtivo(
              configSnap.data() as Map<String, dynamic>);
        }
        _agendarNotificacaoDiaria();
        _migrarUsernameParaIndice();
      }
    } catch (e) {
      debugPrint('Erro ao carregar dados do Firestore: $e');
      if (mounted) setState(() => _aCarregarDados = false);
    }
  }

  Future<void> _migrarUsernameParaIndice() async {
    try {
      if (perfil.nomedeutilizador.isEmpty) return;
      final key = perfil.nomedeutilizador.toLowerCase();
      final doc =
          await _db.collection('usernames').doc(key).get();
      if (!doc.exists ||
          (doc.data()?['uid'] as String?) == _uid) {
        await _db.collection('usernames').doc(key).set({
          'uid': _uid,
          'nome': perfil.nome,
          'nomedeutilizador': perfil.nomedeutilizador,
        });
      }
    } catch (e) {
      debugPrint(
          'Erro ao migrar username para índice: $e');
    }
  }

  // FIX: _guardarTudo completamente reescrito com tratamento de erros
  Future<void> _guardarTudo() async {
    try {
      final batch = _db.batch();

      // Config — merge:true para não apagar campos do timer
      batch.set(
          _configDoc,
          {
            'temaEscuro': temaEscuro.value,
            'ultimaTarefaId': ultimaTarefa?.id,
            'countdownAlvo':
                _countdownAlvoGuardado?.toIso8601String(),
            'countdownMotivo': _countdownMotivoGuardado,
            'streakFreezes': _streakFreezes,
            'metaSemanalMinutos': _metaSemanalMinutos,
            'modoDNDAtivo': _modoDNDAtivo,
            'freezeDias': _freezeDias,
          },
          SetOptions(merge: true));

      // FIX: Perfil sem merge:true — garante escrita completa
      batch.set(_perfilDoc, perfil.toJson());

      // Tarefas
      for (int i = 0; i < tarefas.length; i++) {
        final data = tarefas[i].toJson();
        data['ordem'] = i;
        batch.set(_tarefasCol.doc(tarefas[i].id), data);
      }

      await batch.commit();
    } catch (e) {
      debugPrint('Erro no batch _guardarTudo: $e');
    }

    // FIX: Username index separado do batch para não bloquear
    if (perfil.nomedeutilizador.isNotEmpty) {
      try {
        await _db
            .collection('usernames')
            .doc(perfil.nomedeutilizador.toLowerCase())
            .set({
          'uid': _uid,
          'nome': perfil.nome,
          'nomedeutilizador': perfil.nomedeutilizador,
        });
      } catch (e) {
        debugPrint('Erro ao guardar username index: $e');
      }
    }
  }

  Future<void> _guardarSessao(SessaoConcluida s) async {
    try {
      await _sessoesCol.add(s.toJson());
    } catch (e) {
      debugPrint('Erro ao guardar sessão: $e');
    }
  }

  Future<void> _guardarTarefasImediato() async {
    if (tarefas.isEmpty) return;
    try {
      final batch = _db.batch();
      for (int i = 0; i < tarefas.length; i++) {
        final data = tarefas[i].toJson();
        data['ordem'] = i;
        batch.set(_tarefasCol.doc(tarefas[i].id), data);
      }
      await batch.commit();
    } catch (e) {
      debugPrint('Erro ao guardar tarefas imediato: $e');
    }
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    // FIX: inicializar AudioPlayer com verificação de disponibilidade
    _audioPlayer = AudioPlayer();
    _verificarAudio();

    _carregarDados();

    temaEscuro.addListener(() {
      _configDoc
          .set({'temaEscuro': temaEscuro.value},
              SetOptions(merge: true))
          .catchError((e) =>
              debugPrint('Erro ao guardar tema: $e'));
    });
  }

  // FIX: verifica se os assets de som existem
  Future<void> _verificarAudio() async {
    try {
      await rootBundle
          .load('assets/sounds/timer_fase.wav');
      _audioDisponivel = true;
    } catch (_) {
      _audioDisponivel = false;
      debugPrint(
          'Assets de som não encontrados — usando apenas haptic feedback.');
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _salvarEstadoAtual();
    _guardarTarefasImediato();
    _guardarTudo();
    _audioPlayer.dispose();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive ||
        state == AppLifecycleState.detached) {
      _salvarEstadoAtual();
      _guardarTudo();
      _guardarTarefasImediato();
      if (estadoApp == EstadoApp.cronometro && !pausado) {
        _guardarEstadoTimer();
      }
    }

    if (state == AppLifecycleState.resumed) {
      if (estadoApp == EstadoApp.cronometro && !pausado) {
        _configDoc.get().then((snap) {
          if (!snap.exists || !mounted) return;
          final d = snap.data() as Map<String, dynamic>;
          final refStr = d['timerReferencia'] as String?;
          final refSegundos =
              d['timerSegundosRestantes'] as int?;
          if (refStr != null && refSegundos != null) {
            final ref = DateTime.tryParse(refStr);
            if (ref != null) {
              final elapsed =
                  DateTime.now().difference(ref).inSeconds;
              final novosSegundos =
                  (refSegundos - elapsed).clamp(0, 999999);
              setState(
                  () => segundosRestantes = novosSegundos);
              if (novosSegundos <= 0) _avancarFase();
            }
          }
        }).catchError(
            (e) => debugPrint('Erro ao recuperar timer: $e'));
      }
    }
  }

  // =============================================================================
  // LÓGICA POMODORO
  // =============================================================================

  void iniciarTarefa(Tarefa t, {bool retomar = false}) {
    _timer?.cancel();
    setState(() {
      tarefaAtual = t;
      estadoApp = EstadoApp.cronometro;
      pausado = true;
      _primeiraVez = true;

      if (!retomar) {
        cicloAtual = 1;
        estaNoDescanso = false;
        segundosRestantes = t.estudo;
      } else {
        cicloAtual = t.cicloSalvo.clamp(1, t.ciclos);
        estaNoDescanso = t.estavaNoDescanso;
        final duracaoFase =
            estaNoDescanso ? t.descanso : t.estudo;
        segundosRestantes =
            (t.segundosSalvos > 0 &&
                    t.segundosSalvos <= duracaoFase)
                ? t.segundosSalvos
                : duracaoFase;
      }
    });

    _timer =
        Timer.periodic(const Duration(seconds: 1), (_) {
      if (pausado || tarefaAtual == null) return;
      if (segundosRestantes > 1) {
        setState(() {
          segundosRestantes--;
          _salvarEstadoAtual();
        });
        if (segundosRestantes % 30 == 0) {
          _guardarEstadoTimer();
        }
      } else {
        _salvarEstadoAtual();
        _avancarFase();
      }
    });
    _guardarEstadoTimer();
  }

  void _salvarEstadoAtual() {
    if (tarefaAtual == null) return;
    tarefaAtual!
      ..cicloSalvo = cicloAtual
      ..estavaNoDescanso = estaNoDescanso
      ..segundosSalvos = segundosRestantes
      ..progressoSalvo = _calcularProgressoGlobal();
    ultimaTarefa = tarefaAtual;

    // FIX: atualizar na lista principal também
    final idx =
        tarefas.indexWhere((t) => t.id == tarefaAtual!.id);
    if (idx >= 0) tarefas[idx] = tarefaAtual!;

    final data = tarefaAtual!.toJson();
    if (idx >= 0) data['ordem'] = idx;
    _tarefasCol.doc(tarefaAtual!.id).set(data).catchError(
        (e) => debugPrint('Erro ao guardar tarefa: $e'));
  }

  double _calcularProgressoGlobal() {
    if (tarefaAtual == null) return 0.0;
    final totalFase = estaNoDescanso
        ? tarefaAtual!.descanso
        : tarefaAtual!.estudo;
    final progressoFase = totalFase <= 0
        ? 0.0
        : (1 - (segundosRestantes / totalFase));
    final global =
        ((cicloAtual - 1) + progressoFase) /
            tarefaAtual!.ciclos;
    return global.clamp(0.0, 1.0);
  }

  // FIX: _tocarSom com haptic separado do áudio, nunca falha
  void _tocarSom({bool fim = false}) {
    // Haptic sempre, independente do som
    HapticFeedback.mediumImpact()
        .catchError((_) {});

    if (_audioDisponivel) {
      try {
        final asset = fim
            ? 'assets/sounds/timer_fim.wav'
            : 'assets/sounds/timer_fase.wav';
        _audioPlayer
            .play(AssetSource(
                asset.replaceFirst('assets/', '')))
            .catchError((e) {
          debugPrint('Erro ao tocar som: $e');
        });
      } catch (e) {
        debugPrint('Erro no audioplayer: $e');
      }
    } else {
      // Fallback sem assets
      SystemSound.play(SystemSoundType.click);
    }
  }

  void _avancarFase() {
    if (tarefaAtual == null) return;

    if (!estaNoDescanso) {
      if (cicloAtual >= tarefaAtual!.ciclos) {
        finalizar();
        return;
      }
      _tocarSom();
      setState(() {
        estaNoDescanso = true;
        segundosRestantes = tarefaAtual!.descanso;
        _salvarEstadoAtual();
      });
    } else {
      _tocarSom();
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
    setState(() {
      pausado = !pausado;
      _primeiraVez = false;
    });
    _guardarEstadoTimer();
  }

  void descartarProgresso() {
    setState(() {
      if (ultimaTarefa != null) {
        ultimaTarefa!
          ..progressoSalvo = 0.0
          ..cicloSalvo = 1
          ..estavaNoDescanso = false
          ..segundosSalvos = ultimaTarefa!.estudo;

        // FIX: atualizar na lista principal
        final idx = tarefas
            .indexWhere((t) => t.id == ultimaTarefa!.id);
        if (idx >= 0) tarefas[idx] = ultimaTarefa!;

        final t = ultimaTarefa!;
        final data = t.toJson();
        if (idx >= 0) data['ordem'] = idx;
        _tarefasCol.doc(t.id).set(data).catchError((e) =>
            debugPrint('Erro ao descartar progresso: $e'));
      }
      ultimaTarefa = null;
    });
  }

  // FIX: finalizar com atualização garantida na lista
  void finalizar() {
    _timer?.cancel();
    _tocarSom(fim: true);

    if (tarefaAtual != null) {
      final t = tarefaAtual!;
      t
        ..progressoSalvo = 1.0
        ..cicloSalvo = t.ciclos
        ..estavaNoDescanso = false
        ..segundosSalvos = 0;
      ultimaTarefa = t;

      // FIX: garantir que a lista principal tem o objeto atualizado
      final idx = tarefas.indexWhere((x) => x.id == t.id);
      if (idx >= 0) {
        tarefas[idx] = t;
      }

      // Persistir imediatamente
      final data = t.toJson();
      if (idx >= 0) data['ordem'] = idx;
      _tarefasCol.doc(t.id).set(data).catchError((e) =>
          debugPrint('Erro ao guardar tarefa concluída: $e'));

      // Registar sessão
      final novaSessao = SessaoConcluida(
        tarefaNome:
            t.nome.isEmpty ? 'Sem nome' : t.nome,
        dataConclusao: DateTime.now(),
        ciclosConcluidos: t.ciclos,
        tempoFocoSegundos: t.ciclos * t.estudo,
      );
      sessoes.add(novaSessao);
      _guardarSessao(novaSessao);

      // Notificações e freezes
      final uid =
          FirebaseAuth.instance.currentUser?.uid;
      if (uid != null) _cancelarNotifSeEstudouHoje(uid);

      final streakAtual = StreakInfo.calcularComFreeze(
          sessoes, _freezeDias);
      if (streakAtual.dias > 0 &&
          streakAtual.dias % 7 == 0) {
        _ganharStreakFreeze();
      }
    }

    setState(() => estadoApp = EstadoApp.fim);
    _guardarTudo();

    // Limpar estado do timer no Firestore
    _configDoc.set({
      'timerAtivo': false,
      'timerReferencia': null,
    }, SetOptions(merge: true)).catchError(
        (e) => debugPrint('Erro ao limpar timer: $e'));
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
    _configDoc.set({
      'timerAtivo': false,
      'timerReferencia': null,
    }, SetOptions(merge: true)).catchError(
        (e) => debugPrint('Erro ao limpar timer: $e'));
  }

  Future<void> _usarStreakFreeze() async {
    if (_streakFreezes <= 0) return;
    final today = DateTime.now();
    final todayStr =
        '${today.year}-${today.month}-${today.day}';
    if (_freezeDias.contains(todayStr)) return;
    setState(() {
      _streakFreezes--;
      _freezeDias.add(todayStr);
    });
    await _guardarTudo();
  }

  void _ganharStreakFreeze() {
    setState(() => _streakFreezes++);
    _guardarTudo();
  }

  void removerTarefa(int index) {
    final tarefaId = tarefas[index].id;
    setState(() {
      if (ultimaTarefa != null &&
          tarefas[index].id == ultimaTarefa!.id) {
        ultimaTarefa = null;
      }
      tarefas.removeAt(index);
    });
    _tarefasCol.doc(tarefaId).delete().catchError(
        (e) => debugPrint('Erro ao apagar tarefa: $e'));
    _guardarTudo();
  }

  String formatar(int s) {
    final min = (s ~/ 60).toString().padLeft(2, '0');
    final seg = (s % 60).toString().padLeft(2, '0');
    return '$min:$seg';
  }

  // =============================================================================
  // BUILD
  // =============================================================================

  @override
  Widget build(BuildContext context) {
    if (_aCarregarDados) {
      return ValueListenableBuilder<bool>(
        valueListenable: temaEscuro,
        builder: (_, escuro, __) => Scaffold(
          backgroundColor:
              escuro ? Colors.black : Colors.white,
          body: const Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text('T h o t h',
                    style: TextStyle(
                        fontSize: 32,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF1D81C7),
                        letterSpacing: 6)),
                SizedBox(height: 32),
                CircularProgressIndicator(
                    color: Color(0xFF1D81C7)),
              ],
            ),
          ),
        ),
      );
    }

    switch (estadoApp) {
      case EstadoApp.inicio:
        return _TelaInicial(
          state: this,
          countdownAlvoInicial: _countdownAlvoGuardado,
          countdownMotivoInicial: _countdownMotivoGuardado,
          todoBlocosJson: _todoBlocosGuardados,
        );
      case EstadoApp.cronometro:
        return _TelaCronometro(state: this);
      case EstadoApp.fim:
        return _TelaFim(state: this);
      case EstadoApp.gerenciar:
        return _TelaGerenciar(state: this);
    }
  }
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
                    backgroundImage: perfil.fotoUrl.isNotEmpty
                        ? (perfil.fotoUrl.startsWith('data:')
                            ? MemoryImage(base64Decode(
                                    perfil.fotoUrl
                                        .split(',')
                                        .last))
                                as ImageProvider<Object>
                            : NetworkImage(perfil.fotoUrl)
                                as ImageProvider<Object>)
                        : null,
                    child: perfil.fotoUrl.isEmpty
                        ? Icon(Icons.person,
                            size: 40, color: branco)
                        : null,
                  ),
                  const SizedBox(height: 10),
                  Text(
                    perfil.nome.isEmpty
                        ? 'Utilizador'
                        : perfil.nome,
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
                  MaterialPageRoute(
                      builder: (_) =>
                          const TelaPomodoroInfo()));
            },
          ),
          _drawerItem(
            icon: Icons.account_circle_outlined,
            label: 'Perfil',
            onTap: () async {
              Navigator.pop(context);
              final resultado =
                  await Navigator.push<PerfilUsuario>(
                context,
                MaterialPageRoute(
                  builder: (_) =>
                      TelaPerfil(perfil: state.perfil),
                ),
              );
              if (resultado != null) {
                // ignore: invalid_use_of_protected_member
                state.setState(
                    () => state.perfil = resultado);
                // FIX: guardar perfil imediatamente após edição
                await state._guardarTudo();
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
                      builder: (_) => TelaTodo(
                          lista: state.notasTodo,
                          todoBlocosJson:
                              state._todoBlocosGuardados)));
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
                      builder: (_) => TelaInsights(
                          sessoes: state.sessoes)));
            },
          ),
          StreamBuilder<QuerySnapshot>(
            stream: FirebaseFirestore.instance
                .collection('pedidos_amizade')
                .where('para',
                    isEqualTo: FirebaseAuth
                        .instance.currentUser!.uid)
                .snapshots(),
            builder: (ctx, snap) {
              final countPedidos = snap.data?.docs
                      .where((d) =>
                          (d.data() as Map)['estado'] ==
                          'pendente')
                      .length ??
                  0;
              return StreamBuilder<QuerySnapshot>(
                stream: FirebaseFirestore.instance
                    .collection('users')
                    .doc(FirebaseAuth
                        .instance.currentUser!.uid)
                    .collection('reacoes')
                    .where('lida', isEqualTo: false)
                    .snapshots(),
                builder: (ctx2, snapR) {
                  final countReacoes =
                      snapR.data?.docs.length ?? 0;
                  final count =
                      countPedidos + countReacoes;
                  return _drawerItem(
                    icon: Icons.group_outlined,
                    label: 'Amigos',
                    badge: count,
                    onTap: () {
                      Navigator.pop(context);
                      Navigator.push(
                          context,
                          MaterialPageRoute(
                              builder: (_) => TelaAmigos(
                                  uid: FirebaseAuth.instance
                                      .currentUser!.uid)));
                    },
                  );
                },
              );
            },
          ),
          _drawerItem(
            icon: Icons.leaderboard_outlined,
            label: 'Leaderboard Global',
            onTap: () {
              Navigator.pop(context);
              Navigator.push(
                  context,
                  MaterialPageRoute(
                      builder: (_) =>
                          const TelaLeaderboard()));
            },
          ),
          _drawerItem(
            icon: Icons.flag_outlined,
            label: 'Meta Semanal',
            onTap: () {
              Navigator.pop(context);
              showModalBottomSheet(
                context: context,
                isScrollControlled: true,
                backgroundColor: Colors.transparent,
                builder: (_) => _BottomSheetMetaSemanal(
                  sessoes: state.sessoes,
                  metaAtual: state._metaSemanalMinutos,
                  onSalvar: (v) {
                    // ignore: invalid_use_of_protected_member
                    state.setState(() =>
                        state._metaSemanalMinutos = v);
                    state._guardarTudo();
                  },
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
                  MaterialPageRoute(
                      builder: (_) =>
                          _TelaTarefasConcluidas(
                              state: state)));
            },
          ),
          _drawerItem(
            icon: Icons.settings,
            label: 'Definições',
            onTap: () {
              Navigator.pop(context);
              Navigator.push(
                  context,
                  MaterialPageRoute(
                      builder: (_) =>
                          const TelaDefinicoes()));
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
    int badge = 0,
  }) {
    return ListTile(
      leading: badge > 0
          ? Badge(
              label: Text('$badge',
                  style: const TextStyle(fontSize: 10)),
              child: Icon(icon, color: Colors.white),
            )
          : Icon(icon, color: Colors.white),
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
  final DateTime? countdownAlvoInicial;
  final String? countdownMotivoInicial;
  final String? todoBlocosJson;

  const _TelaInicial({
    required this.state,
    this.countdownAlvoInicial,
    this.countdownMotivoInicial,
    this.todoBlocosJson,
  });

  @override
  State<_TelaInicial> createState() => _TelaInicialState();
}

class _TelaInicialState extends State<_TelaInicial> {
  late DateTime _alvo;
  late String _motivoAlvo;
  Timer? _tickTimer;

  @override
  void initState() {
    super.initState();
    // FIX: usa valor guardado se existir, senão default
    _alvo = widget.countdownAlvoInicial ??
        DateTime.now()
            .add(const Duration(days: 47, hours: 9, minutes: 57));
    _motivoAlvo =
        widget.countdownMotivoInicial ?? 'Exame';
    _tickTimer =
        Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) setState(() {});
    });
  }

  // FIX: atualizar quando o widget pai passa novos valores
  @override
  void didUpdateWidget(_TelaInicial oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.countdownAlvoInicial != null &&
        widget.countdownAlvoInicial !=
            oldWidget.countdownAlvoInicial) {
      setState(() {
        _alvo = widget.countdownAlvoInicial!;
      });
    }
    if (widget.countdownMotivoInicial != null &&
        widget.countdownMotivoInicial !=
            oldWidget.countdownMotivoInicial) {
      setState(() {
        _motivoAlvo = widget.countdownMotivoInicial!;
      });
    }
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
    final data = await showDatePicker(
      context: context,
      initialDate: _alvo.isAfter(DateTime.now())
          ? _alvo
          : DateTime.now().add(const Duration(days: 1)),
      firstDate: DateTime.now(),
      lastDate:
          DateTime.now().add(const Duration(days: 3650)),
      builder: (ctx, child) => Theme(
        data: Theme.of(ctx).copyWith(
          colorScheme: const ColorScheme.dark(
              primary: Color(0xFF1D81C7),
              surface: Color(0xFF111111)),
        ),
        child: child!,
      ),
    );
    if (data == null || !mounted) return;

    final hora = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_alvo),
      builder: (ctx, child) => Theme(
        data: Theme.of(ctx).copyWith(
          colorScheme: const ColorScheme.dark(
              primary: Color(0xFF1D81C7),
              surface: Color(0xFF111111)),
        ),
        child: child!,
      ),
    );
    if (!mounted) return;

    final novoAlvo = hora == null
        ? DateTime(data.year, data.month, data.day)
        : DateTime(data.year, data.month, data.day,
            hora.hour, hora.minute);

    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF111111),
        title: const Text('Motivo',
            style: TextStyle(color: Color(0xFF1D81C7))),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          style: TextStyle(color: _tc()),
          decoration: const InputDecoration(
            hintText: 'Ex: Exame de Matemática',
            hintStyle: TextStyle(color: Colors.white38),
            enabledBorder: UnderlineInputBorder(
                borderSide:
                    BorderSide(color: Colors.white24)),
            focusedBorder: UnderlineInputBorder(
                borderSide: BorderSide(
                    color: Color(0xFF1D81C7))),
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancelar')),
          TextButton(
            onPressed: () =>
                Navigator.pop(ctx, ctrl.text.trim()),
            child: const Text('OK',
                style: TextStyle(
                    color: Color(0xFF1D81C7))),
          ),
        ],
      ),
    );
    if (!mounted) return;

    setState(() {
      _alvo = novoAlvo;
      if (ctrl.text.trim().isNotEmpty) {
        _motivoAlvo = ctrl.text.trim();
      }
    });

    // FIX: usar setState do pai para garantir persistência do countdown
    // ignore: invalid_use_of_protected_member
    widget.state.setState(() {
      widget.state._countdownAlvoGuardado = _alvo;
      widget.state._countdownMotivoGuardado = _motivoAlvo;
    });
    // Guardar no Firestore imediatamente
    widget.state._configDoc.set({
      'countdownAlvo': _alvo.toIso8601String(),
      'countdownMotivo': _motivoAlvo,
    }, SetOptions(merge: true)).catchError(
        (e) => debugPrint('Erro ao guardar countdown: $e'));
  }

  @override
  Widget build(BuildContext context) {
    const azul = _PomodoroAppState._azul;
    final ultimaTarefa = widget.state.ultimaTarefa;
    final tarefas = widget.state.tarefas
        .where((t) => t.progressoSalvo < 1.0)
        .toList();

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
            ValueListenableBuilder<bool>(
              valueListenable: temaEscuro,
              builder: (_, _esc2, __) => Container(
                color: azul,
                padding: const EdgeInsets.symmetric(
                    horizontal: 12, vertical: 8),
                child: Row(
                  children: [
                    GestureDetector(
                      onTap: () {},
                      child: Container(
                        width: 40,
                        height: 40,
                        decoration: const BoxDecoration(
                            shape: BoxShape.circle,
                            color: Colors.white),
                        child: ClipOval(
                          child: CustomPaint(
                              painter:
                                  const _TomatoPainter(),
                              size: const Size(40, 40)),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    _StreakBadge(
                      streak: StreakInfo.calcularComFreeze(
                          widget.state.sessoes,
                          widget.state._freezeDias),
                      onUsarFreeze:
                          widget.state._usarStreakFreeze,
                      freezesDisponiveis:
                          widget.state._streakFreezes,
                    ),
                    const Expanded(child: SizedBox()),
                    IconButton(
                      icon: const Icon(Icons.menu,
                          color: Colors.white, size: 26),
                      onPressed: () => widget.state
                          ._scaffoldKey.currentState
                          ?.openDrawer(),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                    ),
                  ],
                ),
              ),
            ),
            Container(
              color: azul,
              padding:
                  const EdgeInsets.fromLTRB(16, 8, 16, 16),
              child: Row(
                crossAxisAlignment:
                    CrossAxisAlignment.end,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment:
                          CrossAxisAlignment.start,
                      children: const [
                        Text('Thoth',
                            style: TextStyle(
                                fontSize: 44,
                                color: Colors.white,
                                fontWeight:
                                    FontWeight.bold,
                                height: 1.0)),
                        Text('Study helper - pomodoro',
                            style: TextStyle(
                                fontSize: 13,
                                color: Colors.white70)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(
                  25, 10, 25, 0),
              child: Text(
                widget.state.perfil.citacao.isEmpty
                    ? ''
                    : '"${widget.state.perfil.citacao}"',
                style: TextStyle(
                    fontSize: 12,
                    color: _tc().withOpacity(0.55),
                    fontStyle: FontStyle.italic),
                maxLines: 2,
              ),
            ),
            const SizedBox(height: 14),
            GestureDetector(
              onTap: _editarAlvo,
              child: Container(
                margin: const EdgeInsets.symmetric(
                    horizontal: 25),
                padding: const EdgeInsets.symmetric(
                    vertical: 14, horizontal: 18),
                decoration: BoxDecoration(
                  color: azul.withOpacity(0.08),
                  border: Border.all(
                      color: azul.withOpacity(0.35)),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Column(
                  children: [
                    Row(
                      mainAxisAlignment:
                          MainAxisAlignment.center,
                      children: [
                        Text(
                          'Faltam para $_motivoAlvo',
                          style: TextStyle(
                              color: azul,
                              fontSize: 13,
                              fontWeight:
                                  FontWeight.bold),
                        ),
                        const SizedBox(width: 6),
                        Icon(Icons.edit_outlined,
                            color: azul, size: 14),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Row(
                      mainAxisAlignment:
                          MainAxisAlignment.center,
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
            const SizedBox(height: 12),
            if (widget.state._metaSemanalMinutos > 0)
              _CartaoMetaSemanal(
                  sessoes: widget.state.sessoes,
                  meta: widget.state._metaSemanalMinutos),
            const SizedBox(height: 12),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(
                    horizontal: 25),
                child: Column(
                  crossAxisAlignment:
                      CrossAxisAlignment.start,
                  children: [
                    if (ultimaTarefa != null &&
                        ultimaTarefa.progressoSalvo >
                            0.0 &&
                        ultimaTarefa.progressoSalvo <
                            1.0) ...[
                      _CartaoRetomar(
                          state: widget.state,
                          ultimaTarefa: ultimaTarefa),
                      const SizedBox(height: 16),
                    ],
                    const Text('Tarefas',
                        style: TextStyle(
                            fontSize: 18,
                            color: azul,
                            fontWeight: FontWeight.bold)),
                    const SizedBox(height: 10),
                    Expanded(
                      child: tarefas.isEmpty
                          ? Center(
                              child: Column(
                                mainAxisAlignment:
                                    MainAxisAlignment
                                        .center,
                                children: [
                                  Icon(
                                      Icons
                                          .inbox_outlined,
                                      size: 60,
                                      color: _tc()
                                          .withOpacity(
                                              0.2)),
                                  const SizedBox(
                                      height: 16),
                                  Text(
                                      'Nenhuma tarefa criada',
                                      style: TextStyle(
                                          color: _tc()
                                              .withOpacity(
                                                  0.4),
                                          fontSize: 16,
                                          fontWeight:
                                              FontWeight
                                                  .w300)),
                                  const SizedBox(
                                      height: 8),
                                  Text(
                                      'Toca em "Gerir Tarefas" para começar',
                                      style: TextStyle(
                                          color: _tc()
                                              .withOpacity(
                                                  0.25),
                                          fontSize: 13)),
                                ],
                              ),
                            )
                          : ListView.builder(
                              itemCount: tarefas.length,
                              itemBuilder: (ctx, i) =>
                                  _CartaoTarefa(
                                    tarefa: tarefas[i],
                                    onTap: () => widget
                                        .state
                                        .iniciarTarefa(
                                            tarefas[i]),
                                  ),
                            ),
                    ),
                    Padding(
                      padding: const EdgeInsets.only(
                          bottom: 20, top: 10),
                      child: ElevatedButton(
                        onPressed: () =>
                            // ignore: invalid_use_of_protected_member
                            widget.state.setState(() =>
                                widget.state.estadoApp =
                                    EstadoApp.gerenciar),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: azul,
                          foregroundColor: branco,
                          minimumSize: const Size(
                              double.infinity, 55),
                          shape: RoundedRectangleBorder(
                              borderRadius:
                                  BorderRadius.circular(
                                      12)),
                        ),
                        child: const Text('GERIR TAREFAS',
                            style: TextStyle(
                                fontWeight:
                                    FontWeight.bold,
                                letterSpacing: 1)),
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
            style: TextStyle(
                fontSize: 38,
                fontWeight: FontWeight.bold,
                color: _tc(),
                height: 1.0)),
        Text(label,
            style: const TextStyle(
                color: azul,
                fontSize: 12,
                fontWeight: FontWeight.bold)),
      ],
    );
  }
}

// =============================================================================
// CARTÃO META SEMANAL
// =============================================================================

class _CartaoMetaSemanal extends StatelessWidget {
  final List<SessaoConcluida> sessoes;
  final int meta;
  const _CartaoMetaSemanal(
      {required this.sessoes, required this.meta});

  int get _minutosEstaSemana {
    final hoje = DateTime.now();
    final inicioSemana =
        hoje.subtract(Duration(days: hoje.weekday - 1));
    final semanaStr = DateTime(inicioSemana.year,
        inicioSemana.month, inicioSemana.day);
    return sessoes
        .where((s) => s.dataConclusao.isAfter(semanaStr))
        .fold(0,
            (acc, s) => acc + s.tempoFocoSegundos ~/ 60);
  }

  @override
  Widget build(BuildContext context) {
    const azul = Color(0xFF1D81C7);
    const verde = Colors.greenAccent;
    final mins = _minutosEstaSemana;
    final progresso =
        meta > 0 ? (mins / meta).clamp(0.0, 1.0) : 0.0;
    final concluida = progresso >= 1.0;

    return GestureDetector(
      onTap: () => showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (_) => _BottomSheetMetaSemanal(
          sessoes: sessoes,
          metaAtual: meta,
          onSalvar: (_) {},
        ),
      ),
      child: Container(
        margin:
            const EdgeInsets.symmetric(horizontal: 25),
        padding: const EdgeInsets.symmetric(
            vertical: 12, horizontal: 16),
        decoration: BoxDecoration(
          color: concluida
              ? verde.withOpacity(0.07)
              : azul.withOpacity(0.06),
          border: Border.all(
              color: concluida
                  ? verde.withOpacity(0.4)
                  : azul.withOpacity(0.3)),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Column(
          children: [
            Row(
              children: [
                Text(concluida ? '🏆' : '🎯',
                    style: const TextStyle(fontSize: 16)),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    concluida
                        ? 'Meta semanal atingida!'
                        : 'Meta semanal',
                    style: TextStyle(
                        color: concluida ? verde : azul,
                        fontSize: 13,
                        fontWeight: FontWeight.bold),
                  ),
                ),
                Text(
                  '${mins ~/ 60}h ${mins % 60}m / ${meta ~/ 60}h',
                  style: TextStyle(
                      color: _tc54(), fontSize: 12),
                ),
              ],
            ),
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: progresso,
                minHeight: 6,
                color: concluida ? verde : azul,
                backgroundColor:
                    _tc().withOpacity(0.08),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// =============================================================================
// STREAK BADGE
// =============================================================================

class _StreakBadge extends StatelessWidget {
  final StreakInfo streak;
  final Future<void> Function()? onUsarFreeze;
  final int freezesDisponiveis;
  const _StreakBadge(
      {required this.streak,
      this.onUsarFreeze,
      this.freezesDisponiveis = 0});

  @override
  Widget build(BuildContext context) {
    final aceso =
        streak.acendeuHoje || streak.frozenHoje;
    final dias = streak.dias;
    return GestureDetector(
      onTap: () {
        showDialog(
          context: context,
          builder: (_) => _StreakDialog(
              streak: streak,
              onUsarFreeze: onUsarFreeze,
              freezesDisponiveis: freezesDisponiveis),
        );
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 400),
        padding: const EdgeInsets.symmetric(
            horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: aceso
              ? const Color(0xFFFF6D00).withOpacity(0.25)
              : Colors.white.withOpacity(0.10),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: aceso
                ? const Color(0xFFFF6D00)
                : Colors.white24,
            width: 1.2,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('🔥', style: TextStyle(fontSize: 16)),
            const SizedBox(width: 4),
            Text(
              '$dias',
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.bold,
                color: aceso
                    ? const Color(0xFFFFCC02)
                    : Colors.white60,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StreakDialog extends StatelessWidget {
  final StreakInfo streak;
  final Future<void> Function()? onUsarFreeze;
  final int freezesDisponiveis;
  const _StreakDialog(
      {required this.streak,
      this.onUsarFreeze,
      this.freezesDisponiveis = 0});

  @override
  Widget build(BuildContext context) {
    const azul = Color(0xFF1D81C7);
    final dias = streak.dias;
    return Dialog(
      backgroundColor: Colors.transparent,
      child: Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: temaEscuro.value
              ? const Color(0xFF111111)
              : Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
              color: const Color(0xFFFF6D00)
                  .withOpacity(0.4)),
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('🔥',
                  style: TextStyle(fontSize: 48)),
              const SizedBox(height: 8),
              Text('$dias dias seguidos!',
                  style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                      color: _tc())),
              const SizedBox(height: 4),
              Text(
                streak.acendeuHoje
                    ? 'Estudaste hoje. Continua assim!'
                    : 'Estuda hoje para não perder a streak!',
                style: TextStyle(
                    color: _tc54(), fontSize: 13),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 20),
              const Divider(),
              const SizedBox(height: 12),
              Align(
                alignment: Alignment.centerLeft,
                child: const Text('Conquistas de streak',
                    style: TextStyle(
                        color: azul,
                        fontSize: 14,
                        fontWeight: FontWeight.bold)),
              ),
              const SizedBox(height: 10),
              ...StreakInfo.conquistas.map((c) {
                final meta = c['dias'] as int;
                final conquistada = dias >= meta;
                return Padding(
                  padding:
                      const EdgeInsets.only(bottom: 8),
                  child: Row(
                    children: [
                      Text(c['icon'] as String,
                          style: const TextStyle(
                              fontSize: 20)),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment:
                              CrossAxisAlignment.start,
                          children: [
                            Text(c['label'] as String,
                                style: TextStyle(
                                    color: conquistada
                                        ? _tc()
                                        : _tc38(),
                                    fontWeight: conquistada
                                        ? FontWeight.bold
                                        : FontWeight.normal,
                                    fontSize: 14)),
                            LinearProgressIndicator(
                              value: (dias / meta)
                                  .clamp(0.0, 1.0),
                              backgroundColor: _tc12(),
                              color: conquistada
                                  ? const Color(
                                      0xFFFF6D00)
                                  : azul,
                              minHeight: 3,
                              borderRadius:
                                  BorderRadius.circular(
                                      4),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      if (conquistada)
                        const Icon(Icons.check_circle,
                            color: Color(0xFFFF6D00),
                            size: 16)
                      else
                        Text('$meta',
                            style: TextStyle(
                                color: _tc38(),
                                fontSize: 12)),
                    ],
                  ),
                );
              }),
              const SizedBox(height: 12),
              if (!streak.acendeuHoje &&
                  !streak.frozenHoje) ...[
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: freezesDisponiveis > 0 &&
                            onUsarFreeze != null
                        ? () async {
                            await onUsarFreeze!();
                            if (context.mounted) {
                              Navigator.pop(context);
                            }
                          }
                        : null,
                    icon: const Text('🧊',
                        style: TextStyle(fontSize: 16)),
                    label: Text(
                        freezesDisponiveis > 0
                            ? 'Usar Streak Freeze ($freezesDisponiveis disponíveis)'
                            : 'Sem Streak Freezes disponíveis',
                        style: const TextStyle(
                            fontSize: 13)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor:
                          const Color(0xFF1565C0),
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                          borderRadius:
                              BorderRadius.circular(10)),
                      padding:
                          const EdgeInsets.symmetric(
                              vertical: 12),
                    ),
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                    'Ganhas 1 freeze a cada 7 dias de streak consecutivos',
                    style: TextStyle(
                        color: _tc38(), fontSize: 11),
                    textAlign: TextAlign.center),
                const SizedBox(height: 12),
              ],
              if (streak.frozenHoje) ...[
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 8),
                  margin:
                      const EdgeInsets.only(bottom: 12),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1565C0)
                        .withOpacity(0.12),
                    borderRadius:
                        BorderRadius.circular(10),
                    border: Border.all(
                        color: const Color(0xFF1565C0)
                            .withOpacity(0.4)),
                  ),
                  child: const Row(
                    mainAxisAlignment:
                        MainAxisAlignment.center,
                    children: [
                      Text('🧊',
                          style: TextStyle(fontSize: 16)),
                      SizedBox(width: 8),
                      Text('Streak protegida por freeze hoje!',
                          style: TextStyle(
                              color: Color(0xFF42A5F5),
                              fontSize: 13)),
                    ],
                  ),
                ),
              ],
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: () {
                    Navigator.pop(context);
                    final keyStreakCard = GlobalKey();
                    final texto = [
                      '🔥 $dias ${dias == 1 ? 'dia' : 'dias'} de estudo seguidos no THOTH!',
                      streak.acendeuHoje
                          ? 'Streak activa hoje! 💪'
                          : 'A minha streak de estudo',
                      '',
                      '#Thoth #Streak #Produtividade #Estudo',
                    ].join('\n');
                    showDialog(
                      context: context,
                      builder: (_) => _DialogoPartilha(
                        textoPartilha: texto,
                        cartao: RepaintBoundary(
                          key: keyStreakCard,
                          child: _StreakShareCard(
                            dias: dias,
                            acendeuHoje:
                                streak.acendeuHoje,
                            conquistas:
                                StreakInfo.conquistas,
                          ),
                        ),
                        aoPartilhar: () async {
                          await _registarPartilhaFirestore(
                            tipo: 'streak',
                            streakDias: dias,
                            totalFoco: 0,
                            totalCiclos: 0,
                            totalSessoes: 0,
                          );
                          await _partilharImagem(
                              key: keyStreakCard,
                              texto: texto);
                        },
                      ),
                    );
                  },
                  icon: const Icon(
                      Icons.ios_share_rounded,
                      size: 16,
                      color: Color(0xFFFF6D00)),
                  label: const Text('Partilhar streak',
                      style: TextStyle(
                          color: Color(0xFFFF6D00))),
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(
                        color: Color(0x66FF6D00)),
                    shape: RoundedRectangleBorder(
                        borderRadius:
                            BorderRadius.circular(10)),
                    padding: const EdgeInsets.symmetric(
                        vertical: 11),
                  ),
                ),
              ),
              const SizedBox(height: 6),
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Fechar',
                    style: TextStyle(color: azul)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// =============================================================================
// CARTÃO RETOMAR
// =============================================================================

class _CartaoRetomar extends StatelessWidget {
  final _PomodoroAppState state;
  final Tarefa ultimaTarefa;
  const _CartaoRetomar(
      {required this.state, required this.ultimaTarefa});

  @override
  Widget build(BuildContext context) {
    const azul = _PomodoroAppState._azul;
    final branco = _tc();
    final pct =
        (ultimaTarefa.progressoSalvo * 100).toStringAsFixed(0);

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
              const Icon(Icons.history,
                  color: azul, size: 16),
              const SizedBox(width: 6),
              const Text('Última sessão',
                  style: TextStyle(
                      color: azul,
                      fontSize: 12,
                      letterSpacing: 1)),
              const Spacer(),
              Text('$pct%',
                  style: const TextStyle(
                      color: azul,
                      fontSize: 12,
                      fontWeight: FontWeight.bold)),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            ultimaTarefa.nome.isEmpty
                ? 'Tarefa Sem Nome'
                : ultimaTarefa.nome,
            style: TextStyle(
                color: _tc(),
                fontSize: 16,
                fontWeight: FontWeight.bold),
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
                  onPressed: () => state.iniciarTarefa(
                      ultimaTarefa,
                      retomar: true),
                  icon: const Icon(Icons.play_arrow,
                      color: azul, size: 18),
                  label: Text('PROSSEGUIR',
                      style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: branco,
                          fontSize: 12)),
                  style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: azul)),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: state.descartarProgresso,
                  icon: const Icon(Icons.delete_sweep,
                      color: Colors.redAccent, size: 18),
                  label: const Text('DESCARTAR',
                      style: TextStyle(
                          color: Colors.redAccent,
                          fontSize: 12)),
                  style: OutlinedButton.styleFrom(
                      side: const BorderSide(
                          color: Colors.redAccent)),
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
  const _CartaoTarefa(
      {required this.tarefa, required this.onTap});

  @override
  Widget build(BuildContext context) {
    const azul = _PomodoroAppState._azul;
    final branco = _tc();
    final temProgresso =
        tarefa.progressoSalvo > 0.0 &&
            tarefa.progressoSalvo < 1.0;
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
          padding: const EdgeInsets.symmetric(
              horizontal: 16, vertical: 14),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment:
                      CrossAxisAlignment.start,
                  children: [
                    Text(
                      tarefa.nome.isEmpty
                          ? 'Nova Tarefa'
                          : tarefa.nome,
                      style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: concluida
                              ? Colors.greenAccent
                                  .withOpacity(0.8)
                              : branco,
                          fontSize: 17),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Foco: ${tarefa.estudo ~/ 60}m  ·  Descanso: ${tarefa.descanso ~/ 60}m  ·  ${tarefa.ciclos} ciclos',
                      style: const TextStyle(
                          color: azul,
                          fontSize: 13,
                          height: 1.4),
                    ),
                    if (temProgresso) ...[
                      const SizedBox(height: 8),
                      ClipRRect(
                        borderRadius:
                            BorderRadius.circular(3),
                        child: LinearProgressIndicator(
                          value: tarefa.progressoSalvo,
                          color: azul,
                          backgroundColor:
                              branco.withOpacity(0.1),
                          minHeight: 3,
                        ),
                      ),
                    ],
                    if (concluida) ...[
                      const SizedBox(height: 6),
                      const Text('✓ Concluída',
                          style: TextStyle(
                              color: Colors.greenAccent,
                              fontSize: 12)),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Icon(
                concluida
                    ? Icons.check_circle
                    : Icons.play_circle_fill,
                color:
                    concluida ? Colors.greenAccent : azul,
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
        title: const Text('Gerir Tarefas'),
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: _tc()),
          // ignore: invalid_use_of_protected_member
          onPressed: () => state.setState(
              () => state.estadoApp = EstadoApp.inicio),
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
                mainAxisAlignment:
                    MainAxisAlignment.center,
                children: [
                  Icon(Icons.add_task,
                      size: 64,
                      color: _tc().withOpacity(0.2)),
                  const SizedBox(height: 16),
                  Text('Nenhuma tarefa',
                      style: TextStyle(
                          color: _tc().withOpacity(0.4),
                          fontSize: 18)),
                  const SizedBox(height: 8),
                  Text('Toca no + para criar',
                      style: TextStyle(
                          color:
                              branco.withOpacity(0.25),
                          fontSize: 14)),
                ],
              ),
            )
          : ReorderableListView.builder(
              padding:
                  const EdgeInsets.only(bottom: 80),
              itemCount: tarefas.length,
              onReorder: (oldIndex, newIndex) {
                // ignore: invalid_use_of_protected_member
                state.setState(() {
                  if (newIndex > oldIndex) newIndex--;
                  final item =
                      state.tarefas.removeAt(oldIndex);
                  state.tarefas.insert(newIndex, item);
                });
                state._guardarTudo();
              },
              itemBuilder: (ctx, i) =>
                  _linhaGerenciar(ctx, i, tarefas[i]),
            ),
    );
  }

  Widget _linhaGerenciar(
      BuildContext context, int i, Tarefa t) {
    const azul = _PomodoroAppState._azul;

    return Dismissible(
      key: ValueKey(t.id),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        color: Colors.red.withOpacity(0.2),
        child: const Icon(Icons.delete,
            color: Colors.redAccent),
      ),
      onDismissed: (_) => state.removerTarefa(i),
      child: Container(
        key: ValueKey('${t.id}_container'),
        decoration: BoxDecoration(
          border: Border(
              bottom: BorderSide(
                  color: _tc().withOpacity(0.08))),
        ),
        child: ListTile(
          title: Text(t.nome.isEmpty ? 'Sem nome' : t.nome,
              style: TextStyle(
                  color: _tc(),
                  fontWeight: FontWeight.bold)),
          subtitle: Text(
              '${t.estudo ~/ 60}m foco · ${t.descanso ~/ 60}m descanso · ${t.ciclos} ciclos',
              style: const TextStyle(
                  color: azul, fontSize: 13)),
          leading: const Icon(Icons.drag_handle,
              color: Colors.white38),
          trailing: IconButton(
            icon: Icon(Icons.edit_outlined, color: _tc()),
            onPressed: () =>
                _abrirEditor(context, index: i),
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
        : Tarefa(
            id: DateTime.now()
                .millisecondsSinceEpoch
                .toString());

    final nomeCtrl =
        TextEditingController(text: temp.nome);

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.black,
      shape: const RoundedRectangleBorder(
        borderRadius:
            BorderRadius.vertical(top: Radius.circular(22)),
        side: BorderSide(
            color: Color(0xFF1D81C7), width: 2),
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
          state._guardarTudo();
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
  const _EditorTarefa(
      {required this.temp,
      required this.nomeCtrl,
      required this.onGuardar});

  @override
  State<_EditorTarefa> createState() =>
      _EditorTarefaState();
}

class _EditorTarefaState extends State<_EditorTarefa> {
  static const Color azul = _PomodoroAppState._azul;
  static const Color branco = _PomodoroAppState._branco;

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
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                    color: Colors.white24,
                    borderRadius:
                        BorderRadius.circular(2)),
              ),
            ),
            const SizedBox(height: 20),
            const Text('Configurar Tarefa',
                style: TextStyle(
                    color: azul,
                    fontSize: 18,
                    fontWeight: FontWeight.bold)),
            const SizedBox(height: 20),
            TextField(
              controller: widget.nomeCtrl,
              style: TextStyle(color: _tc()),
              textCapitalization:
                  TextCapitalization.sentences,
              decoration: InputDecoration(
                labelText: 'Nome da Tarefa',
                hintText: 'Ex: Estudar Matemática',
                hintStyle: TextStyle(
                    color: branco.withOpacity(0.3)),
                labelStyle:
                    const TextStyle(color: azul),
                enabledBorder:
                    const UnderlineInputBorder(
                        borderSide: BorderSide(
                            color: Colors.white24)),
                focusedBorder:
                    const UnderlineInputBorder(
                        borderSide:
                            BorderSide(color: azul)),
              ),
              onChanged: (v) => t.nome = v,
            ),
            const SizedBox(height: 30),
            _labelSlider('Tempo de Foco',
                '${t.estudo ~/ 60} min'),
            Slider(
              value: t.estudo.toDouble(),
              min: 60,
              max: 7200,
              divisions: 119,
              label: '${t.estudo ~/ 60}m',
              onChanged: (v) => setState(
                  () => t.estudo = (v / 60).round() * 60),
            ),
            _labelSlider('Tempo de Descanso',
                '${t.descanso ~/ 60} min'),
            Slider(
              value: t.descanso.toDouble(),
              min: 60,
              max: 3600,
              divisions: 59,
              label: '${t.descanso ~/ 60}m',
              onChanged: (v) => setState(() =>
                  t.descanso = (v / 60).round() * 60),
            ),
            _labelSlider('Número de Ciclos',
                '${t.ciclos} ciclos'),
            Slider(
              value: t.ciclos.toDouble(),
              min: 1,
              max: 10,
              divisions: 9,
              label: '${t.ciclos}',
              onChanged: (v) =>
                  setState(() => t.ciclos = v.toInt()),
            ),
            const SizedBox(height: 25),
            ElevatedButton(
              onPressed: widget.onGuardar,
              style: ElevatedButton.styleFrom(
                backgroundColor: azul,
                foregroundColor: branco,
                minimumSize:
                    const Size(double.infinity, 52),
                shape: RoundedRectangleBorder(
                    borderRadius:
                        BorderRadius.circular(12)),
              ),
              child: const Text('GUARDAR',
                  style: TextStyle(
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1)),
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
        Text(titulo,
            style: TextStyle(
                color: branco.withOpacity(0.7),
                fontSize: 13)),
        Text(valor,
            style: const TextStyle(
                color: azul,
                fontWeight: FontWeight.bold,
                fontSize: 14)),
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

    final tarefa = state.tarefaAtual;
    if (tarefa == null) return const SizedBox();
    final estaNoDescanso = state.estaNoDescanso;
    final total =
        estaNoDescanso ? tarefa.descanso : tarefa.estudo;
    final progresso = total <= 0
        ? 0.0
        : (1 - (state.segundosRestantes / total))
            .clamp(0.0, 1.0);
    final pausado = state.pausado;

    return ValueListenableBuilder<bool>(
      valueListenable: temaEscuro,
      builder: (context, _e, __) {
        final tc = _tc();
        final tc38 = _tc38();
        return Scaffold(
          body: SafeArea(
            child: Column(
              children: [
                Expanded(
                  child: Column(
                    mainAxisAlignment:
                        MainAxisAlignment.center,
                    children: [
                      if (state._modoDNDAtivo)
                        Padding(
                          padding: const EdgeInsets.only(
                              top: 4, bottom: 4),
                          child: Row(
                            mainAxisAlignment:
                                MainAxisAlignment.center,
                            children: [
                              const Icon(
                                  Icons
                                      .do_not_disturb_on,
                                  size: 13,
                                  color:
                                      Color(0xFF1D81C7)),
                              const SizedBox(width: 4),
                              Text(
                                  'Modo não perturbar activo',
                                  style: TextStyle(
                                      color: _tc38(),
                                      fontSize: 11)),
                            ],
                          ),
                        ),
                      Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 30),
                        child: Text(
                          tarefa.nome.isEmpty
                              ? 'Sem nome'
                              : tarefa.nome,
                          style: const TextStyle(
                              color: azul,
                              letterSpacing: 2,
                              fontSize: 16,
                              fontWeight:
                                  FontWeight.w500),
                          textAlign: TextAlign.center,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(height: 6),
                      AnimatedSwitcher(
                        duration:
                            const Duration(milliseconds: 300),
                        child: Text(
                          estaNoDescanso
                              ? 'DESCANSO'
                              : 'FOCO',
                          key: ValueKey(estaNoDescanso),
                          style: TextStyle(
                              fontSize: 30,
                              color: tc,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 4),
                        ),
                      ),
                      const SizedBox(height: 40),
                      Stack(
                        alignment: Alignment.center,
                        children: [
                          SizedBox(
                            width: 260,
                            height: 260,
                            child: CircularProgressIndicator(
                              value: progresso,
                              strokeWidth: 8,
                              color: azul,
                              backgroundColor:
                                  tc.withOpacity(0.08),
                            ),
                          ),
                          Column(
                            mainAxisAlignment:
                                MainAxisAlignment.center,
                            children: [
                              Text(
                                state.formatar(
                                    state.segundosRestantes),
                                style: TextStyle(
                                    fontSize: 58,
                                    fontWeight:
                                        FontWeight.w200,
                                    color: tc,
                                    letterSpacing: 2),
                              ),
                              if (pausado)
                                Text('PAUSADO',
                                    style: TextStyle(
                                        color: tc38,
                                        fontSize: 12,
                                        letterSpacing: 3)),
                            ],
                          ),
                        ],
                      ),
                      const SizedBox(height: 28),
                      _IndicadorCiclos(
                        cicloAtual: state.cicloAtual,
                        totalCiclos: tarefa.ciclos,
                        estaNoDescanso: estaNoDescanso,
                      ),
                      const SizedBox(height: 48),
                      Row(
                        mainAxisAlignment:
                            MainAxisAlignment.center,
                        children: [
                          _BotaoTimer(
                              icon: Icons.stop_rounded,
                              color: Colors.white38,
                              onPressed: state.reset,
                              tooltip: 'Parar'),
                          const SizedBox(width: 24),
                          _BotaoTimer(
                            icon: pausado
                                ? Icons.play_arrow_rounded
                                : Icons.pause_rounded,
                            color: tc,
                            size: 56,
                            onPressed:
                                state.alternarPausa,
                            tooltip: state._primeiraVez
                                ? 'Começar'
                                : (pausado
                                    ? 'Continuar'
                                    : 'Pausar'),
                          ),
                          const SizedBox(width: 24),
                          _BotaoTimer(
                              icon:
                                  Icons.skip_next_rounded,
                              color: Colors.white38,
                              onPressed: state.pularFase,
                              tooltip: 'Pular fase'),
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
      },
    );
  }
}

class _IndicadorCiclos extends StatelessWidget {
  final int cicloAtual;
  final int totalCiclos;
  final bool estaNoDescanso;
  const _IndicadorCiclos(
      {required this.cicloAtual,
      required this.totalCiclos,
      required this.estaNoDescanso});

  @override
  Widget build(BuildContext context) {
    const azul = _PomodoroAppState._azul;
    return Column(
      children: [
        Text('Ciclo $cicloAtual de $totalCiclos',
            style: const TextStyle(
                color: azul, fontSize: 16)),
        const SizedBox(height: 10),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: List.generate(totalCiclos, (i) {
            final concluido = i < cicloAtual - 1;
            final atual = i == cicloAtual - 1;
            return Container(
              margin:
                  const EdgeInsets.symmetric(horizontal: 3),
              width: atual ? 20 : 10,
              height: 8,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(4),
                color: concluido
                    ? azul
                    : atual
                        ? (estaNoDescanso
                            ? Colors.greenAccent
                                .withOpacity(0.6)
                            : azul)
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
  const _BotaoTimer(
      {required this.icon,
      required this.color,
      required this.onPressed,
      required this.tooltip,
      this.size = 44});

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
// TELA FIM
// =============================================================================

class _TelaFim extends StatelessWidget {
  final _PomodoroAppState state;
  const _TelaFim({required this.state});

  @override
  Widget build(BuildContext context) {
    const azul = _PomodoroAppState._azul;
    final branco = _tc();

    final nome = state.ultimaTarefa?.nome ?? '';
    final ciclos = state.ultimaTarefa?.ciclos ?? 0;
    final tempoFoco = state.ultimaTarefa != null
        ? state.ultimaTarefa!.ciclos *
            state.ultimaTarefa!.estudo
        : 0;

    return Scaffold(
      body: Center(
        child: Padding(
          padding:
              const EdgeInsets.symmetric(horizontal: 40),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              TweenAnimationBuilder<double>(
                tween: Tween(begin: 0.0, end: 1.0),
                duration:
                    const Duration(milliseconds: 600),
                curve: Curves.elasticOut,
                builder: (_, v, child) =>
                    Transform.scale(
                        scale: v, child: child),
                child: const Icon(
                    Icons.check_circle_outline,
                    size: 100,
                    color: azul),
              ),
              const SizedBox(height: 24),
              Text('SESSÃO CONCLUÍDA!',
                  style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                      color: branco,
                      letterSpacing: 3)),
              const SizedBox(height: 8),
              if (nome.isNotEmpty)
                Text(nome,
                    style: const TextStyle(
                        color: azul, fontSize: 16),
                    textAlign: TextAlign.center),
              const SizedBox(height: 40),
              Row(
                mainAxisAlignment:
                    MainAxisAlignment.center,
                children: [
                  _statItem(Icons.repeat, '$ciclos',
                      'ciclos'),
                  const SizedBox(width: 30),
                  _statItem(Icons.timer_outlined,
                      '${tempoFoco ~/ 60}',
                      'minutos foco'),
                ],
              ),
              const SizedBox(height: 50),
              ElevatedButton(
                onPressed: state.reset,
                style: ElevatedButton.styleFrom(
                  backgroundColor: azul,
                  foregroundColor: branco,
                  minimumSize: const Size(200, 52),
                  shape: RoundedRectangleBorder(
                      borderRadius:
                          BorderRadius.circular(12)),
                ),
                child: const Text('VOLTAR AO INÍCIO',
                    style: TextStyle(
                        fontWeight: FontWeight.bold)),
              ),
              const SizedBox(height: 12),
              TextButton(
                onPressed: () {
                  if (state.ultimaTarefa != null) {
                    final t = state.ultimaTarefa!;
                    t
                      ..progressoSalvo = 0.0
                      ..cicloSalvo = 1
                      ..estavaNoDescanso = false
                      ..segundosSalvos = t.estudo;
                    // FIX: atualizar na lista principal
                    final idx = state.tarefas
                        .indexWhere(
                            (x) => x.id == t.id);
                    if (idx >= 0) {
                      state.tarefas[idx] = t;
                    }
                    state.iniciarTarefa(t);
                  }
                },
                child: const Text('Repetir esta tarefa',
                    style: TextStyle(
                        color: Colors.white38)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

Widget _statItem(
    IconData icon, String valor, String label) {
  return Column(
    children: [
      Icon(icon,
          color: const Color(0xFF1D81C7), size: 28),
      const SizedBox(height: 6),
      Text(valor,
          style: TextStyle(
              color: _tc(),
              fontSize: 28,
              fontWeight: FontWeight.bold)),
      Text(label,
          style: TextStyle(
              color: _tc().withOpacity(0.5),
              fontSize: 12)),
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
  late final TextEditingController _citacaoCtrl;
  File? _fotoLocal;
  String _fotoUrl = '';
  bool _aCarregarFoto = false;

  static const Color azul = Color(0xFF1D81C7);

  @override
  void initState() {
    super.initState();
    _nomeCtrl =
        TextEditingController(text: widget.perfil.nome);
    _usernameCtrl = TextEditingController(
        text: widget.perfil.nomedeutilizador);
    _descCtrl = TextEditingController(
        text: widget.perfil.descricao);
    _motivosCtrl = TextEditingController(
        text: widget.perfil.motivos);
    _citacaoCtrl = TextEditingController(
        text: widget.perfil.citacao);
    _fotoUrl = widget.perfil.fotoUrl;
  }

  @override
  void dispose() {
    _nomeCtrl.dispose();
    _usernameCtrl.dispose();
    _descCtrl.dispose();
    _motivosCtrl.dispose();
    _citacaoCtrl.dispose();
    super.dispose();
  }

  Future<void> _escolherFoto() async {
    if (_isDesktop) {
      final picker = ImagePicker();
      final picked = await picker.pickImage(
          source: ImageSource.gallery,
          imageQuality: 75,
          maxWidth: 512);
      if (picked == null || !mounted) return;
      setState(() => _fotoLocal = File(picked.path));
      return;
    }

    final source =
        await showModalBottomSheet<ImageSource>(
      context: context,
      backgroundColor: const Color(0xFF111111),
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(
              top: Radius.circular(20))),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 12),
            ListTile(
              leading: const Icon(Icons.camera_alt,
                  color: azul),
              title: const Text('Tirar foto',
                  style: TextStyle(
                      color: Colors.white)),
              onTap: () => Navigator.pop(
                  ctx, ImageSource.camera),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library,
                  color: azul),
              title: const Text('Escolher da galeria',
                  style: TextStyle(
                      color: Colors.white)),
              onTap: () => Navigator.pop(
                  ctx, ImageSource.gallery),
            ),
            if (_fotoLocal != null ||
                _fotoUrl.isNotEmpty)
              ListTile(
                leading: const Icon(
                    Icons.delete_outline,
                    color: Colors.redAccent),
                title: const Text('Remover foto',
                    style: TextStyle(
                        color: Colors.redAccent)),
                onTap: () => Navigator.pop(ctx, null),
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );

    if (!mounted) return;

    if (source == null &&
        (_fotoLocal != null || _fotoUrl.isNotEmpty)) {
      setState(() {
        _fotoLocal = null;
        _fotoUrl = '';
      });
      return;
    }
    if (source == null) return;

    final picker = ImagePicker();
    final picked = await picker.pickImage(
        source: source,
        imageQuality: 75,
        maxWidth: 512);
    if (picked == null || !mounted) return;
    setState(() => _fotoLocal = File(picked.path));
  }

  Future<String> _uploadFoto(File foto) async {
    final bytes = await foto.readAsBytes();
    return 'data:image/jpeg;base64,${base64Encode(bytes)}';
  }

  bool _usernameValido(String u) =>
      u.isEmpty ||
      RegExp(r'^[a-zA-Z0-9._]{3,20}$').hasMatch(u);

  Future<bool> _usernameDisponivel(
      String username) async {
    if (username.isEmpty) return true;
    final uid = FirebaseAuth.instance.currentUser!.uid;
    final doc = await FirebaseFirestore.instance
        .collection('usernames')
        .doc(username.toLowerCase())
        .get();
    if (!doc.exists) return true;
    return (doc.data()?['uid'] as String?) == uid;
  }

  Future<void> _guardar() async {
    final novoUsername = _usernameCtrl.text.trim();

    if (!_usernameValido(novoUsername)) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
                content: Text(
                    'Username inválido. Usa entre 3-20 caracteres: letras, números, . e _'),
                backgroundColor: Colors.redAccent));
      }
      return;
    }

    setState(() => _aCarregarFoto = true);

    try {
      if (novoUsername.isNotEmpty) {
        final disponivel =
            await _usernameDisponivel(novoUsername);
        if (!disponivel) {
          if (mounted) {
            setState(() => _aCarregarFoto = false);
            ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                    content: Text(
                        '@$novoUsername já está em uso. Escolhe outro.'),
                    backgroundColor: Colors.redAccent));
          }
          return;
        }
      }

      String fotoFinal = _fotoUrl;
      if (_fotoLocal != null) {
        fotoFinal = await _uploadFoto(_fotoLocal!);
      }

      if (mounted) {
        Navigator.pop(
          context,
          PerfilUsuario(
            nome: _nomeCtrl.text.trim(),
            nomedeutilizador: novoUsername,
            descricao: _descCtrl.text.trim(),
            motivos: _motivosCtrl.text.trim(),
            // FIX: incluir citação no perfil guardado
            citacao: _citacaoCtrl.text.trim(),
            fotoUrl: fotoFinal,
          ),
        );
      }
    } catch (e) {
      debugPrint('Erro ao guardar perfil: $e');
      if (mounted) {
        setState(() => _aCarregarFoto = false);
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
                content:
                    Text('Erro ao guardar. Tenta novamente.'),
                backgroundColor: Colors.redAccent));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Editar Perfil'),
        actions: [
          _aCarregarFoto
              ? const Padding(
                  padding: EdgeInsets.all(14),
                  child: SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: azul)),
                )
              : IconButton(
                  icon: const Icon(Icons.check,
                      color: azul),
                  tooltip: 'Guardar',
                  onPressed: _guardar,
                ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(25),
        child: Column(
          children: [
            Center(
              child: GestureDetector(
                onTap: _escolherFoto,
                child: Stack(
                  children: [
                    CircleAvatar(
                      radius: 60,
                      backgroundColor: azul,
                      backgroundImage: _fotoLocal != null
                          ? FileImage(_fotoLocal!)
                              as ImageProvider<Object>
                          : (_fotoUrl.isNotEmpty &&
                                  _fotoUrl
                                      .startsWith('data:'))
                              ? MemoryImage(base64Decode(
                                      _fotoUrl
                                          .split(',')
                                          .last))
                                  as ImageProvider<Object>
                              : (_fotoUrl.isNotEmpty
                                  ? NetworkImage(_fotoUrl)
                                      as ImageProvider<Object>
                                  : null),
                      child: (_fotoLocal == null &&
                              _fotoUrl.isEmpty)
                          ? Text(
                              _nomeCtrl.text.isNotEmpty
                                  ? _nomeCtrl.text[0]
                                      .toUpperCase()
                                  : 'T',
                              style: TextStyle(
                                  fontSize: 50,
                                  color: _tc(),
                                  fontWeight:
                                      FontWeight.bold),
                            )
                          : null,
                    ),
                    Positioned(
                      bottom: 0,
                      right: 0,
                      child: CircleAvatar(
                        radius: 18,
                        backgroundColor: Colors.white,
                        child: Icon(Icons.camera_alt,
                            size: 18, color: azul),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 8),
            Text('Toca para alterar a foto',
                style: TextStyle(
                    color: _tc().withOpacity(0.4),
                    fontSize: 12)),
            const SizedBox(height: 22),
            _campo('Nome', _nomeCtrl,
                'Insira o seu nome...'),
            _campo(
                'Username (@)',
                _usernameCtrl,
                'ex: mestre_foco  (3-20 caracteres)',
                hint2:
                    'Letras, números, . e _ · Deve ser único'),
            _campo('Descrição', _descCtrl,
                'Escreva algo sobre si...',
                maxLines: 3),
            _campo(
                'Motivações para usar o Thoth',
                _motivosCtrl,
                'Ex: Melhorar a gestão de tempo...',
                maxLines: 3),
            // FIX: campo de citação adicionado
            _campo('Citação motivacional', _citacaoCtrl,
                'Ex: A persistência é o caminho do êxito'),
            const SizedBox(height: 20),
            if (widget.perfil.nomedeutilizador
                .isNotEmpty) ...[
              OutlinedButton.icon(
                onPressed: () {
                  final username =
                      widget.perfil.nomedeutilizador;
                  Clipboard.setData(
                      ClipboardData(text: '@$username'));
                  Share.share(
                    'Segue o meu progresso no Thoth! 📚\n'
                    'Pesquisa por @$username na aba de Amigos para me adicionares.',
                    subject:
                        'O meu perfil Thoth — @$username',
                  );
                },
                style: OutlinedButton.styleFrom(
                  foregroundColor: azul,
                  side: const BorderSide(color: azul),
                  minimumSize:
                      const Size(double.infinity, 48),
                  shape: RoundedRectangleBorder(
                      borderRadius:
                          BorderRadius.circular(12)),
                ),
                icon: const Icon(
                    Icons.ios_share_rounded,
                    size: 18),
                label: Text(
                    'Partilhar perfil  @${widget.perfil.nomedeutilizador}'),
              ),
              const SizedBox(height: 12),
            ],
            ElevatedButton(
              onPressed:
                  _aCarregarFoto ? null : _guardar,
              style: ElevatedButton.styleFrom(
                backgroundColor: azul,
                foregroundColor: Colors.white,
                minimumSize:
                    const Size(double.infinity, 52),
                shape: RoundedRectangleBorder(
                    borderRadius:
                        BorderRadius.circular(12)),
              ),
              child: const Text('GUARDAR PERFIL',
                  style: TextStyle(
                      fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _campo(
      String label,
      TextEditingController ctrl,
      String hint,
      {int maxLines = 1, String? hint2}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: TextField(
        controller: ctrl,
        maxLines: maxLines,
        style: TextStyle(color: _tc()),
        textCapitalization: maxLines == 1 && hint2 == null
            ? TextCapitalization.sentences
            : TextCapitalization.none,
        decoration: InputDecoration(
          labelText: label,
          hintText: hint,
          helperText: hint2,
          helperStyle: TextStyle(
              color: _tc().withOpacity(0.4),
              fontSize: 11),
          hintStyle: TextStyle(
              color: _tc().withOpacity(0.3)),
          labelStyle:
              const TextStyle(color: Color(0xFF1D81C7)),
          enabledBorder: const UnderlineInputBorder(
              borderSide:
                  BorderSide(color: Colors.white24)),
          focusedBorder: const UnderlineInputBorder(
              borderSide: BorderSide(
                  color: Color(0xFF1D81C7))),
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
  final String? todoBlocosJson;
  const TelaTodo(
      {super.key,
      required this.lista,
      this.todoBlocosJson});

  @override
  State<TelaTodo> createState() => _TelaTodoState();
}

class _TelaTodoState extends State<TelaTodo> {
  final TextEditingController _todoCtrl =
      TextEditingController();
  final TextEditingController _horaCtrl =
      TextEditingController();
  final TextEditingController _dataCtrl =
      TextEditingController();
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
    for (final key in _blocos.keys) {
      _blocos[key] = [];
    }
    _carregarBlocos();
  }

  FirebaseFirestore get _db => FirebaseFirestore.instance;
  String get _uid =>
      FirebaseAuth.instance.currentUser!.uid;
  CollectionReference get _todoCol =>
      _db.collection('users').doc(_uid).collection('todo');

  Future<void> _carregarBlocos() async {
    if (widget.todoBlocosJson != null) {
      try {
        final m = jsonDecode(widget.todoBlocosJson!)
            as Map<String, dynamic>;
        setState(() {
          for (final entry in m.entries) {
            if (_blocos.containsKey(entry.key)) {
              final raw = entry.value;
              if (raw is Map) {
                final list =
                    (raw['itens'] as List<dynamic>?) ??
                        [];
                _blocos[entry.key] = list
                    .map((e) => ItemTodo.fromJson(
                        e as Map<String, dynamic>))
                    .toList();
              }
            }
          }
        });
      } catch (e) {
        debugPrint('Erro ao ler blocos JSON: $e');
      }
      return;
    }
    try {
      final snap = await _todoCol.get();
      if (snap.docs.isNotEmpty) {
        setState(() {
          for (final doc in snap.docs) {
            if (_blocos.containsKey(doc.id)) {
              final data =
                  doc.data() as Map<String, dynamic>;
              final list =
                  (data['itens'] as List<dynamic>?) ??
                      [];
              _blocos[doc.id] = list
                  .map((e) => ItemTodo.fromJson(
                      e as Map<String, dynamic>))
                  .toList();
            }
          }
        });
      } else {
        setState(() => _blocos['Tarefas para hoje']!
            .addAll(widget.lista));
        await _guardarBlocos();
      }
    } catch (e) {
      debugPrint('Erro ao carregar blocos: $e');
    }
  }

  Future<void> _guardarBlocos() async {
    try {
      final batch = _db.batch();
      for (final entry in _blocos.entries) {
        batch.set(
          _todoCol.doc(entry.key),
          {
            'itens': entry.value
                .map((i) => i.toJson())
                .toList()
          },
        );
      }
      await batch.commit();
    } catch (e) {
      debugPrint('Erro ao guardar blocos: $e');
    }
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
    final hora = _horaCtrl.text.trim().isEmpty
        ? '--:--'
        : _horaCtrl.text.trim();
    final data = _dataCtrl.text.trim().isEmpty
        ? '--/--'
        : _dataCtrl.text.trim();
    setState(() {
      _blocos[_blocoSelecionado]!.add(ItemTodo(
        id: DateTime.now()
            .microsecondsSinceEpoch
            .toString(),
        texto: texto,
        dataHora: '$hora | $data',
        concluido: _blocoSelecionado == 'Acabadas',
      ));
      _todoCtrl.clear();
      _horaCtrl.clear();
      _dataCtrl.clear();
    });
    _guardarBlocos();
  }

  void _moverItem(ItemTodo item, String destino) {
    setState(() {
      for (final lista in _blocos.values) {
        lista.removeWhere((i) => i.id == item.id);
      }
      item.concluido = destino == 'Acabadas';
      _blocos[destino]!.add(item);
    });
    _guardarBlocos();
  }

  void _removerItem(ItemTodo item) {
    setState(() {
      for (final lista in _blocos.values) {
        lista.removeWhere((i) => i.id == item.id);
      }
    });
    _guardarBlocos();
  }

  void _alternarConcluido(ItemTodo item) {
    setState(() {
      item.concluido = !item.concluido;
      for (final lista in _blocos.values) {
        lista.removeWhere((i) => i.id == item.id);
      }
      _blocos[item.concluido
              ? 'Acabadas'
              : 'Por fazer!!']!
          .add(item);
    });
    _guardarBlocos();
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
              surface: Colors.black87),
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
              surface: Colors.black87),
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
          Container(
            width: double.infinity,
            color: const Color(0xFF0D6E9E),
            padding:
                const EdgeInsets.fromLTRB(20, 20, 20, 16),
            child: Column(
              crossAxisAlignment:
                  CrossAxisAlignment.start,
              children: [
                Text('To-do List',
                    style: TextStyle(
                        fontSize: 32,
                        fontWeight: FontWeight.bold,
                        color: _tc())),
                const SizedBox(height: 16),
                TextField(
                  controller: _todoCtrl,
                  style: TextStyle(color: _tc()),
                  textCapitalization:
                      TextCapitalization.sentences,
                  decoration: InputDecoration(
                    hintText: 'Nova tarefa...',
                    hintStyle: const TextStyle(
                        color: Colors.white54),
                    isDense: true,
                    enabledBorder:
                        const UnderlineInputBorder(
                            borderSide: BorderSide(
                                color: Colors.white30)),
                    focusedBorder: UnderlineInputBorder(
                        borderSide:
                            BorderSide(color: _tc())),
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
                            style:
                                TextStyle(color: _tc()),
                            decoration:
                                const InputDecoration(
                              hintText: 'Hora',
                              hintStyle: TextStyle(
                                  color:
                                      Colors.white54),
                              prefixIcon: Icon(
                                  Icons.access_time,
                                  color: Colors.white54,
                                  size: 18),
                              isDense: true,
                              enabledBorder:
                                  UnderlineInputBorder(
                                      borderSide:
                                          BorderSide(
                                              color: Colors
                                                  .white30)),
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
                            style:
                                TextStyle(color: _tc()),
                            decoration:
                                const InputDecoration(
                              hintText: 'Data',
                              hintStyle: TextStyle(
                                  color:
                                      Colors.white54),
                              prefixIcon: Icon(
                                  Icons.calendar_today,
                                  color: Colors.white54,
                                  size: 18),
                              isDense: true,
                              enabledBorder:
                                  UnderlineInputBorder(
                                      borderSide:
                                          BorderSide(
                                              color: Colors
                                                  .white30)),
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
                          style:
                              TextStyle(color: _tc()),
                          icon: const Icon(
                              Icons.arrow_drop_down,
                              color: Colors.white54),
                          items: _blocos.keys.map((b) {
                            return DropdownMenuItem(
                                value: b,
                                child: Text(b));
                          }).toList(),
                          onChanged: (v) {
                            if (v != null) {
                              setState(() =>
                                  _blocoSelecionado =
                                      v);
                            }
                          },
                        ),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.add_task,
                          color: Colors.white),
                      tooltip: 'Adicionar',
                      onPressed: _adicionarItem,
                    ),
                  ],
                ),
              ],
            ),
          ),
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
                  cor: _coresBlocos[entry.key] ??
                      Colors.grey,
                  onMover: (item) =>
                      _moverItem(item, entry.key),
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

  const _BlocoTodo(
      {required this.titulo,
      required this.itens,
      required this.cor,
      required this.onMover,
      required this.onToggle,
      required this.onRemover});

  @override
  Widget build(BuildContext context) {
    return DragTarget<ItemTodo>(
      onAcceptWithDetails: (details) =>
          onMover(details.data),
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
            crossAxisAlignment:
                CrossAxisAlignment.start,
            children: [
              Text(titulo,
                  style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                      color: Colors.black),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis),
              const SizedBox(height: 8),
              Expanded(
                child: itens.isEmpty
                    ? Center(
                        child: Text('Vazio',
                            style: TextStyle(
                                color: Colors.black
                                    .withOpacity(0.3),
                                fontSize: 12)))
                    : ListView(
                        children: itens
                            .map((item) =>
                                _ItemArrastaveel(
                                    item: item,
                                    onToggle: onToggle,
                                    onRemover:
                                        onRemover))
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

  const _ItemArrastaveel(
      {required this.item,
      required this.onToggle,
      required this.onRemover});

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
            padding: const EdgeInsets.symmetric(
                horizontal: 10, vertical: 8),
            decoration: BoxDecoration(
              color: _tc(),
              borderRadius: BorderRadius.circular(10),
              boxShadow: const [
                BoxShadow(
                    color: Colors.black38,
                    blurRadius: 14,
                    offset: Offset(0, 6))
              ],
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.drag_indicator,
                    size: 14, color: Colors.black38),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(item.texto,
                      style: const TextStyle(
                          fontSize: 13,
                          color: Colors.black87,
                          fontWeight: FontWeight.w600),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis),
                ),
              ],
            ),
          ),
        ),
      ),
      childWhenDragging:
          Opacity(opacity: 0.25, child: _buildUI()),
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
            const Icon(Icons.drag_indicator,
                size: 13, color: Colors.black26),
            const SizedBox(width: 4),
            Container(
              width: 14,
              height: 14,
              decoration: BoxDecoration(
                color: item.concluido
                    ? Colors.black54
                    : Colors.transparent,
                border: Border.all(
                    color: Colors.black54, width: 1.5),
                borderRadius: BorderRadius.circular(2),
              ),
              child: item.concluido
                  ? const Icon(Icons.check,
                      size: 10, color: Colors.white)
                  : null,
            ),
            const SizedBox(width: 6),
            Expanded(
              child: Text(item.texto,
                  style: TextStyle(
                      fontSize: 13,
                      color: Colors.black87,
                      decoration: item.concluido
                          ? TextDecoration.lineThrough
                          : TextDecoration.none),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis),
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

    final totalFoco = sessoes.fold<int>(
        0, (s, e) => s + e.tempoFocoSegundos);
    final totalCiclos = sessoes.fold<int>(
        0, (s, e) => s + e.ciclosConcluidos);
    final streak = StreakInfo.calcular(sessoes);

    final contagem = <String, int>{};
    for (final s in sessoes) {
      contagem[s.tarefaNome] =
          (contagem[s.tarefaNome] ?? 0) +
              s.tempoFocoSegundos;
    }
    String? tarefaMaisEstudada;
    if (contagem.isNotEmpty) {
      tarefaMaisEstudada = contagem.entries
          .reduce(
              (a, b) => a.value > b.value ? a : b)
          .key;
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Insights'),
        actions: [
          IconButton(
            icon: const Icon(Icons.share_outlined),
            tooltip: 'Partilhar',
            onPressed: () => _partilhar(context, streak,
                totalFoco, totalCiclos, sessoes.length),
          ),
        ],
        bottom: const PreferredSize(
          preferredSize: Size.fromHeight(1),
          child: Divider(color: azul, height: 1),
        ),
      ),
      body: sessoes.isEmpty
          ? Center(
              child: Column(
                mainAxisAlignment:
                    MainAxisAlignment.center,
                children: [
                  Icon(Icons.bar_chart,
                      size: 64,
                      color: _tc().withOpacity(0.15)),
                  const SizedBox(height: 16),
                  Text('Nenhuma sessão concluída',
                      style: TextStyle(
                          color: _tc().withOpacity(0.4),
                          fontSize: 18)),
                  const SizedBox(height: 8),
                  Text(
                      'Completa uma tarefa para ver os insights',
                      style: TextStyle(
                          color:
                              _tc().withOpacity(0.25),
                          fontSize: 13)),
                ],
              ),
            )
          : SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment:
                    CrossAxisAlignment.start,
                children: [
                  GestureDetector(
                    onTap: () => showDialog(
                      context: context,
                      builder: (_) =>
                          _StreakDialog(streak: streak),
                    ),
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(16),
                      margin: const EdgeInsets.only(
                          bottom: 16),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: streak.acendeuHoje
                              ? [
                                  const Color(0xFFFF6D00)
                                      .withOpacity(0.15),
                                  const Color(0xFFFFCC02)
                                      .withOpacity(0.08)
                                ]
                              : [
                                  azul.withOpacity(0.08),
                                  azul.withOpacity(0.04)
                                ],
                        ),
                        border: Border.all(
                          color: streak.acendeuHoje
                              ? const Color(0xFFFF6D00)
                                  .withOpacity(0.5)
                              : azul.withOpacity(0.3),
                        ),
                        borderRadius:
                            BorderRadius.circular(14),
                      ),
                      child: Row(
                        children: [
                          const Text('🔥',
                              style: TextStyle(
                                  fontSize: 36)),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment:
                                  CrossAxisAlignment
                                      .start,
                              children: [
                                Text(
                                    '${streak.dias} dias seguidos',
                                    style: TextStyle(
                                        color: _tc(),
                                        fontSize: 20,
                                        fontWeight:
                                            FontWeight
                                                .bold)),
                                Text(
                                    streak.acendeuHoje
                                        ? 'Streak activa hoje! 💪'
                                        : 'Estuda hoje para manter a streak',
                                    style: TextStyle(
                                        color: _tc54(),
                                        fontSize: 12)),
                              ],
                            ),
                          ),
                          const Icon(
                              Icons.chevron_right,
                              color: Colors.white38),
                        ],
                      ),
                    ),
                  ),
                  const Text('Conquistas',
                      style: TextStyle(
                          color: azul,
                          fontSize: 16,
                          fontWeight: FontWeight.bold)),
                  const SizedBox(height: 12),
                  SizedBox(
                    height: 90,
                    child: ListView(
                      scrollDirection: Axis.horizontal,
                      children:
                          StreakInfo.conquistas.map((c) {
                        final conquistada =
                            streak.dias >=
                                (c['dias'] as int);
                        return Container(
                          width: 72,
                          margin: const EdgeInsets.only(
                              right: 10),
                          padding:
                              const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: conquistada
                                ? const Color(0xFFFF6D00)
                                    .withOpacity(0.12)
                                : _tc().withOpacity(0.04),
                            border: Border.all(
                                color: conquistada
                                    ? const Color(
                                            0xFFFF6D00)
                                        .withOpacity(0.6)
                                    : _tc()
                                        .withOpacity(0.1)),
                            borderRadius:
                                BorderRadius.circular(12),
                          ),
                          child: Column(
                            mainAxisAlignment:
                                MainAxisAlignment.center,
                            children: [
                              Text(c['icon'] as String,
                                  style: const TextStyle(
                                      fontSize: 24)),
                              const SizedBox(height: 4),
                              Text(c['label'] as String,
                                  style: TextStyle(
                                      fontSize: 9,
                                      color: conquistada
                                          ? _tc()
                                          : _tc38(),
                                      fontWeight:
                                          conquistada
                                              ? FontWeight
                                                  .bold
                                              : FontWeight
                                                  .normal),
                                  textAlign:
                                      TextAlign.center),
                            ],
                          ),
                        );
                      }).toList(),
                    ),
                  ),
                  const SizedBox(height: 20),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: () => _partilhar(
                          context,
                          streak,
                          totalFoco,
                          totalCiclos,
                          sessoes.length),
                      icon: const Icon(
                          Icons.share_outlined,
                          color: azul,
                          size: 18),
                      label: const Text(
                          'Partilhar os meus insights',
                          style:
                              TextStyle(color: azul)),
                      style: OutlinedButton.styleFrom(
                        side: BorderSide(
                            color:
                                azul.withOpacity(0.5)),
                        shape: RoundedRectangleBorder(
                            borderRadius:
                                BorderRadius.circular(
                                    10)),
                        padding:
                            const EdgeInsets.symmetric(
                                vertical: 12),
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                  Row(
                    children: [
                      Expanded(
                        child: _cardInsight(
                          icon: Icons.timer_outlined,
                          valor:
                              _formatarTempo(totalFoco),
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
                          valor:
                              tarefaMaisEstudada ?? '—',
                          label: 'Mais estudada',
                          pequeno: true,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 30),
                  if (contagem.isNotEmpty) ...[
                    const Text('Tempo de foco por tarefa',
                        style: TextStyle(
                            color: Color(0xFF1D81C7),
                            fontSize: 16,
                            fontWeight:
                                FontWeight.bold)),
                    const SizedBox(height: 16),
                    _GraficoBarras(contagem: contagem),
                    const SizedBox(height: 24),
                  ],
                  const Text('Histórico de Sessões',
                      style: TextStyle(
                          color: azul,
                          fontSize: 16,
                          fontWeight: FontWeight.bold)),
                  const SizedBox(height: 12),
                  ...sessoes.reversed
                      .map((s) => _linhaHistorico(s)),
                ],
              ),
            ),
    );
  }

  void _partilhar(
      BuildContext context,
      StreakInfo streak,
      int totalFoco,
      int totalCiclos,
      int totalSessoes) {
    final keyInsights = GlobalKey();
    final contagem = <String, int>{};
    for (final s in sessoes) {
      contagem[s.tarefaNome] =
          (contagem[s.tarefaNome] ?? 0) +
              s.tempoFocoSegundos;
    }
    String? tarefaMaisEstudada;
    if (contagem.isNotEmpty) {
      tarefaMaisEstudada = contagem.entries
          .reduce(
              (a, b) => a.value > b.value ? a : b)
          .key;
    }

    final texto = [
      '🔥 ${streak.dias} dias de streak no THOTH!',
      '⏱ ${_formatarTempo(totalFoco)} de foco total',
      '🔁 $totalCiclos ciclos concluídos',
      '✅ $totalSessoes sessões completadas',
      '',
      '#Thoth #Produtividade #Estudo #Pomodoro',
    ].join('\n');

    showDialog(
      context: context,
      builder: (_) => _DialogoPartilha(
        textoPartilha: texto,
        cartao: RepaintBoundary(
          key: keyInsights,
          child: _InsightsShareCard(
            streakDias: streak.dias,
            acendeuHoje: streak.acendeuHoje,
            totalFocoSegundos: totalFoco,
            totalCiclos: totalCiclos,
            totalSessoes: totalSessoes,
            tarefaMaisEstudada: tarefaMaisEstudada,
          ),
        ),
        aoPartilhar: () async {
          await _registarPartilhaFirestore(
            tipo: 'insights',
            streakDias: streak.dias,
            totalFoco: totalFoco,
            totalCiclos: totalCiclos,
            totalSessoes: totalSessoes,
          );
          await _partilharImagem(
              key: keyInsights, texto: texto);
        },
      ),
    );
  }

  Widget _cardInsight(
      {required IconData icon,
      required String valor,
      required String label,
      bool pequeno = false}) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        border: Border.all(
            color: const Color(0xFF1D81C7)
                .withOpacity(0.4)),
        borderRadius: BorderRadius.circular(12),
        color:
            const Color(0xFF1D81C7).withOpacity(0.05),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon,
              color: const Color(0xFF1D81C7), size: 22),
          const SizedBox(height: 8),
          Text(valor,
              style: TextStyle(
                  color: _tc(),
                  fontSize: pequeno ? 14 : 22,
                  fontWeight: FontWeight.bold),
              maxLines: 2,
              overflow: TextOverflow.ellipsis),
          const SizedBox(height: 4),
          Text(label,
              style: TextStyle(
                  color: _tc().withOpacity(0.4),
                  fontSize: 12)),
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
        border:
            Border.all(color: _tc().withOpacity(0.1)),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          const Icon(Icons.check_circle,
              color: Color(0xFF1D81C7), size: 20),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment:
                  CrossAxisAlignment.start,
              children: [
                Text(s.tarefaNome,
                    style: TextStyle(
                        color: _tc(),
                        fontWeight: FontWeight.bold,
                        fontSize: 14)),
                Text(
                    '${s.ciclosConcluidos} ciclos · ${_formatarTempo(s.tempoFocoSegundos)} foco',
                    style: TextStyle(
                        color: _tc().withOpacity(0.5),
                        fontSize: 12)),
              ],
            ),
          ),
          Text(data,
              style: TextStyle(
                  color: _tc().withOpacity(0.3),
                  fontSize: 11)),
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
            Center(
              child: Container(
                width: 80,
                height: 80,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border:
                      Border.all(color: azul, width: 2),
                ),
                child: const Icon(
                    Icons.timer_outlined,
                    color: azul,
                    size: 40),
              ),
            ),
            const SizedBox(height: 30),
            const Text('O que é o Pomodoro?',
                style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    color: azul)),
            const SizedBox(height: 12),
            const Text(
                'É uma técnica de gestão de tempo que divide o estudo ou trabalho em blocos curtos de foco intenso, intercalados com descansos breves.',
                style: TextStyle(
                    fontSize: tamanhoTexto,
                    height: 1.6,
                    color: Colors.white)),
            const SizedBox(height: 28),
            const Text('Como funciona:',
                style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: azul)),
            const SizedBox(height: 12),
            _passo(1, 'Define uma tarefa a completar.'),
            _passo(2,
                'Estuda/trabalha 25 minutos sem interrupções (1 Pomodoro).'),
            _passo(
                3, 'Faz uma pausa de 5 minutos.'),
            _passo(
                4, 'Repete os ciclos necessários.'),
            _passo(5,
                'A cada 4 ciclos, faz uma pausa longa de 15–30 min.'),
            const SizedBox(height: 28),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                color: azul.withOpacity(0.08),
                border: Border.all(
                    color: azul.withOpacity(0.3)),
              ),
              child: RichText(
                text: TextSpan(
                  style: TextStyle(
                      fontSize: tamanhoTexto,
                      height: 1.6,
                      color: _tc()),
                  children: const [
                    TextSpan(
                        text: 'Objetivo: ',
                        style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: azul)),
                    TextSpan(
                        text:
                            'manter a concentração, evitar fadiga mental e aumentar a produtividade através de intervalos regulares.'),
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
                    height: 1.6)),
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
            margin: const EdgeInsets.only(
                right: 12, top: 2),
            decoration: const BoxDecoration(
              color: Color(0xFF1D81C7),
              shape: BoxShape.circle,
            ),
            child: Center(
              child: Text('$num',
                  style: TextStyle(
                      color: _tc(),
                      fontSize: 13,
                      fontWeight: FontWeight.bold)),
            ),
          ),
          Expanded(
            child: Text(texto,
                style: TextStyle(
                    color: _tc(),
                    fontSize: 15.5,
                    height: 1.5)),
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
    Color(0xFF4CAF50),
    Color(0xFF9C27B0),
    Color(0xFFFF9800),
    Color(0xFFFFEB3B),
    Color(0xFF2196F3),
    Color(0xFFE91E63),
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
    final maxVal = entries
        .map((e) => e.value)
        .reduce((a, b) => a > b ? a : b);
    const maxH = 130.0;

    return SizedBox(
      height: maxH + 50,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Column(
            mainAxisAlignment:
                MainAxisAlignment.spaceBetween,
            children: [
              Text(_fmt(maxVal),
                  style: TextStyle(
                      fontSize: 9, color: _tc38())),
              Text(_fmt(maxVal ~/ 2),
                  style: TextStyle(
                      fontSize: 9, color: _tc38())),
              Text('0',
                  style: TextStyle(
                      fontSize: 9, color: _tc38())),
              const SizedBox(height: 28),
            ],
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Row(
              crossAxisAlignment:
                  CrossAxisAlignment.end,
              mainAxisAlignment:
                  MainAxisAlignment.spaceEvenly,
              children: entries.asMap().entries.map((e) {
                final idx = e.key;
                final kv = e.value;
                final ratio = maxVal == 0
                    ? 0.0
                    : kv.value / maxVal;
                final barH =
                    (ratio * maxH).clamp(4.0, maxH);
                final cor = _cores[idx % _cores.length];
                final label = kv.key.length > 7
                    ? kv.key.substring(0, 7)
                    : kv.key;
                return Column(
                  mainAxisAlignment:
                      MainAxisAlignment.end,
                  children: [
                    Text(_fmt(kv.value),
                        style: TextStyle(
                            color: cor,
                            fontSize: 9,
                            fontWeight:
                                FontWeight.bold)),
                    const SizedBox(height: 3),
                    Container(
                      width: 32,
                      height: barH,
                      decoration: BoxDecoration(
                        color: cor,
                        borderRadius:
                            const BorderRadius.vertical(
                                top: Radius.circular(5)),
                      ),
                    ),
                    const SizedBox(height: 5),
                    SizedBox(
                      width: 44,
                      child: Text(label,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                              color: Colors.white54,
                              fontSize: 9),
                          maxLines: 2,
                          overflow:
                              TextOverflow.ellipsis),
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
  State<TelaDefinicoes> createState() =>
      _TelaDefinicoesState();
}

class _TelaDefinicoesState
    extends State<TelaDefinicoes> {
  bool _notifs = true;
  bool _privado = false;
  bool _modoDND = false;
  bool _loadingPrefs = true;

  static const azul = Color(0xFF1D81C7);

  FirebaseFirestore get _db => FirebaseFirestore.instance;
  String get _uid =>
      FirebaseAuth.instance.currentUser!.uid;
  DocumentReference get _configDoc =>
      _db.collection('users').doc(_uid).collection('config').doc('dados');

  @override
  void initState() {
    super.initState();
    _carregarPreferencias();
  }

  Future<void> _carregarPreferencias() async {
    try {
      final snap = await _configDoc.get();
      if (snap.exists && mounted) {
        final d = snap.data() as Map<String, dynamic>;
        setState(() {
          _notifs = d['notificacoes'] as bool? ?? true;
          _privado =
              d['contaPrivada'] as bool? ?? false;
          _modoDND =
              d['modoDNDAtivo'] as bool? ?? false;
        });
      }
    } catch (_) {}
    if (mounted) setState(() => _loadingPrefs = false);
  }

  Future<void> _guardarPreferencia(
      String campo, bool valor) async {
    try {
      await _configDoc
          .set({campo: valor}, SetOptions(merge: true));
      if (campo == 'notificacoes') {
        if (valor) {
          await _agendarNotificacaoDiaria();
        } else {
          await _notifPlugin.cancelAll();
        }
      }
    } catch (e) {
      debugPrint(
          'Erro ao guardar preferência $campo: $e');
    }
  }

  String get _account {
    final user = FirebaseAuth.instance.currentUser;
    return user?.displayName ?? 'Utilizador';
  }

  String get _email =>
      FirebaseAuth.instance.currentUser?.email ?? '';

  void _confirmarLogout() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: temaEscuro.value
            ? const Color(0xFF111111)
            : Colors.white,
        title: Text('Terminar sessão?',
            style: TextStyle(
                color: temaEscuro.value
                    ? Colors.white
                    : Colors.black87)),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancelar')),
          TextButton(
            onPressed: () async {
              await GoogleSignIn().signOut();
              await FirebaseAuth.instance.signOut();
              if (context.mounted) {
                Navigator.pop(ctx);
              }
            },
            child: const Text('Log out',
                style: TextStyle(color: azul)),
          ),
        ],
      ),
    );
  }

  void _confirmarEliminar() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: temaEscuro.value
            ? const Color(0xFF111111)
            : Colors.white,
        title: const Text('Eliminar conta?',
            style:
                TextStyle(color: Colors.redAccent)),
        content: Text('Esta acção é irreversível.',
            style: TextStyle(
                color: temaEscuro.value
                    ? Colors.white70
                    : Colors.black54)),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancelar')),
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              Navigator.pop(context);
            },
            child: const Text('Eliminar',
                style: TextStyle(
                    color: Colors.redAccent)),
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
        final bg =
            escuro ? Colors.black : Colors.white;
        final fg =
            escuro ? Colors.white : Colors.black87;
        final fgMuted =
            escuro ? Colors.white54 : Colors.black45;
        final border =
            escuro ? Colors.white12 : Colors.black12;
        final tileBg = escuro
            ? const Color(0xFF111111)
            : const Color(0xFFF5F5F5);

        return Scaffold(
          backgroundColor: bg,
          appBar: AppBar(
            backgroundColor: bg,
            foregroundColor: fg,
            title: Text('Definições',
                style: TextStyle(
                    color: fg,
                    fontWeight: FontWeight.bold)),
            bottom: const PreferredSize(
              preferredSize: Size.fromHeight(1),
              child: Divider(color: azul, height: 1),
            ),
          ),
          body: _loadingPrefs
              ? const Center(
                  child:
                      CircularProgressIndicator(
                          color: azul))
              : ListView(
                  padding: const EdgeInsets.all(20),
                  children: [
                    Text('APARÊNCIA',
                        style: const TextStyle(
                            color: azul,
                            fontSize: 12,
                            fontWeight:
                                FontWeight.bold,
                            letterSpacing: 1.5)),
                    const SizedBox(height: 10),
                    Container(
                      decoration: BoxDecoration(
                          color: tileBg,
                          borderRadius:
                              BorderRadius.circular(14),
                          border: Border.all(
                              color: border)),
                      child: Padding(
                        padding:
                            const EdgeInsets.symmetric(
                                horizontal: 18,
                                vertical: 14),
                        child: Row(
                          children: [
                            AnimatedSwitcher(
                              duration: const Duration(
                                  milliseconds: 250),
                              child: Icon(
                                escuro
                                    ? Icons
                                        .dark_mode_outlined
                                    : Icons
                                        .light_mode_outlined,
                                key: ValueKey(escuro),
                                color: azul,
                                size: 26,
                              ),
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              child: Column(
                                crossAxisAlignment:
                                    CrossAxisAlignment
                                        .start,
                                children: [
                                  Text(
                                      escuro
                                          ? 'Tema escuro'
                                          : 'Tema claro',
                                      style: TextStyle(
                                          color: fg,
                                          fontSize: 16,
                                          fontWeight:
                                              FontWeight
                                                  .w600)),
                                  Text(
                                      escuro
                                          ? 'Fundo preto'
                                          : 'Fundo branco',
                                      style: TextStyle(
                                          color: fgMuted,
                                          fontSize: 12)),
                                ],
                              ),
                            ),
                            GestureDetector(
                              onTap: () =>
                                  temaEscuro.value =
                                      !escuro,
                              child: AnimatedContainer(
                                duration: const Duration(
                                    milliseconds: 250),
                                width: 52,
                                height: 28,
                                decoration: BoxDecoration(
                                  borderRadius:
                                      BorderRadius
                                          .circular(14),
                                  color: escuro
                                      ? azul
                                      : Colors
                                          .grey.shade300,
                                ),
                                child: AnimatedAlign(
                                  duration: const Duration(
                                      milliseconds: 250),
                                  alignment: escuro
                                      ? Alignment
                                          .centerRight
                                      : Alignment
                                          .centerLeft,
                                  child: Padding(
                                    padding:
                                        const EdgeInsets
                                            .all(3),
                                    child: Container(
                                      width: 22,
                                      height: 22,
                                      decoration:
                                          BoxDecoration(
                                              shape: BoxShape
                                                  .circle,
                                              color:
                                                  _tc(),
                                              boxShadow: const [
                                            BoxShadow(
                                                color: Colors
                                                    .black26,
                                                blurRadius:
                                                    3)
                                          ]),
                                      child: Icon(
                                          escuro
                                              ? Icons
                                                  .nightlight_round
                                              : Icons
                                                  .wb_sunny_rounded,
                                          size: 13,
                                          color: escuro
                                              ? azul
                                              : Colors
                                                  .orange),
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
                      decoration: BoxDecoration(
                          color: tileBg,
                          borderRadius:
                              BorderRadius.circular(14),
                          border: Border.all(
                              color: border)),
                      child: Row(children: [
                        _MiniPreview(
                            dark: true,
                            selected: escuro,
                            onTap: () =>
                                temaEscuro.value = true,
                            label: 'Escuro'),
                        const SizedBox(width: 12),
                        _MiniPreview(
                            dark: false,
                            selected: !escuro,
                            onTap: () =>
                                temaEscuro.value = false,
                            label: 'Claro'),
                      ]),
                    ),
                    const SizedBox(height: 28),
                    Text('CONTA',
                        style: const TextStyle(
                            color: azul,
                            fontSize: 12,
                            fontWeight:
                                FontWeight.bold,
                            letterSpacing: 1.5)),
                    const SizedBox(height: 10),
                    _tile(
                        Icons.account_circle_outlined,
                        'Account',
                        _account,
                        fg,
                        fgMuted,
                        tileBg,
                        border,
                        onTap: () {},
                        readOnly: true),
                    _tile(
                        Icons.mail_outline,
                        'Email',
                        _email,
                        fg,
                        fgMuted,
                        tileBg,
                        border,
                        onTap: () {},
                        readOnly: true),
                    _tileToggle(
                        Icons.notifications_outlined,
                        'Notificações',
                        _notifs,
                        fg,
                        fgMuted,
                        tileBg,
                        border,
                        onChanged: (v) {
                          setState(() => _notifs = v);
                          _guardarPreferencia(
                              'notificacoes', v);
                        }),
                    _tileToggle(
                        Icons.lock_outline,
                        'Privacidade',
                        _privado,
                        fg,
                        fgMuted,
                        tileBg,
                        border,
                        onChanged: (v) {
                          setState(() => _privado = v);
                          _guardarPreferencia(
                              'contaPrivada', v);
                        }),
                    _tileToggle(
                        Icons
                            .do_not_disturb_on_outlined,
                        'Não perturbar durante o timer',
                        _modoDND,
                        fg,
                        fgMuted,
                        tileBg,
                        border,
                        onChanged: (v) {
                          setState(() => _modoDND = v);
                          _guardarPreferencia(
                              'modoDNDAtivo', v);
                        }),
                    _tile(Icons.logout, 'Log out', null,
                        fg, fgMuted, tileBg, border,
                        onTap: _confirmarLogout),
                    const SizedBox(height: 8),
                    _tile(
                        Icons.delete_outline,
                        'Eliminar conta!',
                        null,
                        Colors.redAccent,
                        Colors.redAccent.withOpacity(0.6),
                        Colors.red.withOpacity(0.04),
                        Colors.redAccent.withOpacity(0.25),
                        onTap: _confirmarEliminar,
                        bold: true),
                  ],
                ),
        );
      },
    );
  }

  Widget _tile(
      IconData icon,
      String titulo,
      String? valor,
      Color fg,
      Color fgMuted,
      Color bg,
      Color border,
      {required VoidCallback onTap,
      bool bold = false,
      bool readOnly = false}) {
    return GestureDetector(
      onTap: readOnly ? null : onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(
            horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: border)),
        child: Row(children: [
          Icon(icon,
              color:
                  bold ? Colors.redAccent : azul,
              size: 22),
          const SizedBox(width: 14),
          Expanded(
              child: Text(titulo,
                  style: TextStyle(
                      color: fg,
                      fontSize: 15,
                      fontWeight: bold
                          ? FontWeight.bold
                          : FontWeight.normal))),
          if (valor != null)
            Flexible(
              child: Text(valor,
                  style: TextStyle(
                      color: fgMuted, fontSize: 13),
                  overflow: TextOverflow.ellipsis,
                  maxLines: 1,
                  textAlign: TextAlign.end),
            )
          else if (!bold && !readOnly)
            Icon(Icons.chevron_right,
                color: fgMuted, size: 20),
        ]),
      ),
    );
  }

  Widget _tileToggle(
      IconData icon,
      String titulo,
      bool valor,
      Color fg,
      Color fgMuted,
      Color bg,
      Color border,
      {required ValueChanged<bool> onChanged}) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(
          horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: border)),
      child: Row(children: [
        Icon(icon, color: azul, size: 22),
        const SizedBox(width: 14),
        Expanded(
            child: Text(titulo,
                style: TextStyle(
                    color: fg, fontSize: 15))),
        Switch(
            value: valor,
            onChanged: onChanged,
            activeColor: azul),
      ]),
    );
  }
}

class _MiniPreview extends StatelessWidget {
  final bool dark;
  final bool selected;
  final VoidCallback onTap;
  final String label;
  const _MiniPreview(
      {required this.dark,
      required this.selected,
      required this.onTap,
      required this.label});

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
            color:
                dark ? Colors.black : Colors.white,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
                color: selected
                    ? azul
                    : Colors.transparent,
                width: 2),
            boxShadow: const [
              BoxShadow(
                  color: Colors.black26,
                  blurRadius: 6,
                  offset: Offset(0, 2))
            ],
          ),
          child: Column(
            children: [
              Container(
                  height: 7,
                  width: 55,
                  margin: const EdgeInsets.only(
                      bottom: 5),
                  decoration: BoxDecoration(
                      color: azul,
                      borderRadius:
                          BorderRadius.circular(4))),
              Container(
                  height: 4,
                  width: 45,
                  margin: const EdgeInsets.only(
                      bottom: 4),
                  decoration: BoxDecoration(
                      color: dark
                          ? Colors.white24
                          : Colors.black26,
                      borderRadius:
                          BorderRadius.circular(3))),
              Container(
                  height: 4,
                  width: 35,
                  decoration: BoxDecoration(
                      color: dark
                          ? Colors.white12
                          : Colors.black12,
                      borderRadius:
                          BorderRadius.circular(3))),
              const SizedBox(height: 7),
              Text(label,
                  style: TextStyle(
                      color: dark
                          ? Colors.white70
                          : Colors.black54,
                      fontSize: 11,
                      fontWeight: FontWeight.w600)),
              if (selected)
                const Padding(
                    padding:
                        EdgeInsets.only(top: 3),
                    child: Icon(Icons.check_circle,
                        color: azul, size: 13)),
            ],
          ),
        ),
      ),
    );
  }
}

// =============================================================================
// TELA AMIGOS
// =============================================================================

class TelaAmigos extends StatefulWidget {
  final String uid;
  const TelaAmigos({super.key, required this.uid});

  @override
  State<TelaAmigos> createState() =>
      _TelaAmigosState();
}

class _TelaAmigosState extends State<TelaAmigos> {
  static const azul = Color(0xFF1D81C7);
  final FirebaseFirestore _db =
      FirebaseFirestore.instance;

  List<Map<String, dynamic>> _amigos = [];
  List<Map<String, dynamic>> _pedidos = [];
  bool _loading = true;
  final TextEditingController _searchCtrl =
      TextEditingController();
  List<Map<String, dynamic>> _resultados = [];
  bool _searching = false;
  StreamSubscription<QuerySnapshot>? _pedidosSub;

  @override
  void initState() {
    super.initState();
    _carregarAmigos();
    _pedidosSub = _db
        .collection('pedidos_amizade')
        .where('para', isEqualTo: widget.uid)
        .snapshots()
        .listen((snap) async {
      final pedidos = <Map<String, dynamic>>[];
      for (final doc in snap.docs) {
        final estado =
            doc.data()['estado'] as String? ?? '';
        if (estado != 'pendente') continue;
        final remetenteUid =
            doc.data()['de'] as String? ?? '';
        if (remetenteUid.isEmpty) continue;
        try {
          final perfilSnap = await _db
              .collection('users')
              .doc(remetenteUid)
              .collection('perfil')
              .doc('dados')
              .get();
          final perfil = perfilSnap.exists
              ? PerfilUsuario.fromJson(
                  perfilSnap.data()!)
              : PerfilUsuario();
          pedidos.add({
            'uid': remetenteUid,
            'perfil': perfil,
            'docId': doc.id
          });
        } catch (_) {}
      }
      if (mounted) setState(() => _pedidos = pedidos);
    });
  }

  @override
  void dispose() {
    _pedidosSub?.cancel();
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _carregarAmigos() async {
    setState(() => _loading = true);
    try {
      final amigosSnap = await _db
          .collection('users')
          .doc(widget.uid)
          .collection('amigos')
          .where('estado', isEqualTo: 'aceite')
          .get();

      final amigos = <Map<String, dynamic>>[];
      for (final doc in amigosSnap.docs) {
        final amigoUid = doc.id;
        final perfilSnap = await _db
            .collection('users')
            .doc(amigoUid)
            .collection('perfil')
            .doc('dados')
            .get();
        final sessoesSnap = await _db
            .collection('users')
            .doc(amigoUid)
            .collection('sessoes')
            .orderBy('dataConclusao')
            .get();
        final sessoes = sessoesSnap.docs
            .map((d) => SessaoConcluida.fromJson(
                d.data()))
            .toList();
        final streak = StreakInfo.calcular(sessoes);
        final totalFoco = sessoes.fold<int>(
            0, (s, e) => s + e.tempoFocoSegundos);
        final perfil = perfilSnap.exists
            ? PerfilUsuario.fromJson(
                perfilSnap.data()!)
            : PerfilUsuario();
        amigos.add({
          'uid': amigoUid,
          'perfil': perfil,
          'streak': streak,
          'totalFoco': totalFoco,
          'totalSessoes': sessoes.length,
        });
      }

      if (mounted) {
        setState(() {
          _amigos = amigos;
          _loading = false;
        });
      }
    } catch (e) {
      debugPrint('Erro ao carregar amigos: $e');
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _pesquisar(String query) async {
    if (query.trim().isEmpty) {
      setState(() => _resultados = []);
      return;
    }
    setState(() => _searching = true);
    try {
      final q = query
          .trim()
          .toLowerCase()
          .replaceFirst(RegExp(r'^@'), '');
      final results = <Map<String, dynamic>>[];

      final usernameDoc = await _db
          .collection('usernames')
          .doc(q)
          .get();
      if (usernameDoc.exists) {
        final uid =
            usernameDoc.data()!['uid'] as String? ??
                '';
        if (uid.isNotEmpty && uid != widget.uid) {
          final perfilSnap = await _db
              .collection('users')
              .doc(uid)
              .collection('perfil')
              .doc('dados')
              .get();
          if (perfilSnap.exists) {
            final perfil = PerfilUsuario.fromJson(
                perfilSnap.data()!);
            final jaAmigo = _amigos
                .any((a) => a['uid'] == uid);
            final jaPedido = _pedidos
                .any((p) => p['uid'] == uid);
            results.add({
              'uid': uid,
              'perfil': perfil,
              'jaAmigo': jaAmigo,
              'jaPedido': jaPedido
            });
          }
        }
      }

      if (q.length >= 2) {
        final snap =
            await _db.collection('usernames').get();
        for (final doc in snap.docs) {
          final uid =
              doc.data()['uid'] as String? ?? '';
          if (uid.isEmpty || uid == widget.uid) {
            continue;
          }
          if (results.any((r) => r['uid'] == uid)) {
            continue;
          }
          final nome = (doc.data()['nome'] as String? ??
                  '')
              .toLowerCase();
          final username = (doc.data()[
                      'nomedeutilizador'] as String? ??
                  '')
              .toLowerCase();
          if (!nome.contains(q) &&
              !username.contains(q)) continue;
          final perfilSnap = await _db
              .collection('users')
              .doc(uid)
              .collection('perfil')
              .doc('dados')
              .get();
          if (!perfilSnap.exists) continue;
          final perfil = PerfilUsuario.fromJson(
              perfilSnap.data()!);
          final jaAmigo =
              _amigos.any((a) => a['uid'] == uid);
          final jaPedido =
              _pedidos.any((p) => p['uid'] == uid);
          results.add({
            'uid': uid,
            'perfil': perfil,
            'jaAmigo': jaAmigo,
            'jaPedido': jaPedido
          });
        }
      }

      if (mounted) {
        setState(() {
          _resultados = results;
          _searching = false;
        });
      }
    } catch (e) {
      debugPrint('Erro na pesquisa: $e');
      if (mounted) setState(() => _searching = false);
    }
  }

  Future<void> _enviarPedido(String amigoUid) async {
    try {
      await _db.collection('pedidos_amizade').add({
        'de': widget.uid,
        'para': amigoUid,
        'estado': 'pendente',
        'data': FieldValue.serverTimestamp(),
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
                content:
                    Text('Pedido de amizade enviado!')));
        setState(() {
          for (final r in _resultados) {
            if (r['uid'] == amigoUid) {
              r['jaPedido'] = true;
            }
          }
        });
      }
    } catch (e) {
      debugPrint('Erro ao enviar pedido: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
                content: Text(
                    'Erro ao enviar pedido. Tenta novamente.'),
                backgroundColor: Colors.redAccent));
      }
    }
  }

  Future<void> _aceitarPedido(
      String remetenteUid, String docId) async {
    try {
      final batch = _db.batch();
      batch.set(
        _db
            .collection('users')
            .doc(widget.uid)
            .collection('amigos')
            .doc(remetenteUid),
        {'estado': 'aceite'},
      );
      batch.set(
        _db
            .collection('users')
            .doc(remetenteUid)
            .collection('amigos')
            .doc(widget.uid),
        {'estado': 'aceite'},
      );
      batch.delete(
          _db.collection('pedidos_amizade').doc(docId));
      await batch.commit();
      _carregarAmigos();
    } catch (e) {
      debugPrint('Erro ao aceitar pedido: $e');
    }
  }

  Future<void> _recusarPedido(
      String remetenteUid, String docId) async {
    try {
      await _db
          .collection('pedidos_amizade')
          .doc(docId)
          .delete();
      _carregarAmigos();
    } catch (e) {
      debugPrint('Erro ao recusar pedido: $e');
    }
  }

  String _fmtTempo(int segundos) {
    if (segundos >= 3600) {
      final h = segundos ~/ 3600;
      final m = (segundos % 3600) ~/ 60;
      return m > 0 ? '${h}h ${m}m' : '${h}h';
    }
    return '${segundos ~/ 60}m';
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: temaEscuro,
      builder: (_, _esc, __) => Scaffold(
        appBar: AppBar(
          title: const Text('Amigos'),
          bottom: const PreferredSize(
            preferredSize: Size.fromHeight(1),
            child: Divider(color: azul, height: 1),
          ),
        ),
        body: _loading
            ? const Center(
                child: CircularProgressIndicator())
            : SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment:
                      CrossAxisAlignment.start,
                  children: [
                    TextField(
                      controller: _searchCtrl,
                      style: TextStyle(color: _tc()),
                      decoration: InputDecoration(
                        hintText:
                            'Pesquisar por @username ou nome...',
                        hintStyle:
                            TextStyle(color: _tc38()),
                        prefixIcon: Icon(Icons.search,
                            color: _tc54()),
                        suffixIcon: _searching
                            ? const Padding(
                                padding:
                                    EdgeInsets.all(12),
                                child: SizedBox(
                                    width: 16,
                                    height: 16,
                                    child:
                                        CircularProgressIndicator(
                                            strokeWidth:
                                                2)))
                            : null,
                        enabledBorder:
                            OutlineInputBorder(
                          borderSide: BorderSide(
                              color: _tc24()),
                          borderRadius:
                              BorderRadius.circular(12),
                        ),
                        focusedBorder:
                            const OutlineInputBorder(
                          borderSide: BorderSide(
                              color: azul),
                          borderRadius:
                              BorderRadius.all(
                                  Radius.circular(12)),
                        ),
                      ),
                      onChanged: (v) =>
                          Future.delayed(
                        const Duration(
                            milliseconds: 500),
                        () {
                          if (_searchCtrl.text == v) {
                            _pesquisar(v);
                          }
                        },
                      ),
                    ),
                    FutureBuilder<DocumentSnapshot>(
                      future: FirebaseFirestore.instance
                          .collection('users')
                          .doc(widget.uid)
                          .collection('perfil')
                          .doc('dados')
                          .get(),
                      builder: (ctx, snap) {
                        if (!snap.hasData ||
                            !snap.data!.exists) {
                          return const SizedBox
                              .shrink();
                        }
                        final perfil =
                            PerfilUsuario.fromJson(
                                snap.data!.data()
                                    as Map<String,
                                        dynamic>);
                        if (perfil.nomedeutilizador
                            .isEmpty) {
                          return Padding(
                            padding: const EdgeInsets
                                .only(
                                top: 10, bottom: 4),
                            child: Text(
                                '💡 Define um @username no teu perfil para partilhares o teu link.',
                                style: TextStyle(
                                    color: _tc38(),
                                    fontSize: 12)),
                          );
                        }
                        return Padding(
                          padding: const EdgeInsets.only(
                              top: 10),
                          child: OutlinedButton.icon(
                            onPressed: () {
                              Clipboard.setData(ClipboardData(
                                  text:
                                      '@${perfil.nomedeutilizador}'));
                              Share.share(
                                'Adiciona-me no Thoth! 📚\nPesquisa por @${perfil.nomedeutilizador} na aba de Amigos.',
                                subject:
                                    'O meu perfil no Thoth',
                              );
                            },
                            style:
                                OutlinedButton.styleFrom(
                              foregroundColor: azul,
                              side: const BorderSide(
                                  color: azul),
                              minimumSize: const Size(
                                  double.infinity, 44),
                              shape:
                                  RoundedRectangleBorder(
                                      borderRadius:
                                          BorderRadius
                                              .circular(
                                                  12)),
                            ),
                            icon: const Icon(
                                Icons.ios_share_rounded,
                                size: 16),
                            label: Text(
                                'Partilhar  @${perfil.nomedeutilizador}'),
                          ),
                        );
                      },
                    ),
                    const SizedBox(height: 8),
                    if (_resultados.isNotEmpty) ...[
                      const SizedBox(height: 12),
                      const Text('Resultados',
                          style: TextStyle(
                              color: azul,
                              fontSize: 14,
                              fontWeight:
                                  FontWeight.bold)),
                      const SizedBox(height: 8),
                      ..._resultados.map((r) {
                        final perfil =
                            r['perfil'] as PerfilUsuario;
                        final jaAmigo = r['jaAmigo']
                                as bool? ??
                            false;
                        final jaPedido = r['jaPedido']
                                as bool? ??
                            false;
                        return Container(
                          margin: const EdgeInsets.only(
                              bottom: 8),
                          padding:
                              const EdgeInsets.symmetric(
                                  horizontal: 14,
                                  vertical: 10),
                          decoration: BoxDecoration(
                            border: Border.all(
                                color: _tc24()),
                            borderRadius:
                                BorderRadius.circular(
                                    12),
                          ),
                          child: Row(
                            children: [
                              CircleAvatar(
                                radius: 20,
                                backgroundColor: azul
                                    .withOpacity(0.15),
                                child: Text(
                                    perfil.nome.isNotEmpty
                                        ? perfil.nome[0]
                                            .toUpperCase()
                                        : '?',
                                    style: const TextStyle(
                                        color: azul,
                                        fontWeight:
                                            FontWeight
                                                .bold)),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment
                                          .start,
                                  children: [
                                    Text(perfil.nome,
                                        style: TextStyle(
                                            color: _tc(),
                                            fontWeight:
                                                FontWeight
                                                    .bold)),
                                    if (perfil
                                        .nomedeutilizador
                                        .isNotEmpty)
                                      Text(
                                          '@${perfil.nomedeutilizador}',
                                          style: TextStyle(
                                              color:
                                                  _tc54(),
                                              fontSize:
                                                  12)),
                                  ],
                                ),
                              ),
                              if (jaAmigo)
                                const Icon(
                                    Icons.check_circle,
                                    color: azul,
                                    size: 20)
                              else if (jaPedido)
                                Text('Enviado',
                                    style: TextStyle(
                                        color: _tc38(),
                                        fontSize: 12))
                              else
                                IconButton(
                                  icon: const Icon(
                                      Icons
                                          .person_add_outlined,
                                      color: azul),
                                  onPressed: () =>
                                      _enviarPedido(
                                          r['uid']
                                              as String),
                                  tooltip:
                                      'Adicionar amigo',
                                ),
                            ],
                          ),
                        );
                      }),
                      const Divider(height: 24),
                    ],
                    Container(
                      margin: const EdgeInsets.only(
                          bottom: 20),
                      decoration: BoxDecoration(
                        border: Border.all(
                          color: _pedidos.isNotEmpty
                              ? azul.withOpacity(0.5)
                              : _tc().withOpacity(0.1),
                        ),
                        borderRadius:
                            BorderRadius.circular(14),
                        color: _pedidos.isNotEmpty
                            ? azul.withOpacity(0.06)
                            : Colors.transparent,
                      ),
                      child: Column(
                        crossAxisAlignment:
                            CrossAxisAlignment.start,
                        children: [
                          Padding(
                            padding:
                                const EdgeInsets.fromLTRB(
                                    14, 12, 14, 8),
                            child: Row(
                              children: [
                                const Icon(
                                    Icons.inbox_rounded,
                                    color: azul,
                                    size: 18),
                                const SizedBox(width: 8),
                                const Text(
                                    'Pedidos de amizade',
                                    style: TextStyle(
                                        color: azul,
                                        fontSize: 14,
                                        fontWeight:
                                            FontWeight
                                                .bold)),
                                const SizedBox(width: 8),
                                if (_pedidos.isNotEmpty)
                                  Container(
                                    padding:
                                        const EdgeInsets
                                            .symmetric(
                                            horizontal: 7,
                                            vertical: 2),
                                    decoration:
                                        BoxDecoration(
                                            color: azul,
                                            borderRadius:
                                                BorderRadius
                                                    .circular(
                                                        10)),
                                    child: Text(
                                        '${_pedidos.length}',
                                        style: const TextStyle(
                                            color: Colors
                                                .white,
                                            fontSize: 11,
                                            fontWeight:
                                                FontWeight
                                                    .bold)),
                                  ),
                              ],
                            ),
                          ),
                          if (_pedidos.isEmpty)
                            Padding(
                              padding:
                                  const EdgeInsets.fromLTRB(
                                      14, 0, 14, 14),
                              child: Text(
                                  'Nenhum pedido pendente',
                                  style: TextStyle(
                                      color: _tc38(),
                                      fontSize: 13)),
                            )
                          else
                            ..._pedidos.map((p) {
                              final perfil = p['perfil']
                                  as PerfilUsuario;
                              return Container(
                                margin:
                                    const EdgeInsets
                                        .fromLTRB(
                                        10, 0, 10, 10),
                                padding:
                                    const EdgeInsets
                                        .symmetric(
                                        horizontal: 12,
                                        vertical: 10),
                                decoration:
                                    BoxDecoration(
                                  color: _tc()
                                      .withOpacity(0.04),
                                  borderRadius:
                                      BorderRadius
                                          .circular(10),
                                ),
                                child: Row(
                                  children: [
                                    CircleAvatar(
                                      radius: 20,
                                      backgroundColor:
                                          azul.withOpacity(
                                              0.15),
                                      backgroundImage: perfil
                                              .fotoUrl
                                              .isNotEmpty
                                          ? NetworkImage(
                                              perfil
                                                  .fotoUrl)
                                          : null,
                                      child: perfil.fotoUrl
                                              .isEmpty
                                          ? Text(
                                              perfil.nome
                                                      .isNotEmpty
                                                  ? perfil
                                                      .nome[0]
                                                      .toUpperCase()
                                                  : '?',
                                              style: const TextStyle(
                                                  color:
                                                      azul,
                                                  fontWeight:
                                                      FontWeight
                                                          .bold))
                                          : null,
                                    ),
                                    const SizedBox(
                                        width: 12),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment
                                                .start,
                                        children: [
                                          Text(
                                              perfil.nome
                                                      .isNotEmpty
                                                  ? perfil
                                                      .nome
                                                  : 'Utilizador',
                                              style: TextStyle(
                                                  color:
                                                      _tc(),
                                                  fontWeight:
                                                      FontWeight
                                                          .bold,
                                                  fontSize:
                                                      14)),
                                          if (perfil
                                              .nomedeutilizador
                                              .isNotEmpty)
                                            Text(
                                                '@${perfil.nomedeutilizador}',
                                                style: TextStyle(
                                                    color:
                                                        _tc54(),
                                                    fontSize:
                                                        12)),
                                        ],
                                      ),
                                    ),
                                    IconButton(
                                      icon: const Icon(
                                          Icons
                                              .close_rounded,
                                          color: Colors
                                              .redAccent,
                                          size: 22),
                                      tooltip: 'Recusar',
                                      onPressed: () =>
                                          _recusarPedido(
                                              p['uid']
                                                  as String,
                                              p['docId']
                                                  as String),
                                    ),
                                    ElevatedButton(
                                      onPressed: () =>
                                          _aceitarPedido(
                                              p['uid']
                                                  as String,
                                              p['docId']
                                                  as String),
                                      style: ElevatedButton
                                          .styleFrom(
                                        backgroundColor:
                                            azul,
                                        foregroundColor:
                                            Colors.white,
                                        minimumSize:
                                            const Size(
                                                72, 34),
                                        padding:
                                            const EdgeInsets
                                                .symmetric(
                                                horizontal:
                                                    12),
                                        shape:
                                            RoundedRectangleBorder(
                                                borderRadius:
                                                    BorderRadius
                                                        .circular(
                                                            8)),
                                      ),
                                      child: const Text(
                                          'Aceitar',
                                          style: TextStyle(
                                              fontSize:
                                                  13)),
                                    ),
                                  ],
                                ),
                              );
                            }),
                        ],
                      ),
                    ),
                    Row(
                      children: [
                        const Text('Os meus amigos',
                            style: TextStyle(
                                color: azul,
                                fontSize: 16,
                                fontWeight:
                                    FontWeight.bold)),
                        const SizedBox(width: 8),
                        Text('(${_amigos.length})',
                            style: TextStyle(
                                color: _tc38(),
                                fontSize: 14)),
                      ],
                    ),
                    const SizedBox(height: 12),
                    // FIX: Stream de reacções sem orderBy para evitar índice composto
                    StreamBuilder<QuerySnapshot>(
                      stream: FirebaseFirestore.instance
                          .collection('users')
                          .doc(widget.uid)
                          .collection('reacoes')
                          .where('lida',
                              isEqualTo: false)
                          .limit(10)
                          .snapshots(),
                      builder: (ctx, snapR) {
                        if (!snapR.hasData ||
                            snapR.data!.docs.isEmpty) {
                          return const SizedBox
                              .shrink();
                        }
                        final reacoes =
                            snapR.data!.docs;
                        return Container(
                          margin: const EdgeInsets.only(
                              bottom: 16),
                          padding:
                              const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            border: Border.all(
                                color: const Color(
                                        0xFF1D81C7)
                                    .withOpacity(0.4)),
                            borderRadius:
                                BorderRadius.circular(
                                    14),
                            color: const Color(
                                    0xFF1D81C7)
                                .withOpacity(0.05),
                          ),
                          child: Column(
                            crossAxisAlignment:
                                CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  const Icon(
                                      Icons
                                          .favorite_outline,
                                      color: Color(
                                          0xFF1D81C7),
                                      size: 16),
                                  const SizedBox(
                                      width: 6),
                                  const Text(
                                      'Novas reacções',
                                      style: TextStyle(
                                          color: Color(
                                              0xFF1D81C7),
                                          fontWeight:
                                              FontWeight
                                                  .bold,
                                          fontSize: 14)),
                                  const SizedBox(
                                      width: 6),
                                  Container(
                                    padding:
                                        const EdgeInsets
                                            .symmetric(
                                            horizontal: 6,
                                            vertical: 1),
                                    decoration:
                                        BoxDecoration(
                                            color: const Color(
                                                0xFF1D81C7),
                                            borderRadius:
                                                BorderRadius
                                                    .circular(
                                                        8)),
                                    child: Text(
                                        '${reacoes.length}',
                                        style: const TextStyle(
                                            color: Colors
                                                .white,
                                            fontSize: 10,
                                            fontWeight:
                                                FontWeight
                                                    .bold)),
                                  ),
                                  const Spacer(),
                                  TextButton(
                                    onPressed: () async {
                                      final batch =
                                          FirebaseFirestore
                                              .instance
                                              .batch();
                                      for (final doc
                                          in reacoes) {
                                        batch.update(
                                            doc.reference,
                                            {
                                              'lida': true
                                            });
                                      }
                                      await batch
                                          .commit();
                                    },
                                    style: TextButton
                                        .styleFrom(
                                            padding: const EdgeInsets
                                                .symmetric(
                                                horizontal:
                                                    6)),
                                    child: Text(
                                        'Marcar lidas',
                                        style: TextStyle(
                                            color:
                                                _tc38(),
                                            fontSize:
                                                11)),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 10),
                              Wrap(
                                spacing: 8,
                                runSpacing: 8,
                                children:
                                    reacoes.map((doc) {
                                  final data = doc.data()
                                      as Map<String,
                                          dynamic>;
                                  final emoji = data[
                                          'emoji'] as String? ??
                                      '👏';
                                  final de = data['de']
                                          as String? ??
                                      '';
                                  final amigo =
                                      _amigos.firstWhere(
                                          (a) =>
                                              a['uid'] ==
                                              de,
                                          orElse: () =>
                                              {});
                                  final nomeAmigo =
                                      amigo.isNotEmpty
                                          ? (amigo['perfil']
                                                  as PerfilUsuario)
                                              .nome
                                          : 'Amigo';
                                  return Container(
                                    padding:
                                        const EdgeInsets
                                            .symmetric(
                                            horizontal:
                                                10,
                                            vertical: 6),
                                    decoration:
                                        BoxDecoration(
                                      color: _tc()
                                          .withOpacity(
                                              0.06),
                                      borderRadius:
                                          BorderRadius
                                              .circular(
                                                  20),
                                      border: Border.all(
                                          color: _tc()
                                              .withOpacity(
                                                  0.1)),
                                    ),
                                    child: Text(
                                        '$emoji  $nomeAmigo',
                                        style: TextStyle(
                                            color: _tc(),
                                            fontSize:
                                                13)),
                                  );
                                }).toList(),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                    if (_amigos.isEmpty)
                      Center(
                        child: Padding(
                          padding:
                              const EdgeInsets.symmetric(
                                  vertical: 40),
                          child: Column(
                            children: [
                              Icon(
                                  Icons.group_outlined,
                                  size: 56,
                                  color: _tc()
                                      .withOpacity(
                                          0.15)),
                              const SizedBox(height: 12),
                              Text('Ainda sem amigos',
                                  style: TextStyle(
                                      color: _tc38(),
                                      fontSize: 15)),
                              const SizedBox(height: 6),
                              Text(
                                  'Pesquisa pelo nome para adicionar',
                                  style: TextStyle(
                                      color: _tc()
                                          .withOpacity(
                                              0.2),
                                      fontSize: 12)),
                            ],
                          ),
                        ),
                      )
                    else
                      ..._amigos.map((a) {
                        final perfil =
                            a['perfil'] as PerfilUsuario;
                        final streak =
                            a['streak'] as StreakInfo;
                        final totalFoco =
                            a['totalFoco'] as int;
                        final totalSessoes =
                            a['totalSessoes'] as int;
                        return Container(
                          margin: const EdgeInsets.only(
                              bottom: 12),
                          padding:
                              const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            border: Border.all(
                                color: _tc()
                                    .withOpacity(0.1)),
                            borderRadius:
                                BorderRadius.circular(
                                    14),
               
