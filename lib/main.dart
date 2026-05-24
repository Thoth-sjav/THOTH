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
import 'package:shared_preferences/shared_preferences.dart';

import 'firebase_options.dart';

// ─── Reacções disponíveis entre amigos ──────────────────────────────────────
const List<String> _reacoes = ['🔥', '💪', '👏', '⚡', '🎯', '🏆'];

// ─── Helpers de plataforma ───────────────────────────────────────────────────
bool get _isDesktop =>
    !kIsWeb && (Platform.isWindows || Platform.isMacOS || Platform.isLinux);

// ─── Notificações globais ────────────────────────────────────────────────────
final FlutterLocalNotificationsPlugin _notifPlugin =
    FlutterLocalNotificationsPlugin();

// Mensagens passivo-agressivas estilo Duolingo
final List<String> _mensagensNotif = [
  // Clássicos passivo-agressivos
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
  // Novos — mais engraçados e duolingo-ish
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

  // Android 13+ — pedir permissão de notificações em runtime
  if (!kIsWeb && Platform.isAndroid) {
    final androidPlugin = _notifPlugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>();
    await androidPlugin?.requestNotificationsPermission();
    await androidPlugin?.requestExactAlarmsPermission();
  }
}

/// Agenda uma notificação diária às 20h, MAS só a mostra se o utilizador
/// ainda não tiver estudado hoje. Usa um canal de alta prioridade para
/// aparecer mesmo com a app fechada (Android 8+, iOS com permissão).
Future<void> _agendarNotificacaoDiaria() async {
  // Windows/Linux não suportam notificações nativas via este plugin
  if (_isDesktop && !Platform.isMacOS) return;

  await _notifPlugin.cancelAll();

  final rand = math.Random();
  final msg = _mensagensNotif[rand.nextInt(_mensagensNotif.length)];

  // Agenda para as 20h todos os dias
  final agora = tz.TZDateTime.now(tz.local);
  var agendado = tz.TZDateTime(tz.local, agora.year, agora.month, agora.day, 20, 0);
  if (agendado.isBefore(agora)) {
    agendado = agendado.add(const Duration(days: 1));
  }

  const androidDetails = AndroidNotificationDetails(
    'thoth_daily',
    'Lembrete Diário',
    channelDescription: 'Lembrete passivo-agressivo para estudar',
    importance: Importance.max,           // heads-up mesmo com app fechada
    priority: Priority.max,
    ticker: 'Vai estudar.',
    playSound: true,
    enableVibration: true,
    styleInformation: const BigTextStyleInformation(
      'Thoth está à tua espera 📚 - Vai estudar e alcança os teus objetivos!',
    ),
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
    const NotificationDetails(android: androidDetails, iOS: iosDetails, macOS: iosDetails),
    androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
    uiLocalNotificationDateInterpretation:
        UILocalNotificationDateInterpretation.absoluteTime,
    matchDateTimeComponents: DateTimeComponents.time,   // repete diariamente
  );
}

/// Verifica se o utilizador já estudou hoje e, se sim, cancela a notificação agendada.
/// Deve ser chamado quando uma sessão é concluída.
Future<void> _cancelarNotifSeEstudouHoje(String uid) async {
  try {
    final hoje = DateTime.now();
    final inicioDia = DateTime(hoje.year, hoje.month, hoje.day);
    final snap = await FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .collection('sessoes')
        .where('dataConclusao', isGreaterThanOrEqualTo: inicioDia.toIso8601String())
        .limit(1)
        .get();
    if (snap.docs.isNotEmpty) {
      await _notifPlugin.cancel(0);  // cancela a notificação das 20h
    }
  } catch (_) {}
}

/// ─── Serviço de Persistência de Sessão ──────────────────────────────────────
class SessionPersistenceService {
  static const String _userIdKey = 'thoth_user_id';
  static const String _loginTimestampKey = 'thoth_login_timestamp';
  static const String _isLoggedInKey = 'thoth_is_logged_in';

  /// Salva a sessão quando o utilizador faz login
  static Future<void> saveSession(String userId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_userIdKey, userId);
      await prefs.setBool(_isLoggedInKey, true);
      await prefs.setInt(_loginTimestampKey, DateTime.now().millisecondsSinceEpoch);
      debugPrint('✅ Sessão guardada para: $userId');
    } catch (e) {
      debugPrint('❌ Erro ao guardar sessão: $e');
    }
  }

  /// Obtém o ID do utilizador guardado
  static Future<String?> getSavedUserId() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getString(_userIdKey);
    } catch (e) {
      debugPrint('❌ Erro ao obter utilizador guardado: $e');
      return null;
    }
  }

  /// Verifica se há uma sessão ativa
  static Future<bool> hasActiveSession() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getBool(_isLoggedInKey) ?? false;
    } catch (e) {
      debugPrint('❌ Erro ao verificar sessão: $e');
      return false;
    }
  }

  /// Limpa a sessão quando o utilizador faz logout
  static Future<void> clearSession() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_userIdKey);
      await prefs.remove(_isLoggedInKey);
      await prefs.remove(_loginTimestampKey);
      debugPrint('✅ Sessão limpa');
    } catch (e) {
      debugPrint('❌ Erro ao limpar sessão: $e');
    }
  }
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  // ✨ NOVO: Aguardar que o Firebase Auth restaure a sessão
  // Isto é crítico para persistência de login
  int retries = 0;
  while (FirebaseAuth.instance.currentUser == null && retries < 30) {
    await Future.delayed(const Duration(milliseconds: 100));
    retries++;
  }
  
  if (FirebaseAuth.instance.currentUser == null) {
    debugPrint('⚠️ Aviso: Firebase Auth não restaurou a sessão após 3 segundos');
  } else {
    debugPrint('✅ Sessão restaurada: ${FirebaseAuth.instance.currentUser!.email}');
  }

  await _inicializarNotificacoes();

  // Orientação só faz sentido em mobile
  if (!_isDesktop && !kIsWeb) {
    await SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
    ]);
  }

  // Configuração da janela desktop (Windows / macOS / Linux)
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
        progressoSalvo: (j['progressoSalvo'] as num?)?.toDouble() ?? 0.0,
        cicloSalvo: j['cicloSalvo'] as int? ?? 1,
        estavaNoDescanso: j['estavaNoDescanso'] as bool? ?? false,
        segundosSalvos: j['segundosSalvos'] as int? ?? 1500,
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
  String fotoUrl; // URL da foto de perfil (guardada no Firestore Storage ou Google photo)

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

  Map<String, dynamic> toJson() => {
        'tarefaNome': tarefaNome,
        'dataConclusao': dataConclusao.toIso8601String(),
        'ciclosConcluidos': ciclosConcluidos,
        'tempoFocoSegundos': tempoFocoSegundos,
      };

  factory SessaoConcluida.fromJson(Map<String, dynamic> j) => SessaoConcluida(
        tarefaNome: j['tarefaNome'] as String? ?? '',
        dataConclusao: DateTime.parse(j['dataConclusao'] as String),
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
  final bool frozenHoje; // true = streak salva por freeze hoje

  const StreakInfo({required this.dias, this.ultimoEstudo, this.frozenHoje = false});

  bool get acendeuHoje {
    if (ultimoEstudo == null) return false;
    final agora = DateTime.now();
    final ult = ultimoEstudo!;
    return ult.year == agora.year && ult.month == agora.month && ult.day == agora.day;
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
    final yesterdayStr = '${yesterday.year}-${yesterday.month}-${yesterday.day}';
    if (!dias.contains(todayStr) && !dias.contains(yesterdayStr)) return const StreakInfo(dias: 0);
    for (int i = sorted.length - 1; i > 0; i--) {
      final curr = DateTime.parse(sorted[i]);
      final prev = DateTime.parse(sorted[i - 1]);
      if (curr.difference(prev).inDays == 1) {
        streak++;
      } else {
        break;
      }
    }
    final lastSession = sessoes.reduce((a, b) => a.dataConclusao.isAfter(b.dataConclusao) ? a : b);
    return StreakInfo(dias: streak, ultimoEstudo: lastSession.dataConclusao);
  }

  /// Calcula streak considerando dias de freeze (dias sem estudo mas com freeze activo)
  static StreakInfo calcularComFreeze(List<SessaoConcluida> sessoes, List<String> freezeDias) {
    if (sessoes.isEmpty) return const StreakInfo(dias: 0);
    final diasEstudo = <String>{};
    for (final s in sessoes) {
      final d = s.dataConclusao;
      diasEstudo.add('${d.year}-${d.month}-${d.day}');
    }
    // Adicionar dias de freeze ao conjunto de dias "activos"
    final diasActivos = {...diasEstudo, ...freezeDias};
    final sorted = diasActivos.toList()..sort();
    int streak = 1;
    final today = DateTime.now();
    final todayStr = '${today.year}-${today.month}-${today.day}';
    final yesterday = today.subtract(const Duration(days: 1));
    final yesterdayStr = '${yesterday.year}-${yesterday.month}-${yesterday.day}';
    if (!diasActivos.contains(todayStr) && !diasActivos.contains(yesterdayStr)) {
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
    final frozenHoje = !diasEstudo.contains(todayStr) && diasActivos.contains(todayStr);
    final lastSession = sessoes.reduce((a, b) => a.dataConclusao.isAfter(b.dataConclusao) ? a : b);
    return StreakInfo(dias: streak, ultimoEstudo: lastSession.dataConclusao, frozenHoje: frozenHoje);
  }

  static const List<Map<String, dynamic>> conquistas = [
    {'dias': 3,   'label': '3 dias',    'icon': '🔥'},
    {'dias': 7,   'label': '1 semana',  'icon': '⚡'},
    {'dias': 10,  'label': '10 dias',   'icon': '💪'},
    {'dias': 30,  'label': '30 dias',   'icon': '🏅'},
    {'dias': 50,  'label': '50 dias',   'icon': '🥈'},
    {'dias': 75,  'label': '75 dias',   'icon': '🥇'},
    {'dias': 100, 'label': '100 dias',  'icon': '💎'},
    {'dias': 180, 'label': '6 meses',   'icon': '🌟'},
    {'dias': 365, 'label': '1 ano',     'icon': '👑'},
  ];
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
        builder: (context, child) {
          // Em desktop, centra o conteúdo com largura máxima estilo mobile
          if (_isDesktop && child != null) {
            return Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 480),
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
      // Web Client ID do Firebase Authentication → Sign-in method → Google → Web client ID
      final GoogleSignIn googleSignIn = GoogleSignIn(
        serverClientId: '639767112265-bupqhsgfftmn42rkcob8cvk9ntrk2nje.apps.googleusercontent.com',
      );

      final GoogleSignInAccount? googleUser = await googleSignIn.signIn();

      if (googleUser == null) {
        setState(() => _loading = false);
        return;
      }

      final GoogleSignInAuthentication googleAuth =
          await googleUser.authentication;

      if (googleAuth.idToken == null) {
        debugPrint('ERRO: idToken é null. Verifica o SHA-1 no Firebase Console.');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Erro de autenticação. Verifica a ligação e tenta novamente.')),
          );
        }
        setState(() => _loading = false);
        return;
      }

      final credential = GoogleAuthProvider.credential(
  accessToken: googleAuth.accessToken,
  idToken: googleAuth.idToken,
);

final currentUser = FirebaseAuth.instance.currentUser;

UserCredential userCredential;

if (currentUser != null && currentUser.isAnonymous) {
  userCredential =
      await currentUser.linkWithCredential(credential);
} else {
  userCredential =
      await FirebaseAuth.instance.signInWithCredential(credential);
}
      // ✨ NOVO: Guardar a sessão após login bem-sucedido
      if (userCredential.user != null) {
        await SessionPersistenceService.saveSession(userCredential.user!.uid);
        debugPrint('✅ Login bem-sucedido para ${userCredential.user!.email}');
      }
      // AuthGate deteta a mudança automaticamente
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
                // Logo / título
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

                // Separador
                Container(height: 1, color: Colors.white12),
                const SizedBox(height: 50),

                // Bem-vindo
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
                  style: TextStyle(fontSize: 14, color: Colors.white54),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 40),

                // Botão Sign In
                SizedBox(
                  width: double.infinity,
                  height: 54,
                  child: ElevatedButton.icon(
                    onPressed: _loading ? null : signInWithGoogle,
                    icon: _loading
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              color: Colors.white,
                              strokeWidth: 2,
                            ),
                          )
                        : const Icon(Icons.login, color: Colors.white),
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
                      disabledBackgroundColor: azul.withOpacity(0.6),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                      elevation: 0,
                    ),
                  ),
                ),
                const SizedBox(height: 24),

                // Termos
                const Text(
                  'Ao entrar, aceitas os termos de utilização do Thoth',
                  style: TextStyle(fontSize: 12, color: Colors.white24),
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

  // Loading state
  bool _aCarregarDados = true;

  // ---------------------------------------------------------------------------
  // CICLO DE VIDA
  // ---------------------------------------------------------------------------

  // ── Firestore helpers ───────────────────────────────────────────────────────
  FirebaseFirestore get _db => FirebaseFirestore.instance;
  String get _uid => FirebaseAuth.instance.currentUser!.uid;
  DocumentReference get _configDoc  => _db.collection('users').doc(_uid).collection('config').doc('dados');
  DocumentReference get _perfilDoc  => _db.collection('users').doc(_uid).collection('perfil').doc('dados');
  CollectionReference get _tarefasCol => _db.collection('users').doc(_uid).collection('tarefas');
  CollectionReference get _sessoesCol => _db.collection('users').doc(_uid).collection('sessoes');
  CollectionReference get _todoCol    => _db.collection('users').doc(_uid).collection('todo');

  String? _todoBlocosGuardados;
  DateTime? _countdownAlvoGuardado;
  String? _countdownMotivoGuardado;

  // ── Streak freeze ──────────────────────────────────────────────────────
  int _streakFreezes = 0;
  List<String> _freezeDias = []; // datas em formato yyyy-M-d onde o freeze foi usado

  // ── Meta semanal ───────────────────────────────────────────────────────
  int _metaSemanalMinutos = 0;

  // ── Modo não perturbar ─────────────────────────────────────────────────
  bool _modoDNDAtivo = false;

  // Timer em segundo plano — guardamos o momento absoluto em que o timer
  // estava a correr para recalcular ao regressar, mesmo que o processo tenha
  // sido suspenso pelo SO.
  DateTime? _timerReferencia;   // momento em que segundosRestantes foi registado
  int?      _segundosNaReferencia; // valor de segundosRestantes nesse momento

  /// Persiste o estado do timer em curso no Firestore para sobreviver
  /// a mudanças de telefone ou fecho da app.
  Future<void> _guardarEstadoTimer() async {
    if (tarefaAtual == null) return;
    await _configDoc.set({
      'timerAtivo': estadoApp == EstadoApp.cronometro,
      'timerTarefaId': tarefaAtual?.id,
      'timerSegundosRestantes': segundosRestantes,
      'timerCicloAtual': cicloAtual,
      'timerEstaNoDescanso': estaNoDescanso,
      'timerPausado': pausado,
      'timerReferencia': (!pausado && estadoApp == EstadoApp.cronometro)
          ? DateTime.now().toIso8601String()
          : null,
    }, SetOptions(merge: true));
  }

  /// Ao arrancar, restaura o timer que estava a correr (mesmo noutro telefone).
  Future<void> _restaurarTimerSeAtivo(Map<String, dynamic> d) async {
    final timerAtivo = d['timerAtivo'] as bool? ?? false;
    if (!timerAtivo) return;

    final tarefaId = d['timerTarefaId'] as String?;
    if (tarefaId == null) return;

    Tarefa? t;
    try { t = tarefas.firstWhere((x) => x.id == tarefaId); } catch (_) { return; }

    var segundos = (d['timerSegundosRestantes'] as int?) ?? t.estudo;
    final ciclo  = (d['timerCicloAtual'] as int?) ?? 1;
    final noDesc = (d['timerEstaNoDescanso'] as bool?) ?? false;
    final estava = (d['timerPausado'] as bool?) ?? true;
    final refStr = d['timerReferencia'] as String?;

    // Se o timer estava a correr, calcular o tempo passado desde a referência
    if (!estava && refStr != null) {
      final ref = DateTime.tryParse(refStr);
      if (ref != null) {
        final elapsed = DateTime.now().difference(ref).inSeconds;
        segundos = (segundos - elapsed).clamp(0, 999999);
      }
    }

    // Restaurar estado
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

    // Relançar o ticker
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (pausado || tarefaAtual == null) return;
      if (segundosRestantes > 1) {
        setState(() { segundosRestantes--; _salvarEstadoAtual(); });
        // Guardar referência periódica (a cada 30s) para sobreviver a suspensões
        if (segundosRestantes % 30 == 0) _guardarEstadoTimer();
      } else {
        _salvarEstadoAtual();
        _avancarFase();
      }
    });
  }

  Future<void> _carregarDados() async {
    try {
      // Verificar se o utilizador está autenticado
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        debugPrint('❌ Erro: Utilizador não autenticado em _carregarDados');
        if (mounted) {
          setState(() { _aCarregarDados = false; });
        }
        return;
      }

      debugPrint('📚 Carregando dados para: ${user.email}');

      // Config (tema + countdown)
      try {
        final configSnap = await _configDoc.get().timeout(
          const Duration(seconds: 5),
          onTimeout: () {
            throw TimeoutException('Timeout ao carregar config');
          },
        );
        if (configSnap.exists) {
          final d = configSnap.data() as Map<String, dynamic>;
          if (d['temaEscuro'] != null) temaEscuro.value = d['temaEscuro'] as bool;
          if (d['countdownAlvo'] != null) {
            _countdownAlvoGuardado = DateTime.tryParse(d['countdownAlvo'] as String);
          }
          if (d['countdownMotivo'] != null) {
            _countdownMotivoGuardado = d['countdownMotivo'] as String;
          }
          if (d['streakFreezes'] != null) {
            _streakFreezes = d['streakFreezes'] as int? ?? 0;
          }
          if (d['metaSemanalMinutos'] != null) {
            _metaSemanalMinutos = d['metaSemanalMinutos'] as int? ?? 0;
          }
          if (d['modoDNDAtivo'] != null) {
            _modoDNDAtivo = d['modoDNDAtivo'] as bool? ?? false;
          }
          if (d['freezeDias'] != null) {
            _freezeDias = List<String>.from(d['freezeDias'] as List? ?? []);
          }
        }
        debugPrint('✅ Config carregada');
      } catch (e) {
        debugPrint('⚠️ Erro ao carregar config: $e');
      }

      // Perfil
      try {
        final perfilSnap = await _perfilDoc.get().timeout(
          const Duration(seconds: 5),
          onTimeout: () {
            throw TimeoutException('Timeout ao carregar perfil');
          },
        );
        if (perfilSnap.exists) {
          perfil = PerfilUsuario.fromJson(perfilSnap.data() as Map<String, dynamic>);
          debugPrint('✅ Perfil carregado: ${perfil.nomedeutilizador}');
        } else {
          debugPrint('⚠️ Documento de perfil não existe');
        }
      } catch (e) {
        debugPrint('⚠️ Erro ao carregar perfil: $e');
      }

      // Tarefas
      try {
        final tarefasSnap = await _tarefasCol.orderBy('ordem').get().timeout(
          const Duration(seconds: 5),
          onTimeout: () {
            throw TimeoutException('Timeout ao carregar tarefas');
          },
        );
        tarefas = tarefasSnap.docs
            .map((d) => Tarefa.fromJson(d.data() as Map<String, dynamic>))
            .toList();
        debugPrint('✅ Tarefas carregadas: ${tarefas.length}');
      } catch (e) {
        debugPrint('⚠️ Erro ao carregar tarefas: $e');
      }

      // Ultima tarefa
      try {
        final configSnap = await _configDoc.get().timeout(
          const Duration(seconds: 5),
          onTimeout: () {
            throw TimeoutException('Timeout ao carregar ultima tarefa');
          },
        );
        final configData = configSnap.exists ? configSnap.data() as Map<String, dynamic> : {};
        final ultimaId = configData['ultimaTarefaId'] as String?;
        if (ultimaId != null) {
          try { 
            ultimaTarefa = tarefas.firstWhere((t) => t.id == ultimaId);
            debugPrint('✅ Última tarefa: ${ultimaTarefa?.nome}');
          } catch (_) {
            debugPrint('⚠️ Última tarefa não encontrada');
          }
        }
      } catch (e) {
        debugPrint('⚠️ Erro ao carregar última tarefa: $e');
      }

      // Sessões
      try {
        final sessoesSnap = await _sessoesCol.orderBy('dataConclusao').get().timeout(
          const Duration(seconds: 5),
          onTimeout: () {
            throw TimeoutException('Timeout ao carregar sessões');
          },
        );
        sessoes = sessoesSnap.docs
            .map((d) => SessaoConcluida.fromJson(d.data() as Map<String, dynamic>))
            .toList();
        debugPrint('✅ Sessões carregadas: ${sessoes.length}');
      } catch (e) {
        debugPrint('⚠️ Erro ao carregar sessões: $e');
      }

      // Todo blocos
      try {
        final todoSnap = await _todoCol.get().timeout(
          const Duration(seconds: 5),
          onTimeout: () {
            throw TimeoutException('Timeout ao carregar TODO');
          },
        );
        if (todoSnap.docs.isNotEmpty) {
          final m = <String, dynamic>{};
          for (final doc in todoSnap.docs) {
            m[doc.id] = doc.data();
          }
          _todoBlocosGuardados = jsonEncode(m);
          debugPrint('✅ TODO blocos carregados: ${todoSnap.docs.length}');
        }
      } catch (e) {
        debugPrint('⚠️ Erro ao carregar TODO: $e');
      }

      // Restaurar timer que estava a correr
      try {
        final configSnap = await _configDoc.get().timeout(
          const Duration(seconds: 5),
          onTimeout: () {
            throw TimeoutException('Timeout ao restaurar timer');
          },
        );
        if (configSnap.exists) {
          await _restaurarTimerSeAtivo(configSnap.data() as Map<String, dynamic>);
          debugPrint('✅ Timer restaurado');
        }
      } catch (e) {
        debugPrint('⚠️ Erro ao restaurar timer: $e');
      }
      
      // Agendar notificação diária
      try {
        await _agendarNotificacaoDiaria();
        debugPrint('✅ Notificação agendada');
      } catch (e) {
        debugPrint('⚠️ Erro ao agendar notificação: $e');
      }
      
      // Migração: garantir que o username do utilizador está no índice global
      try {
        await _migrarUsernameParaIndice();
        debugPrint('✅ Username migrado');
      } catch (e) {
        debugPrint('⚠️ Erro ao migrar username: $e');
      }
      
      debugPrint('✅ Todos os dados carregados com sucesso');
      if (mounted) {
        setState(() { _aCarregarDados = false; });
      }
    } catch (e) {
      debugPrint('❌ Erro geral ao carregar dados: $e');
      if (mounted) setState(() { _aCarregarDados = false; });
    }
  }

  // Problema 1 — garante que utilizadores existentes ficam no índice global
  Future<void> _migrarUsernameParaIndice() async {
    try {
      if (perfil.nomedeutilizador.isEmpty) return;
      final key = perfil.nomedeutilizador.toLowerCase();
      final doc = await _db.collection('usernames').doc(key).get();
      // Só escreve se ainda não existir ou se pertencer a este utilizador
      if (!doc.exists || (doc.data()?['uid'] as String?) == _uid) {
        await _db.collection('usernames').doc(key).set({
          'uid': _uid,
          'nome': perfil.nome,
          'nomedeutilizador': perfil.nomedeutilizador,
        });
      }
    } catch (e) {
      debugPrint('Erro ao migrar username para índice: $e');
    }
  }

  Future<void> _guardarTudo() async {
    final batch = _db.batch();

    // Config
    batch.set(_configDoc, {
      'temaEscuro': temaEscuro.value,
      'ultimaTarefaId': ultimaTarefa?.id,
      'countdownAlvo': _countdownAlvoGuardado?.toIso8601String(),
      'countdownMotivo': _countdownMotivoGuardado,
      'streakFreezes': _streakFreezes,
      'metaSemanalMinutos': _metaSemanalMinutos,
      'modoDNDAtivo': _modoDNDAtivo,
      'freezeDias': _freezeDias,
    }, SetOptions(merge: true));

    // Perfil
    batch.set(_perfilDoc, perfil.toJson(), SetOptions(merge: true));

    // Tarefas — reescreve todas (lista pequena)
    for (int i = 0; i < tarefas.length; i++) {
      final t = tarefas[i];
      final data = t.toJson();
      data['ordem'] = i;
      batch.set(_tarefasCol.doc(t.id), data);
    }

    await batch.commit();

    // Índice global de usernames — permite pesquisa rápida e unicidade
    if (perfil.nomedeutilizador.isNotEmpty) {
      await _db.collection('usernames').doc(perfil.nomedeutilizador.toLowerCase()).set({
        'uid': _uid,
        'nome': perfil.nome,
        'nomedeutilizador': perfil.nomedeutilizador,
      });
    }

    // Sessões — só adiciona novas (não apaga)
    // Guardamos separado para não exceder limite do batch (500 ops)
  }

  Future<void> _guardarSessao(SessaoConcluida s) async {
    await _sessoesCol.add(s.toJson());
  }

  /// Persiste imediatamente o progresso de todas as tarefas no Firestore.
  /// Mais leve que _guardarTudo() — só escreve as tarefas.
  /// Usado ao sair da app ou mudar de fase para garantir que nada se perde.
  Future<void> _guardarTarefasImediato() async {
    if (tarefas.isEmpty) return;
    try {
      final batch = _db.batch();
      for (int i = 0; i < tarefas.length; i++) {
        final t = tarefas[i];
        final data = t.toJson();
        data['ordem'] = i;
        batch.set(_tarefasCol.doc(t.id), data);
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
    _carregarDados();
    // Guardar quando o tema muda
    temaEscuro.addListener(() {
      _configDoc.set({'temaEscuro': temaEscuro.value}, SetOptions(merge: true));
    });
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

  /// Quando a app vai para background: guarda timestamp absoluto no Firestore.
  /// Quando regressa: calcula os segundos passados e avança o timer.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive ||
        state == AppLifecycleState.detached) {
      _salvarEstadoAtual();
      _guardarTudo();
      _guardarTarefasImediato();
      if (estadoApp == EstadoApp.cronometro && !pausado) {
        // Guardar referência absoluta para continuar ao regressar
        _guardarEstadoTimer();
      }
    }

    if (state == AppLifecycleState.resumed) {
      if (estadoApp == EstadoApp.cronometro && !pausado) {
        // Recalcular a partir da referência guardada no Firestore
        _configDoc.get().then((snap) {
          if (!snap.exists || !mounted) return;
          final d = snap.data() as Map<String, dynamic>;
          final refStr = d['timerReferencia'] as String?;
          final refSegundos = d['timerSegundosRestantes'] as int?;
          if (refStr != null && refSegundos != null) {
            final ref = DateTime.tryParse(refStr);
            if (ref != null) {
              final elapsed = DateTime.now().difference(ref).inSeconds;
              final novosSegundos = (refSegundos - elapsed).clamp(0, 999999);
              setState(() => segundosRestantes = novosSegundos);
              if (novosSegundos <= 0) _avancarFase();
            }
          }
        });
      }
    }
  }

  // ---------------------------------------------------------------------------
  // LÓGICA POMODORO
  // ---------------------------------------------------------------------------

  void iniciarTarefa(Tarefa t, {bool retomar = false}) {
    _timer?.cancel();
    // Modo não perturbar: suprimir volume de media durante o foco
    if (_modoDNDAtivo) {
      SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle());
      // Sinalizar via volume/notificação — a implementação real usa a preferência salva
    }
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
        // Guardar referência absoluta a cada 30s para sobreviver a suspensões
        if (segundosRestantes % 30 == 0) _guardarEstadoTimer();
      } else {
        _salvarEstadoAtual();
        _avancarFase();
      }
    });
    // Persistir imediatamente o estado do timer no Firestore
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
    // Persistir a tarefa atual imediatamente no Firestore
    final data = tarefaAtual!.toJson();
    final idx = tarefas.indexWhere((t) => t.id == tarefaAtual!.id);
    if (idx >= 0) data['ordem'] = idx;
    _tarefasCol.doc(tarefaAtual!.id).set(data).catchError((e) {
      debugPrint('Erro ao guardar tarefa atual: $e');
    });
  }

  double _calcularProgressoGlobal() {
    if (tarefaAtual == null) return 0.0;
    final totalFase = estaNoDescanso ? tarefaAtual!.descanso : tarefaAtual!.estudo;
    final progressoFase = totalFase <= 0 ? 0.0 : (1 - (segundosRestantes / totalFase));
    final global = ((cicloAtual - 1) + progressoFase) / tarefaAtual!.ciclos;
    return global.clamp(0.0, 1.0);
  }

  // ── Audio player para sons do timer ─────────────────────────────────────
  final AudioPlayer _audioPlayer = AudioPlayer();

  void _tocarSom({bool fim = false}) {
    try {
      HapticFeedback.mediumImpact();
      // Som real: fim de sessão usa som mais dramático, troca de fase usa som suave
      final asset = fim ? 'sounds/timer_fim.wav' : 'sounds/timer_fase.wav';
      _audioPlayer.play(AssetSource(asset)).catchError((_) {
        // fallback silencioso se o asset não existir
        SystemSound.play(SystemSoundType.click);
      });
    } catch (_) {
      SystemSound.play(SystemSoundType.click);
    }
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
      _tocarSom();
      setState(() {
        estaNoDescanso = true;
        segundosRestantes = tarefaAtual!.descanso;
        _salvarEstadoAtual();
      });
    } else {
      // Descanso acabou → próximo ciclo de estudo
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
    setState(() { pausado = !pausado; _primeiraVez = false; });
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
        // Persistir o reset no Firestore
        final t = ultimaTarefa!;
        final data = t.toJson();
        final idx = tarefas.indexWhere((x) => x.id == t.id);
        if (idx >= 0) data['ordem'] = idx;
        _tarefasCol.doc(t.id).set(data).catchError((e) {
          debugPrint('Erro ao descartar progresso: $e');
        });
      }
      ultimaTarefa = null;
    });
  }

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

      // Persistir imediatamente a tarefa concluída no Firestore
      final data = t.toJson();
      final idx = tarefas.indexWhere((x) => x.id == t.id);
      if (idx >= 0) data['ordem'] = idx;
      _tarefasCol.doc(t.id).set(data).catchError((e) {
        debugPrint('Erro ao guardar tarefa concluída: $e');
      });

      // Registar sessão concluída
      sessoes.add(SessaoConcluida(
        tarefaNome: t.nome.isEmpty ? 'Sem nome' : t.nome,
        dataConclusao: DateTime.now(),
        ciclosConcluidos: t.ciclos,
        tempoFocoSegundos: t.ciclos * t.estudo,
      ));
    }
    setState(() => estadoApp = EstadoApp.fim);
    _guardarTudo();
    if (sessoes.isNotEmpty) {
      _guardarSessao(sessoes.last);
      // Se estudou hoje, cancela a notificação das 20h
      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid != null) _cancelarNotifSeEstudouHoje(uid);
      // Ganhar 1 freeze a cada 7 dias de streak
      final streakAtual = StreakInfo.calcularComFreeze(sessoes, _freezeDias);
      if (streakAtual.dias > 0 && streakAtual.dias % 7 == 0) {
        _ganharStreakFreeze();
      }
    }
    // Limpar estado do timer no Firestore
    _configDoc.set({
      'timerAtivo': false,
      'timerReferencia': null,
    }, SetOptions(merge: true));
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
    // Limpar estado do timer no Firestore
    _configDoc.set({
      'timerAtivo': false,
      'timerReferencia': null,
    }, SetOptions(merge: true));
  }

  /// Usa um streak freeze para hoje — protege a streak mesmo sem estudar
  Future<void> _usarStreakFreeze() async {
    if (_streakFreezes <= 0) return;
    final today = DateTime.now();
    final todayStr = '${today.year}-${today.month}-${today.day}';
    if (_freezeDias.contains(todayStr)) return; // já usado hoje
    setState(() {
      _streakFreezes--;
      _freezeDias.add(todayStr);
    });
    await _guardarTudo();
  }

  /// Compra mais streak freezes (1 freeze = ganha por estudar X dias seguidos, ou lógica personalizada)
  void _ganharStreakFreeze() {
    setState(() => _streakFreezes++);
    _guardarTudo();
  }

  void removerTarefa(int index) {
    final tarefaId = tarefas[index].id;
    setState(() {
      if (ultimaTarefa != null && tarefas[index].id == ultimaTarefa!.id) {
        ultimaTarefa = null;
      }
      tarefas.removeAt(index);
    });
    // Apagar documento do Firestore
    _tarefasCol.doc(tarefaId).delete().catchError((e) {
      debugPrint('Erro ao apagar tarefa: $e');
    });
    _guardarTudo();
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
    // Mostrar splash de carregamento enquanto os dados do Firestore chegam
    if (_aCarregarDados) {
      return ValueListenableBuilder<bool>(
        valueListenable: temaEscuro,
        builder: (_, escuro, __) => Scaffold(
          backgroundColor: escuro ? Colors.black : Colors.white,
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
                CircularProgressIndicator(color: Color(0xFF1D81C7)),
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
                    backgroundImage: perfil.fotoUrl.isNotEmpty
                        ? (perfil.fotoUrl.startsWith('data:')
                            ? MemoryImage(base64Decode(perfil.fotoUrl.split(',').last)) as ImageProvider<Object>
                            : NetworkImage(perfil.fotoUrl) as ImageProvider<Object>)
                        : null,
                    child: perfil.fotoUrl.isEmpty
                        ? Icon(Icons.person, size: 40, color: branco)
                        : null,
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
                state._guardarTudo();
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
                  builder: (_) => TelaTodo(lista: state.notasTodo, todoBlocosJson: state._todoBlocosGuardados),
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
          StreamBuilder<QuerySnapshot>(
            stream: FirebaseFirestore.instance
                .collection('pedidos_amizade')
                .where('para', isEqualTo: FirebaseAuth.instance.currentUser!.uid)
                .snapshots(),
            builder: (ctx, snap) {
              final countPedidos = snap.data?.docs
                  .where((d) => (d.data() as Map)['estado'] == 'pendente')
                  .length ?? 0;
              return StreamBuilder<QuerySnapshot>(
                stream: FirebaseFirestore.instance
                    .collection('users')
                    .doc(FirebaseAuth.instance.currentUser!.uid)
                    .collection('reacoes')
                    .where('lida', isEqualTo: false)
                    .snapshots(),
                builder: (ctx2, snapR) {
                  final countReacoes = snapR.data?.docs.length ?? 0;
                  final count = countPedidos + countReacoes;
                  return _drawerItem(
                    icon: Icons.group_outlined,
                    label: 'Amigos',
                    badge: count,
                    onTap: () {
                      Navigator.pop(context);
                      Navigator.push(
                        context,
                        MaterialPageRoute(builder: (_) => TelaAmigos(uid: FirebaseAuth.instance.currentUser!.uid)),
                      );
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
              Navigator.push(context, MaterialPageRoute(builder: (_) => const TelaLeaderboard()));
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
                    state.setState(() => state._metaSemanalMinutos = v);
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
    int badge = 0,
  }) {
    return ListTile(
      leading: badge > 0
          ? Badge(
              label: Text('$badge', style: const TextStyle(fontSize: 10)),
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
    _alvo = widget.countdownAlvoInicial ??
        DateTime.now().add(const Duration(days: 47, hours: 9, minutes: 57));
    _motivoAlvo = widget.countdownMotivoInicial ?? 'Exame';
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
    // persist countdown
    widget.state._countdownAlvoGuardado = _alvo;
    widget.state._countdownMotivoGuardado = _motivoAlvo;
    widget.state._configDoc.set({
      'countdownAlvo': _alvo.toIso8601String(),
      'countdownMotivo': _motivoAlvo,
    }, SetOptions(merge: true));
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
                  // ── Streak badge ──────────────────────────────────
                  _StreakBadge(streak: StreakInfo.calcularComFreeze(widget.state.sessoes, widget.state._freezeDias), onUsarFreeze: widget.state._usarStreakFreeze, freezesDisponiveis: widget.state._streakFreezes),
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
            const SizedBox(height: 12),

            // ── Meta Semanal Card ─────────────────────────────────────
            if (widget.state._metaSemanalMinutos > 0)
              _CartaoMetaSemanal(sessoes: widget.state.sessoes, meta: widget.state._metaSemanalMinutos),

            const SizedBox(height: 12),

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
                                  Text('Toca em "Gerir Tarefas" para começar',
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
                        child: const Text('GERIR TAREFAS',
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

// =============================================================================
// CARTÃO META SEMANAL (tela inicial)
// =============================================================================

class _CartaoMetaSemanal extends StatelessWidget {
  final List<SessaoConcluida> sessoes;
  final int meta; // em minutos
  const _CartaoMetaSemanal({required this.sessoes, required this.meta});

  int get _minutosEstaSemana {
    final hoje = DateTime.now();
    final inicioSemana = hoje.subtract(Duration(days: hoje.weekday - 1));
    final semanaStr = DateTime(inicioSemana.year, inicioSemana.month, inicioSemana.day);
    return sessoes
        .where((s) => s.dataConclusao.isAfter(semanaStr))
        .fold(0, (acc, s) => acc + s.tempoFocoSegundos ~/ 60);
  }

  @override
  Widget build(BuildContext context) {
    const azul = Color(0xFF1D81C7);
    const verde = Colors.greenAccent;
    final mins = _minutosEstaSemana;
    final progresso = meta > 0 ? (mins / meta).clamp(0.0, 1.0) : 0.0;
    final concluida = progresso >= 1.0;

    return GestureDetector(
      onTap: () => showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (_) => _BottomSheetMetaSemanal(
          sessoes: sessoes,
          metaAtual: meta,
          onSalvar: (_) {}, // read-only aqui; edição via drawer
        ),
      ),
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 25),
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
        decoration: BoxDecoration(
          color: concluida ? verde.withOpacity(0.07) : azul.withOpacity(0.06),
          border: Border.all(color: concluida ? verde.withOpacity(0.4) : azul.withOpacity(0.3)),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Column(
          children: [
            Row(
              children: [
                Text(concluida ? '🏆' : '🎯', style: const TextStyle(fontSize: 16)),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    concluida ? 'Meta semanal atingida!' : 'Meta semanal',
                    style: TextStyle(
                      color: concluida ? verde : azul,
                      fontSize: 13, fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                Text(
                  '${mins ~/ 60}h ${mins % 60}m / ${meta ~/ 60}h',
                  style: TextStyle(color: _tc54(), fontSize: 12),
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
                backgroundColor: _tc().withOpacity(0.08),
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
  const _StreakBadge({required this.streak, this.onUsarFreeze, this.freezesDisponiveis = 0});

  @override
  Widget build(BuildContext context) {
    final aceso = streak.acendeuHoje || streak.frozenHoje;
    final dias = streak.dias;
    return GestureDetector(
      onTap: () {
        showDialog(
          context: context,
          builder: (_) => _StreakDialog(streak: streak, onUsarFreeze: onUsarFreeze, freezesDisponiveis: freezesDisponiveis),
        );
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 400),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: aceso
              ? const Color(0xFFFF6D00).withOpacity(0.25)
              : Colors.white.withOpacity(0.10),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: aceso ? const Color(0xFFFF6D00) : Colors.white24,
            width: 1.2,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              aceso ? '🔥' : '🔥',
              style: TextStyle(
                fontSize: 16,
                color: aceso ? null : null,
              ),
            ),
            const SizedBox(width: 4),
            Text(
              '$dias',
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.bold,
                color: aceso ? const Color(0xFFFFCC02) : Colors.white60,
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
  const _StreakDialog({required this.streak, this.onUsarFreeze, this.freezesDisponiveis = 0});

  @override
  Widget build(BuildContext context) {
    const azul = Color(0xFF1D81C7);
    final dias = streak.dias;
    return Dialog(
      backgroundColor: Colors.transparent,
      child: Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: temaEscuro.value ? const Color(0xFF111111) : Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: const Color(0xFFFF6D00).withOpacity(0.4)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('🔥', style: TextStyle(fontSize: 48)),
            const SizedBox(height: 8),
            Text(
              '$dias dias seguidos!',
              style: TextStyle(
                fontSize: 22, fontWeight: FontWeight.bold,
                color: _tc(),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              streak.acendeuHoje
                  ? 'Estudaste hoje. Continua assim!'
                  : 'Estuda hoje para não perder a streak!',
              style: TextStyle(color: _tc54(), fontSize: 13),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 20),
            const Divider(),
            const SizedBox(height: 12),
            const Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'Conquistas de streak',
                style: TextStyle(
                  color: azul, fontSize: 14, fontWeight: FontWeight.bold,
                ),
              ),
            ),
            const SizedBox(height: 10),
            ...StreakInfo.conquistas.map((c) {
              final meta = c['dias'] as int;
              final conquistada = dias >= meta;
              return Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  children: [
                    Text(c['icon'] as String,
                      style: TextStyle(
                        fontSize: 20,
                        color: conquistada ? null : null,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            c['label'] as String,
                            style: TextStyle(
                              color: conquistada ? _tc() : _tc38(),
                              fontWeight: conquistada
                                  ? FontWeight.bold
                                  : FontWeight.normal,
                              fontSize: 14,
                            ),
                          ),
                          LinearProgressIndicator(
                            value: (dias / meta).clamp(0.0, 1.0),
                            backgroundColor: _tc12(),
                            color: conquistada
                                ? const Color(0xFFFF6D00)
                                : azul,
                            minHeight: 3,
                            borderRadius: BorderRadius.circular(4),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    if (conquistada)
                      const Icon(Icons.check_circle, color: Color(0xFFFF6D00), size: 16)
                    else
                      Text(
                        '$meta',
                        style: TextStyle(color: _tc38(), fontSize: 12),
                      ),
                  ],
                ),
              );
            }),
            const SizedBox(height: 12),
            // ── Streak Freeze ──────────────────────────────────────
            if (!streak.acendeuHoje && !streak.frozenHoje) ...[
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: freezesDisponiveis > 0 && onUsarFreeze != null
                      ? () async {
                          await onUsarFreeze!();
                          if (context.mounted) Navigator.pop(context);
                        }
                      : null,
                  icon: const Text('🧊', style: TextStyle(fontSize: 16)),
                  label: Text(
                    freezesDisponiveis > 0
                        ? 'Usar Streak Freeze ($freezesDisponiveis disponíveis)'
                        : 'Sem Streak Freezes disponíveis',
                    style: const TextStyle(fontSize: 13),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF1565C0),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'Ganhas 1 freeze a cada 7 dias de streak consecutivos',
                style: TextStyle(color: _tc38(), fontSize: 11),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),
            ],
            if (streak.frozenHoje) ...[
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                margin: const EdgeInsets.only(bottom: 12),
                decoration: BoxDecoration(
                  color: const Color(0xFF1565C0).withOpacity(0.12),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: const Color(0xFF1565C0).withOpacity(0.4)),
                ),
                child: const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text('🧊', style: TextStyle(fontSize: 16)),
                    SizedBox(width: 8),
                    Text('Streak protegida por freeze hoje!', style: TextStyle(color: Color(0xFF42A5F5), fontSize: 13)),
                  ],
                ),
              ),
            ],
            // ── Botão partilhar streak ──────────────────────────────
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: () {
                  Navigator.pop(context);
                  final keyStreakCard = GlobalKey();
                  final texto = [
                    '🔥 $dias ${dias == 1 ? 'dia' : 'dias'} de estudo seguidos no THOTH!',
                    streak.acendeuHoje ? 'Streak activa hoje! 💪' : 'A minha streak de estudo',
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
                          acendeuHoje: streak.acendeuHoje,
                          conquistas: StreakInfo.conquistas,
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
                        await _partilharImagem(key: keyStreakCard, texto: texto);
                      },
                    ),
                  );
                },
                icon: const Icon(Icons.ios_share_rounded, size: 16, color: Color(0xFFFF6D00)),
                label: const Text(
                  'Partilhar streak',
                  style: TextStyle(color: Color(0xFFFF6D00)),
                ),
                style: OutlinedButton.styleFrom(
                  side: const BorderSide(color: Color(0x66FF6D00)),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  padding: const EdgeInsets.symmetric(vertical: 11),
                ),
              ),
            ),
            const SizedBox(height: 6),
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Fechar', style: TextStyle(color: azul)),
            ),
          ],
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
        title: const Text('Gerir Tarefas'),
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
                state._guardarTudo();
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

                  // DND indicator
                  if (state._modoDNDAtivo)
                    Padding(
                      padding: const EdgeInsets.only(top: 4, bottom: 4),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.do_not_disturb_on, size: 13, color: Color(0xFF1D81C7)),
                          const SizedBox(width: 4),
                          Text('Modo não perturbar activo', style: TextStyle(color: _tc38(), fontSize: 11)),
                        ],
                      ),
                    ),

                  // Task name ──────────────────────────────────────────────────
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
    },
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
  File? _fotoLocal;        // foto nova escolhida localmente
  String _fotoUrl = '';    // URL existente guardada no Firestore
  bool _aCarregarFoto = false;

  static const Color azul = Color(0xFF1D81C7);

  @override
  void initState() {
    super.initState();
    _nomeCtrl     = TextEditingController(text: widget.perfil.nome);
    _usernameCtrl = TextEditingController(text: widget.perfil.nomedeutilizador);
    _descCtrl     = TextEditingController(text: widget.perfil.descricao);
    _motivosCtrl  = TextEditingController(text: widget.perfil.motivos);
    _fotoUrl      = widget.perfil.fotoUrl;
  }

  @override
  void dispose() {
    _nomeCtrl.dispose();
    _usernameCtrl.dispose();
    _descCtrl.dispose();
    _motivosCtrl.dispose();
    super.dispose();
  }

  Future<void> _escolherFoto() async {
    // Em desktop não há câmara, vamos direto para o file picker
    if (_isDesktop) {
      final picker = ImagePicker();
      final picked = await picker.pickImage(source: ImageSource.gallery, imageQuality: 75, maxWidth: 512);
      if (picked == null || !mounted) return;
      setState(() => _fotoLocal = File(picked.path));
      return;
    }

    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      backgroundColor: const Color(0xFF111111),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 12),
            ListTile(
              leading: const Icon(Icons.camera_alt, color: azul),
              title: const Text('Tirar foto', style: TextStyle(color: Colors.white)),
              onTap: () => Navigator.pop(ctx, ImageSource.camera),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library, color: azul),
              title: const Text('Escolher da galeria', style: TextStyle(color: Colors.white)),
              onTap: () => Navigator.pop(ctx, ImageSource.gallery),
            ),
            if (_fotoLocal != null || _fotoUrl.isNotEmpty)
              ListTile(
                leading: const Icon(Icons.delete_outline, color: Colors.redAccent),
                title: const Text('Remover foto', style: TextStyle(color: Colors.redAccent)),
                onTap: () => Navigator.pop(ctx, null),
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );

    if (!mounted) return;

    if (source == null && (_fotoLocal != null || _fotoUrl.isNotEmpty)) {
      // Remover foto
      setState(() { _fotoLocal = null; _fotoUrl = ''; });
      return;
    }
    if (source == null) return;

    final picker = ImagePicker();
    final picked = await picker.pickImage(source: source, imageQuality: 75, maxWidth: 512);
    if (picked == null || !mounted) return;
    setState(() => _fotoLocal = File(picked.path));
  }

  Future<String> _uploadFoto(File foto) async {
    // Codificar em base64 e guardar no Firestore (evita Firebase Storage no plano Spark)
    final bytes = await foto.readAsBytes();
    return 'data:image/jpeg;base64,${base64Encode(bytes)}';
  }

  // Valida que o username só contém letras, números, pontos e underscores
  bool _usernameValido(String u) =>
      u.isEmpty || RegExp(r'^[a-zA-Z0-9._]{3,20}$').hasMatch(u);

  Future<bool> _usernameDisponivel(String username) async {
    if (username.isEmpty) return true;
    final uid = FirebaseAuth.instance.currentUser!.uid;
    final doc = await FirebaseFirestore.instance
        .collection('usernames')
        .doc(username.toLowerCase())
        .get();
    if (!doc.exists) return true;
    // É o próprio utilizador
    return (doc.data()?['uid'] as String?) == uid;
  }

  Future<void> _guardar() async {
    final novoUsername = _usernameCtrl.text.trim();

    if (!_usernameValido(novoUsername)) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Username inválido. Usa entre 3-20 caracteres: letras, números, . e _'),
          backgroundColor: Colors.redAccent,
        ));
      }
      return;
    }

    setState(() => _aCarregarFoto = true);

    try {
      // Verificar unicidade do username (só se não estiver vazio)
      if (novoUsername.isNotEmpty) {
        final disponivel = await _usernameDisponivel(novoUsername);
        if (!disponivel) {
          if (mounted) {
            setState(() => _aCarregarFoto = false);
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(
              content: Text('@$novoUsername já está em uso. Escolhe outro.'),
              backgroundColor: Colors.redAccent,
            ));
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
            citacao: widget.perfil.citacao,
            fotoUrl: fotoFinal,
          ),
        );
      }
    } catch (e) {
      debugPrint('Erro ao guardar perfil: $e');
      if (mounted) {
        setState(() => _aCarregarFoto = false);
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Erro ao guardar. Tenta novamente.'),
          backgroundColor: Colors.redAccent,
        ));
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
                  child: SizedBox(width: 20, height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2, color: azul)),
                )
              : IconButton(
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
            // Avatar com foto alterável
            Center(
              child: GestureDetector(
                onTap: _escolherFoto,
                child: Stack(
                  children: [
                    CircleAvatar(
                      radius: 60,
                      backgroundColor: azul,
                      backgroundImage: _fotoLocal != null
                          ? FileImage(_fotoLocal!) as ImageProvider<Object>
                          : (_fotoUrl.isNotEmpty && _fotoUrl.startsWith('data:'))
                              ? MemoryImage(base64Decode(_fotoUrl.split(',').last)) as ImageProvider<Object>
                              : (_fotoUrl.isNotEmpty ? NetworkImage(_fotoUrl) as ImageProvider<Object> : null),
                      child: (_fotoLocal == null && _fotoUrl.isEmpty)
                          ? Text(
                              _nomeCtrl.text.isNotEmpty
                                  ? _nomeCtrl.text[0].toUpperCase()
                                  : 'T',
                              style: TextStyle(
                                fontSize: 50,
                                color: _tc(),
                                fontWeight: FontWeight.bold,
                              ),
                            )
                          : null,
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
            ),
            const SizedBox(height: 8),
            Text('Toca para alterar a foto',
              style: TextStyle(color: _tc().withOpacity(0.4), fontSize: 12)),
            const SizedBox(height: 22),

            _campo('Nome', _nomeCtrl, 'Insira o seu nome...'),
            _campo('Username (@)', _usernameCtrl, 'ex: mestre_foco  (3-20 caracteres)',
                hint2: 'Letras, números, . e _ · Deve ser único'),
            _campo('Descrição', _descCtrl, 'Escreva algo sobre si...', maxLines: 3),
            _campo(
              'Motivações para usar o Thoth',
              _motivosCtrl,
              'Ex: Melhorar a gestão de tempo...',
              maxLines: 3,
            ),
            const SizedBox(height: 20),

            // ── Partilhar perfil ──────────────────────────────────
            if (widget.perfil.nomedeutilizador.isNotEmpty) ...[
              OutlinedButton.icon(
                onPressed: () {
                  final username = widget.perfil.nomedeutilizador;
                  Clipboard.setData(ClipboardData(text: '@$username'));
                  Share.share(
                    'Segue o meu progresso no Thoth! 📚\n'
                    'Pesquisa por @$username na aba de Amigos para me adicionares.',
                    subject: 'O meu perfil Thoth — @$username',
                  );
                },
                style: OutlinedButton.styleFrom(
                  foregroundColor: azul,
                  side: const BorderSide(color: azul),
                  minimumSize: const Size(double.infinity, 48),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                icon: const Icon(Icons.ios_share_rounded, size: 18),
                label: Text('Partilhar perfil  @${widget.perfil.nomedeutilizador}'),
              ),
              const SizedBox(height: 12),
            ],

            ElevatedButton(
              onPressed: _aCarregarFoto ? null : _guardar,
              style: ElevatedButton.styleFrom(
                backgroundColor: azul,
                foregroundColor: Colors.white,
                minimumSize: const Size(double.infinity, 52),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              child: const Text('GUARDAR PERFIL',
                style: TextStyle(fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _campo(String label, TextEditingController ctrl, String hint,
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
          helperStyle: TextStyle(color: _tc().withOpacity(0.4), fontSize: 11),
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
  final String? todoBlocosJson;

  const TelaTodo({super.key, required this.lista, this.todoBlocosJson});

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
    for (final key in _blocos.keys) {
      _blocos[key] = [];
    }
    _carregarBlocos();
  }

  FirebaseFirestore get _db => FirebaseFirestore.instance;
  String get _uid => FirebaseAuth.instance.currentUser!.uid;
  CollectionReference get _todoCol => _db.collection('users').doc(_uid).collection('todo');

  Future<void> _carregarBlocos() async {
    // Tentar dados passados do estado pai primeiro
    if (widget.todoBlocosJson != null) {
      final m = jsonDecode(widget.todoBlocosJson!) as Map<String, dynamic>;
      setState(() {
        for (final entry in m.entries) {
          if (_blocos.containsKey(entry.key)) {
            final raw = entry.value;
            if (raw is Map) {
              // formato Firestore: {itens: [...]}
              final list = (raw['itens'] as List<dynamic>?) ?? [];
              _blocos[entry.key] = list
                  .map((e) => ItemTodo.fromJson(e as Map<String, dynamic>))
                  .toList();
            }
          }
        }
      });
      return;
    }
    // Fallback: ler do Firestore diretamente
    final snap = await _todoCol.get();
    if (snap.docs.isNotEmpty) {
      setState(() {
        for (final doc in snap.docs) {
          if (_blocos.containsKey(doc.id)) {
            final data = doc.data() as Map<String, dynamic>;
            final list = (data['itens'] as List<dynamic>?) ?? [];
            _blocos[doc.id] = list
                .map((e) => ItemTodo.fromJson(e as Map<String, dynamic>))
                .toList();
          }
        }
      });
    } else {
      setState(() => _blocos['Tarefas para hoje']!.addAll(widget.lista));
      await _guardarBlocos();
    }
  }

  Future<void> _guardarBlocos() async {
    final batch = _db.batch();
    for (final entry in _blocos.entries) {
      batch.set(
        _todoCol.doc(entry.key),
        {'itens': entry.value.map((i) => i.toJson()).toList()},
      );
    }
    await batch.commit();
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
      _blocos[item.concluido ? 'Acabadas' : 'Por fazer!!']!.add(item);
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
    final streak = StreakInfo.calcular(sessoes);

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
        actions: [
          IconButton(
            icon: const Icon(Icons.share_outlined),
            tooltip: 'Partilhar',
            onPressed: () => _partilhar(context, streak, totalFoco, totalCiclos, sessoes.length),
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
                  // ── Streak card ─────────────────────────────────────
                  GestureDetector(
                    onTap: () => showDialog(
                      context: context,
                      builder: (_) => _StreakDialog(streak: streak),
                    ),
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(16),
                      margin: const EdgeInsets.only(bottom: 16),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: streak.acendeuHoje
                              ? [const Color(0xFFFF6D00).withOpacity(0.15), const Color(0xFFFFCC02).withOpacity(0.08)]
                              : [azul.withOpacity(0.08), azul.withOpacity(0.04)],
                        ),
                        border: Border.all(
                          color: streak.acendeuHoje
                              ? const Color(0xFFFF6D00).withOpacity(0.5)
                              : azul.withOpacity(0.3),
                        ),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Row(
                        children: [
                          Text('🔥', style: const TextStyle(fontSize: 36)),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  '${streak.dias} dias seguidos',
                                  style: TextStyle(
                                    color: _tc(),
                                    fontSize: 20,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                Text(
                                  streak.acendeuHoje
                                      ? 'Streak activa hoje! 💪'
                                      : 'Estuda hoje para manter a streak',
                                  style: TextStyle(color: _tc54(), fontSize: 12),
                                ),
                              ],
                            ),
                          ),
                          const Icon(Icons.chevron_right, color: Colors.white38),
                        ],
                      ),
                    ),
                  ),

                  // ── Conquistas ──────────────────────────────────────
                  const Text(
                    'Conquistas',
                    style: TextStyle(color: azul, fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    height: 90,
                    child: ListView(
                      scrollDirection: Axis.horizontal,
                      children: StreakInfo.conquistas.map((c) {
                        final conquistada = streak.dias >= (c['dias'] as int);
                        return Container(
                          width: 72,
                          margin: const EdgeInsets.only(right: 10),
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: conquistada
                                ? const Color(0xFFFF6D00).withOpacity(0.12)
                                : _tc().withOpacity(0.04),
                            border: Border.all(
                              color: conquistada
                                  ? const Color(0xFFFF6D00).withOpacity(0.6)
                                  : _tc().withOpacity(0.1),
                            ),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text(
                                c['icon'] as String,
                                style: TextStyle(
                                  fontSize: 24,
                                  color: conquistada ? null : null,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                c['label'] as String,
                                style: TextStyle(
                                  fontSize: 9,
                                  color: conquistada ? _tc() : _tc38(),
                                  fontWeight: conquistada ? FontWeight.bold : FontWeight.normal,
                                ),
                                textAlign: TextAlign.center,
                              ),
                            ],
                          ),
                        );
                      }).toList(),
                    ),
                  ),
                  const SizedBox(height: 20),

                  // Botão partilhar
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: () => _partilhar(context, streak, totalFoco, totalCiclos, sessoes.length),
                      icon: const Icon(Icons.share_outlined, color: azul, size: 18),
                      label: const Text('Partilhar os meus insights', style: TextStyle(color: azul)),
                      style: OutlinedButton.styleFrom(
                        side: BorderSide(color: azul.withOpacity(0.5)),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),

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

  void _partilhar(BuildContext context, StreakInfo streak, int totalFoco, int totalCiclos, int totalSessoes) {
    final keyInsights = GlobalKey();

    // Tarefa mais estudada
    final contagem = <String, int>{};
    for (final s in sessoes) {
      contagem[s.tarefaNome] = (contagem[s.tarefaNome] ?? 0) + s.tempoFocoSegundos;
    }
    String? tarefaMaisEstudada;
    if (contagem.isNotEmpty) {
      tarefaMaisEstudada = contagem.entries.reduce((a, b) => a.value > b.value ? a : b).key;
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
          await _partilharImagem(key: keyInsights, texto: texto);
        },
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
  bool   _notifs   = true;
  bool   _privado  = false;
  bool   _modoDND  = false;
  bool   _loadingPrefs = true;

  static const azul = Color(0xFF1D81C7);

  FirebaseFirestore get _db => FirebaseFirestore.instance;
  String get _uid => FirebaseAuth.instance.currentUser!.uid;
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
          _notifs  = d['notificacoes'] as bool? ?? true;
          _privado = d['contaPrivada']  as bool? ?? false;
          _modoDND = d['modoDNDAtivo']  as bool? ?? false;
        });
      }
    } catch (_) {}
    if (mounted) setState(() => _loadingPrefs = false);
  }

  Future<void> _guardarPreferencia(String campo, bool valor) async {
    try {
      await _configDoc.set({campo: valor}, SetOptions(merge: true));
      // Gerir notificações diárias conforme preferência
      if (campo == 'notificacoes') {
        if (valor) {
          await _agendarNotificacaoDiaria();
        } else {
          await _notifPlugin.cancelAll();
        }
      }
    } catch (_) {}
  }

  // Dados reais da conta Google
  String get _account {
    // Nome de utilizador do perfil Thoth, ou displayName do Google, ou 'Utilizador'
    final user = FirebaseAuth.instance.currentUser;
    return user?.displayName ?? 'Utilizador';
  }
  String get _email => FirebaseAuth.instance.currentUser?.email ?? '';

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

  // ✨ NOVO: Limpar a sessão guardada
  await SessionPersistenceService.clearSession();

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

              // Account — apenas leitura (nome do Google)
              _tile(Icons.account_circle_outlined, 'Account', _account, fg, fgMuted, tileBg, border,
                onTap: () {}, readOnly: true),

              // Email — apenas leitura (email do Google)
              _tile(Icons.mail_outline, 'Email', _email, fg, fgMuted, tileBg, border,
                onTap: () {}, readOnly: true),

              // Notificações (toggle)
              _tileToggle(Icons.notifications_outlined, 'Notificações', _notifs, fg, fgMuted, tileBg, border,
                onChanged: (v) {
                  setState(() => _notifs = v);
                  _guardarPreferencia('notificacoes', v);
                }),

              // Privacidade (toggle)
              _tileToggle(Icons.lock_outline, 'Privacidade', _privado, fg, fgMuted, tileBg, border,
                onChanged: (v) {
                  setState(() => _privado = v);
                  _guardarPreferencia('contaPrivada', v);
                }),

              // Modo não perturbar
              _tileToggle(Icons.do_not_disturb_on_outlined, 'Não perturbar durante o timer', _modoDND, fg, fgMuted, tileBg, border,
                onChanged: (v) {
                  setState(() => _modoDND = v);
                  _guardarPreferencia('modoDNDAtivo', v);
                }),

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
      {required VoidCallback onTap, bool bold = false, bool readOnly = false}) {
    return GestureDetector(
      onTap: readOnly ? null : onTap,
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
            Flexible(
              child: Text(valor,
                style: TextStyle(color: fgMuted, fontSize: 13),
                overflow: TextOverflow.ellipsis,
                maxLines: 1,
                textAlign: TextAlign.end,
              ),
            )
          else if (!bold && !readOnly)
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
// TELA AMIGOS
// =============================================================================

class TelaAmigos extends StatefulWidget {
  final String uid;
  const TelaAmigos({super.key, required this.uid});

  @override
  State<TelaAmigos> createState() => _TelaAmigosState();
}

class _TelaAmigosState extends State<TelaAmigos> {
  static const azul = Color(0xFF1D81C7);
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  List<Map<String, dynamic>> _amigos = [];
  List<Map<String, dynamic>> _pedidos = [];
  bool _loading = true;
  final TextEditingController _searchCtrl = TextEditingController();
  List<Map<String, dynamic>> _resultados = [];
  bool _searching = false;
  StreamSubscription<QuerySnapshot>? _pedidosSub;

  @override
  void initState() {
    super.initState();
    _carregarAmigos();
    // Stream real-time para pedidos pendentes
    // Filtra só por 'para' para não precisar de índice composto no Firestore
    _pedidosSub = _db
        .collection('pedidos_amizade')
        .where('para', isEqualTo: widget.uid)
        .snapshots()
        .listen((snap) async {
      final pedidos = <Map<String, dynamic>>[];
      for (final doc in snap.docs) {
        // Filtrar pendentes em código (evita índice composto)
        final estado = doc.data()['estado'] as String? ?? '';
        if (estado != 'pendente') continue;
        final remetenteUid = doc.data()['de'] as String? ?? '';
        if (remetenteUid.isEmpty) continue;
        try {
          final perfilSnap = await _db
              .collection('users')
              .doc(remetenteUid)
              .collection('perfil')
              .doc('dados')
              .get();
          final perfil = perfilSnap.exists
              ? PerfilUsuario.fromJson(perfilSnap.data()!)
              : PerfilUsuario();
          pedidos.add({'uid': remetenteUid, 'perfil': perfil, 'docId': doc.id});
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

  Future<void> _carregar() => _carregarAmigos();

  Future<void> _carregarAmigos() async {
    setState(() => _loading = true);
    try {
      // Amigos aceites — lidos da subcoleção do próprio utilizador
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
            .map((d) => SessaoConcluida.fromJson(d.data()))
            .toList();
        final streak = StreakInfo.calcular(sessoes);
        final totalFoco = sessoes.fold<int>(0, (s, e) => s + e.tempoFocoSegundos);
        final perfil = perfilSnap.exists
            ? PerfilUsuario.fromJson(perfilSnap.data()!)
            : PerfilUsuario();
        amigos.add({
          'uid': amigoUid,
          'perfil': perfil,
          'streak': streak,
          'totalFoco': totalFoco,
          'totalSessoes': sessoes.length,
        });
      }

      if (mounted) setState(() { _amigos = amigos; _loading = false; });
    } catch (e) {
      debugPrint('Erro ao carregar amigos: $e');
      if (mounted) setState(() => _loading = false);
    }
  }
  Future<void> _pesquisar(String query) async {
    if (query.trim().isEmpty) { setState(() => _resultados = []); return; }
    setState(() => _searching = true);
    try {
      final q = query.trim().toLowerCase().replaceFirst(RegExp(r'^@'), '');
      final results = <Map<String, dynamic>>[];

      // 1. Pesquisa exacta por @username no índice global
      final usernameDoc = await _db.collection('usernames').doc(q).get();
      if (usernameDoc.exists) {
        final uid = usernameDoc.data()!['uid'] as String? ?? '';
        if (uid.isNotEmpty && uid != widget.uid) {
          final perfilSnap = await _db
              .collection('users').doc(uid).collection('perfil').doc('dados').get();
          if (perfilSnap.exists) {
            final perfil = PerfilUsuario.fromJson(perfilSnap.data()!);
            final jaAmigo = _amigos.any((a) => a['uid'] == uid);
            final jaPedido = _pedidos.any((p) => p['uid'] == uid);
            results.add({'uid': uid, 'perfil': perfil, 'jaAmigo': jaAmigo, 'jaPedido': jaPedido});
          }
        }
      }

      // 2. Pesquisa parcial por nome/username — sem orderBy, não precisa de índice
      if (q.length >= 2) {
        final snap = await _db.collection('usernames').get();
        for (final doc in snap.docs) {
          final uid = doc.data()['uid'] as String? ?? '';
          if (uid.isEmpty || uid == widget.uid) continue;
          if (results.any((r) => r['uid'] == uid)) continue;
          final nome = (doc.data()['nome'] as String? ?? '').toLowerCase();
          final username = (doc.data()['nomedeutilizador'] as String? ?? '').toLowerCase();
          if (!nome.contains(q) && !username.contains(q)) continue;
          final perfilSnap = await _db
              .collection('users').doc(uid).collection('perfil').doc('dados').get();
          if (!perfilSnap.exists) continue;
          final perfil = PerfilUsuario.fromJson(perfilSnap.data()!);
          final jaAmigo = _amigos.any((a) => a['uid'] == uid);
          final jaPedido = _pedidos.any((p) => p['uid'] == uid);
          results.add({'uid': uid, 'perfil': perfil, 'jaAmigo': jaAmigo, 'jaPedido': jaPedido});
        }
      }

      if (mounted) setState(() { _resultados = results; _searching = false; });
    } catch (e) {
      debugPrint('Erro na pesquisa: $e');
      if (mounted) setState(() => _searching = false);
    }
  }

  Future<void> _enviarPedido(String amigoUid) async {
    try {
      // Escreve na coleção global — qualquer utilizador autenticado pode escrever
      await _db.collection('pedidos_amizade').add({
        'de': widget.uid,
        'para': amigoUid,
        'estado': 'pendente',
        'data': FieldValue.serverTimestamp(),
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Pedido de amizade enviado!')),
        );
        setState(() {
          for (final r in _resultados) {
            if (r['uid'] == amigoUid) r['jaPedido'] = true;
          }
        });
      }
    } catch (e) {
      debugPrint('Erro ao enviar pedido: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Erro ao enviar pedido. Tenta novamente.'),
              backgroundColor: Colors.redAccent),
        );
      }
    }
  }

  Future<void> _aceitarPedido(String remetenteUid, String docId) async {
    try {
      final batch = _db.batch();
      // Marca amizade nos dois perfis
      batch.set(
        _db.collection('users').doc(widget.uid).collection('amigos').doc(remetenteUid),
        {'estado': 'aceite'},
      );
      batch.set(
        _db.collection('users').doc(remetenteUid).collection('amigos').doc(widget.uid),
        {'estado': 'aceite'},
      );
      // Apaga o pedido da coleção global
      batch.delete(_db.collection('pedidos_amizade').doc(docId));
      await batch.commit();
      _carregar();
    } catch (e) {
      debugPrint('Erro ao aceitar pedido: $e');
    }
  }

  Future<void> _recusarPedido(String remetenteUid, String docId) async {
    try {
      await _db.collection('pedidos_amizade').doc(docId).delete();
      _carregar();
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
            ? const Center(child: CircularProgressIndicator())
            : SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // ── Pesquisa ──────────────────────────────────────
                    TextField(
                      controller: _searchCtrl,
                      style: TextStyle(color: _tc()),
                      decoration: InputDecoration(
                        hintText: 'Pesquisar por @username ou nome...',
                        hintStyle: TextStyle(color: _tc38()),
                        prefixIcon: Icon(Icons.search, color: _tc54()),
                        suffixIcon: _searching
                            ? const Padding(
                                padding: EdgeInsets.all(12),
                                child: SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
                              )
                            : null,
                        enabledBorder: OutlineInputBorder(
                          borderSide: BorderSide(color: _tc24()),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        focusedBorder: const OutlineInputBorder(
                          borderSide: BorderSide(color: azul),
                          borderRadius: BorderRadius.all(Radius.circular(12)),
                        ),
                      ),
                      onChanged: (v) => Future.delayed(
                        const Duration(milliseconds: 500),
                        () { if (_searchCtrl.text == v) _pesquisar(v); },
                      ),
                    ),

                    // ── Partilhar o meu perfil ─────────────────────
                    FutureBuilder<DocumentSnapshot>(
                      future: FirebaseFirestore.instance
                          .collection('users').doc(widget.uid)
                          .collection('perfil').doc('dados').get(),
                      builder: (ctx, snap) {
                        if (!snap.hasData || !snap.data!.exists) return const SizedBox.shrink();
                        final perfil = PerfilUsuario.fromJson(snap.data!.data() as Map<String, dynamic>);
                        if (perfil.nomedeutilizador.isEmpty) {
                          return Padding(
                            padding: const EdgeInsets.only(top: 10, bottom: 4),
                            child: Text(
                              '💡 Define um @username no teu perfil para partilhares o teu link.',
                              style: TextStyle(color: _tc38(), fontSize: 12),
                            ),
                          );
                        }
                        return Padding(
                          padding: const EdgeInsets.only(top: 10),
                          child: OutlinedButton.icon(
                            onPressed: () {
                              // Copia o username para a área de transferência
                              Clipboard.setData(ClipboardData(
                                text: '@${perfil.nomedeutilizador}',
                              ));
                              Share.share(
                                'Adiciona-me no Thoth! 📚\n'
                                'Pesquisa por @${perfil.nomedeutilizador} na aba de Amigos.',
                                subject: 'O meu perfil no Thoth',
                              );
                            },
                            style: OutlinedButton.styleFrom(
                              foregroundColor: azul,
                              side: const BorderSide(color: azul),
                              minimumSize: const Size(double.infinity, 44),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            ),
                            icon: const Icon(Icons.ios_share_rounded, size: 16),
                            label: Text('Partilhar  @${perfil.nomedeutilizador}'),
                          ),
                        );
                      },
                    ),
                    const SizedBox(height: 8),

                    if (_resultados.isNotEmpty) ...[
                      const SizedBox(height: 12),
                      const Text('Resultados', style: TextStyle(color: azul, fontSize: 14, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 8),
                      ..._resultados.map((r) {
                        final perfil = r['perfil'] as PerfilUsuario;
                        final jaAmigo = r['jaAmigo'] as bool? ?? false;
                        final jaPedido = r['jaPedido'] as bool? ?? false;
                        return Container(
                          margin: const EdgeInsets.only(bottom: 8),
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                          decoration: BoxDecoration(
                            border: Border.all(color: _tc24()),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Row(
                            children: [
                              CircleAvatar(
                                radius: 20,
                                backgroundColor: azul.withOpacity(0.15),
                                child: Text(
                                  perfil.nome.isNotEmpty ? perfil.nome[0].toUpperCase() : '?',
                                  style: const TextStyle(color: azul, fontWeight: FontWeight.bold),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(perfil.nome, style: TextStyle(color: _tc(), fontWeight: FontWeight.bold)),
                                    if (perfil.nomedeutilizador.isNotEmpty)
                                      Text('@${perfil.nomedeutilizador}', style: TextStyle(color: _tc54(), fontSize: 12)),
                                  ],
                                ),
                              ),
                              if (jaAmigo)
                                const Icon(Icons.check_circle, color: azul, size: 20)
                              else if (jaPedido)
                                Text('Enviado', style: TextStyle(color: _tc38(), fontSize: 12))
                              else
                                IconButton(
                                  icon: const Icon(Icons.person_add_outlined, color: azul),
                                  onPressed: () => _enviarPedido(r['uid'] as String),
                                  tooltip: 'Adicionar amigo',
                                ),
                            ],
                          ),
                        );
                      }),
                      const Divider(height: 24),
                    ],

                    // ── Inbox de pedidos ────────────────────────────
                    Container(
                      margin: const EdgeInsets.only(bottom: 20),
                      decoration: BoxDecoration(
                        border: Border.all(
                          color: _pedidos.isNotEmpty ? azul.withOpacity(0.5) : _tc().withOpacity(0.1),
                        ),
                        borderRadius: BorderRadius.circular(14),
                        color: _pedidos.isNotEmpty ? azul.withOpacity(0.06) : Colors.transparent,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Padding(
                            padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
                            child: Row(
                              children: [
                                const Icon(Icons.inbox_rounded, color: azul, size: 18),
                                const SizedBox(width: 8),
                                const Text('Pedidos de amizade',
                                    style: TextStyle(color: azul, fontSize: 14, fontWeight: FontWeight.bold)),
                                const SizedBox(width: 8),
                                if (_pedidos.isNotEmpty)
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                                    decoration: BoxDecoration(color: azul, borderRadius: BorderRadius.circular(10)),
                                    child: Text('${_pedidos.length}',
                                        style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold)),
                                  ),
                              ],
                            ),
                          ),
                          if (_pedidos.isEmpty)
                            Padding(
                              padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
                              child: Text('Nenhum pedido pendente', style: TextStyle(color: _tc38(), fontSize: 13)),
                            )
                          else
                            ..._pedidos.map((p) {
                              final perfil = p['perfil'] as PerfilUsuario;
                              return Container(
                                margin: const EdgeInsets.fromLTRB(10, 0, 10, 10),
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                                decoration: BoxDecoration(
                                  color: _tc().withOpacity(0.04),
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: Row(
                                  children: [
                                    CircleAvatar(
                                      radius: 20,
                                      backgroundColor: azul.withOpacity(0.15),
                                      backgroundImage: perfil.fotoUrl.isNotEmpty ? NetworkImage(perfil.fotoUrl) as ImageProvider : null,
                                      child: perfil.fotoUrl.isEmpty
                                          ? Text(perfil.nome.isNotEmpty ? perfil.nome[0].toUpperCase() : '?',
                                              style: const TextStyle(color: azul, fontWeight: FontWeight.bold))
                                          : null,
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(perfil.nome.isNotEmpty ? perfil.nome : 'Utilizador',
                                              style: TextStyle(color: _tc(), fontWeight: FontWeight.bold, fontSize: 14)),
                                          if (perfil.nomedeutilizador.isNotEmpty)
                                            Text('@${perfil.nomedeutilizador}', style: TextStyle(color: _tc54(), fontSize: 12)),
                                        ],
                                      ),
                                    ),
                                    IconButton(
                                      icon: const Icon(Icons.close_rounded, color: Colors.redAccent, size: 22),
                                      tooltip: 'Recusar',
                                      onPressed: () => _recusarPedido(p['uid'] as String, p['docId'] as String),
                                    ),
                                    ElevatedButton(
                                      onPressed: () => _aceitarPedido(p['uid'] as String, p['docId'] as String),
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: azul,
                                        foregroundColor: Colors.white,
                                        minimumSize: const Size(72, 34),
                                        padding: const EdgeInsets.symmetric(horizontal: 12),
                                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                      ),
                                      child: const Text('Aceitar', style: TextStyle(fontSize: 13)),
                                    ),
                                  ],
                                ),
                              );
                            }),
                        ],
                      ),
                    ),

                    // ── Lista de amigos ──────────────────────────────
                    Row(
                      children: [
                        Text(
                          'Os meus amigos',
                          style: const TextStyle(color: azul, fontSize: 16, fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(width: 8),
                        Text('(${_amigos.length})', style: TextStyle(color: _tc38(), fontSize: 14)),
                      ],
                    ),
                    const SizedBox(height: 12),

                    // ── Reacções não lidas ──────────────────────────
                    StreamBuilder<QuerySnapshot>(
                      stream: FirebaseFirestore.instance
                          .collection('users')
                          .doc(widget.uid)
                          .collection('reacoes')
                          .where('lida', isEqualTo: false)
                          .orderBy('criadaEm', descending: true)
                          .limit(10)
                          .snapshots(),
                      builder: (ctx, snapR) {
                        if (!snapR.hasData || snapR.data!.docs.isEmpty) return const SizedBox.shrink();
                        final reacoes = snapR.data!.docs;
                        return Container(
                          margin: const EdgeInsets.only(bottom: 16),
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            border: Border.all(color: const Color(0xFF1D81C7).withOpacity(0.4)),
                            borderRadius: BorderRadius.circular(14),
                            color: const Color(0xFF1D81C7).withOpacity(0.05),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  const Icon(Icons.favorite_outline, color: Color(0xFF1D81C7), size: 16),
                                  const SizedBox(width: 6),
                                  const Text('Novas reacções', style: TextStyle(color: Color(0xFF1D81C7), fontWeight: FontWeight.bold, fontSize: 14)),
                                  const SizedBox(width: 6),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                                    decoration: BoxDecoration(color: const Color(0xFF1D81C7), borderRadius: BorderRadius.circular(8)),
                                    child: Text('${reacoes.length}', style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)),
                                  ),
                                  const Spacer(),
                                  TextButton(
                                    onPressed: () async {
                                      final batch = FirebaseFirestore.instance.batch();
                                      for (final doc in reacoes) {
                                        batch.update(doc.reference, {'lida': true});
                                      }
                                      await batch.commit();
                                    },
                                    style: TextButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 6)),
                                    child: Text('Marcar lidas', style: TextStyle(color: _tc38(), fontSize: 11)),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 10),
                              Wrap(
                                spacing: 8,
                                runSpacing: 8,
                                children: reacoes.map((doc) {
                                  final data = doc.data() as Map<String, dynamic>;
                                  final emoji = data['emoji'] as String? ?? '👏';
                                  final de = data['de'] as String? ?? '';
                                  final amigo = _amigos.firstWhere((a) => a['uid'] == de, orElse: () => {});
                                  final nomeAmigo = amigo.isNotEmpty
                                      ? (amigo['perfil'] as PerfilUsuario).nome
                                      : 'Amigo';
                                  return Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                    decoration: BoxDecoration(
                                      color: _tc().withOpacity(0.06),
                                      borderRadius: BorderRadius.circular(20),
                                      border: Border.all(color: _tc().withOpacity(0.1)),
                                    ),
                                    child: Text('$emoji  $nomeAmigo', style: TextStyle(color: _tc(), fontSize: 13)),
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
                          padding: const EdgeInsets.symmetric(vertical: 40),
                          child: Column(
                            children: [
                              Icon(Icons.group_outlined, size: 56, color: _tc().withOpacity(0.15)),
                              const SizedBox(height: 12),
                              Text('Ainda sem amigos', style: TextStyle(color: _tc38(), fontSize: 15)),
                              const SizedBox(height: 6),
                              Text('Pesquisa pelo nome para adicionar', style: TextStyle(color: _tc().withOpacity(0.2), fontSize: 12)),
                            ],
                          ),
                        ),
                      )
                    else
                      ..._amigos.map((a) {
                        final perfil = a['perfil'] as PerfilUsuario;
                        final streak = a['streak'] as StreakInfo;
                        final totalFoco = a['totalFoco'] as int;
                        final totalSessoes = a['totalSessoes'] as int;
                        return Container(
                          margin: const EdgeInsets.only(bottom: 12),
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            border: Border.all(color: _tc().withOpacity(0.1)),
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              // Header do amigo
                              Row(
                                children: [
                                  CircleAvatar(
                                    radius: 22,
                                    backgroundColor: azul.withOpacity(0.15),
                                    backgroundImage: perfil.fotoUrl.isNotEmpty
                                        ? NetworkImage(perfil.fotoUrl)
                                        : null,
                                    child: perfil.fotoUrl.isEmpty
                                        ? Text(
                                            perfil.nome.isNotEmpty ? perfil.nome[0].toUpperCase() : '?',
                                            style: const TextStyle(color: azul, fontWeight: FontWeight.bold, fontSize: 18),
                                          )
                                        : null,
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          perfil.nome.isNotEmpty ? perfil.nome : 'Sem nome',
                                          style: TextStyle(color: _tc(), fontWeight: FontWeight.bold, fontSize: 15),
                                        ),
                                        if (perfil.nomedeutilizador.isNotEmpty)
                                          Text('@${perfil.nomedeutilizador}', style: TextStyle(color: _tc38(), fontSize: 12)),
                                      ],
                                    ),
                                  ),
                                  // Streak badge do amigo
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                    decoration: BoxDecoration(
                                      color: streak.acendeuHoje
                                          ? const Color(0xFFFF6D00).withOpacity(0.15)
                                          : _tc().withOpacity(0.05),
                                      borderRadius: BorderRadius.circular(12),
                                      border: Border.all(
                                        color: streak.acendeuHoje
                                            ? const Color(0xFFFF6D00).withOpacity(0.5)
                                            : _tc24(),
                                      ),
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        const Text('🔥', style: TextStyle(fontSize: 14)),
                                        const SizedBox(width: 3),
                                        Text(
                                          '${streak.dias}',
                                          style: TextStyle(
                                            color: streak.acendeuHoje ? const Color(0xFFFFCC02) : _tc38(),
                                            fontWeight: FontWeight.bold,
                                            fontSize: 13,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 12),
                              // Stats + Reacção
                              Row(
                                children: [
                                  _statAmigo(Icons.timer_outlined, _fmtTempo(totalFoco), 'foco total'),
                                  const SizedBox(width: 20),
                                  _statAmigo(Icons.task_alt, '$totalSessoes', 'sessões'),
                                  const Spacer(),
                                  _BotaoReacao(amigoUid: a['uid'] as String, meuUid: widget.uid),
                                ],
                              ),
                              // Conquistas do amigo
                              if (streak.dias > 0) ...[
                                const SizedBox(height: 10),
                                Wrap(
                                  spacing: 4,
                                  children: StreakInfo.conquistas
                                      .where((c) => streak.dias >= (c['dias'] as int))
                                      .map((c) => Tooltip(
                                            message: c['label'] as String,
                                            child: Text(c['icon'] as String,
                                              style: const TextStyle(fontSize: 18)),
                                          ))
                                      .toList(),
                                ),
                              ],
                              // Citação se existir
                              if (perfil.citacao.isNotEmpty) ...[
                                const SizedBox(height: 8),
                                Text(
                                  '"${perfil.citacao}"',
                                  style: TextStyle(color: _tc54(), fontSize: 11, fontStyle: FontStyle.italic),
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ],
                            ],
                          ),
                        );
                      }),
                  ],
                ),
              ),
      ),
    );
  }

  Widget _statAmigo(IconData icon, String valor, String label) {
    return Row(
      children: [
        Icon(icon, size: 14, color: const Color(0xFF1D81C7)),
        const SizedBox(width: 4),
        Text(valor, style: TextStyle(color: _tc(), fontSize: 13, fontWeight: FontWeight.bold)),
        const SizedBox(width: 3),
        Text(label, style: TextStyle(color: _tc54(), fontSize: 11)),
      ],
    );
  }
}

// =============================================================================
// PARTILHA — FUNÇÕES GLOBAIS DE APOIO
// =============================================================================

/// Captura o widget referenciado por [key] como PNG e abre o share sheet nativo.
/// Em desktop, guarda o ficheiro na pasta Downloads e mostra um SnackBar.
Future<void> _partilharImagem({
  required GlobalKey key,
  required String texto,
  BuildContext? context,
  double pixelRatio = 3.0,
}) async {
  try {
    final boundary =
        key.currentContext?.findRenderObject() as RenderRepaintBoundary?;
    if (boundary == null) return;
    final image = await boundary.toImage(pixelRatio: pixelRatio);
    final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
    if (byteData == null) return;
    final pngBytes = byteData.buffer.asUint8List();

    if (_isDesktop) {
      // Em desktop: guardar na pasta Downloads
      final dir = await getDownloadsDirectory() ?? await getTemporaryDirectory();
      final file = File('${dir.path}/thoth_share_${DateTime.now().millisecondsSinceEpoch}.png');
      await file.writeAsBytes(pngBytes);
      if (context != null && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Imagem guardada em ${file.path}'),
            backgroundColor: const Color(0xFF1D81C7),
          ),
        );
      }
      return;
    }

    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/thoth_share_${DateTime.now().millisecondsSinceEpoch}.png');
    await file.writeAsBytes(pngBytes);
    await Share.shareXFiles(
      [XFile(file.path, mimeType: 'image/png')],
      text: texto,
      subject: 'THOTH – O meu progresso de estudo',
    );
  } catch (e) {
    debugPrint('Erro ao partilhar imagem: $e');
  }
}

/// Regista a partilha na coleção Firestore users/{uid}/partilhas/
Future<void> _registarPartilhaFirestore({
  required String tipo,
  required int streakDias,
  required int totalFoco,
  required int totalCiclos,
  required int totalSessoes,
}) async {
  try {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    await FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .collection('partilhas')
        .add({
      'tipo': tipo,
      'streakDias': streakDias,
      'totalFocoSegundos': totalFoco,
      'totalCiclos': totalCiclos,
      'totalSessoes': totalSessoes,
      'criadaEm': FieldValue.serverTimestamp(),
    });
  } catch (e) {
    debugPrint('Erro ao registar partilha: $e');
  }
}

// =============================================================================
// DIÁLOGO DE PARTILHA
// =============================================================================

class _DialogoPartilha extends StatefulWidget {
  final Widget cartao;
  final String textoPartilha;
  final Future<void> Function() aoPartilhar;

  const _DialogoPartilha({
    required this.cartao,
    required this.textoPartilha,
    required this.aoPartilhar,
  });

  @override
  State<_DialogoPartilha> createState() => _DialogoPartilhaState();
}

class _DialogoPartilhaState extends State<_DialogoPartilha> {
  bool _aPartilhar = false;

  @override
  Widget build(BuildContext context) {
    const azul = Color(0xFF1D81C7);
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 40),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Preview do cartão
          ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.of(context).size.height * 0.60,
            ),
            child: AspectRatio(
              aspectRatio: 9 / 16,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(20),
                child: widget.cartao,
              ),
            ),
          ),
          const SizedBox(height: 14),
          const Text(
            'Optimizado para Instagram Stories e TikTok',
            style: TextStyle(color: Colors.white38, fontSize: 11, letterSpacing: 0.5),
          ),
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: azul,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
              onPressed: _aPartilhar
                  ? null
                  : () async {
                      setState(() => _aPartilhar = true);
                      await widget.aoPartilhar();
                      if (mounted) Navigator.pop(context);
                    },
              icon: _aPartilhar
                  ? const SizedBox(
                      width: 18, height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                    )
                  : const Icon(Icons.ios_share_rounded, size: 18),
              label: Text(
                _aPartilhar ? 'A guardar…' : 'Partilhar',
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
              ),
            ),
          ),
          const SizedBox(height: 6),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancelar', style: TextStyle(color: Colors.white38, fontSize: 13)),
          ),
        ],
      ),
    );
  }
}

// =============================================================================
// CARTÃO DE STREAK  (formato story 9:16)
// =============================================================================

class _StreakShareCard extends StatelessWidget {
  final int dias;
  final bool acendeuHoje;
  final List<Map<String, dynamic>> conquistas;
  final String? nomeUtilizador;

  const _StreakShareCard({
    required this.dias,
    required this.acendeuHoje,
    this.conquistas = const [],
    this.nomeUtilizador,
  });

  @override
  Widget build(BuildContext context) {
    const laranja = Color(0xFFFF6D00);
    const amarelo = Color(0xFFFFCC02);
    const azul = Color(0xFF1D81C7);
    const fundo = Color(0xFF080C12);

    return Container(
      color: fundo,
      child: Stack(
        children: [
          // Gradiente de fundo
          Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: acendeuHoje
                    ? [laranja.withOpacity(0.18), fundo, fundo, azul.withOpacity(0.10)]
                    : [azul.withOpacity(0.12), fundo, fundo, azul.withOpacity(0.06)],
              ),
            ),
          ),
          // Anel decorativo
          Positioned(
            right: -80,
            top: -60,
            child: Container(
              width: 300, height: 300,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: (acendeuHoje ? laranja : azul).withOpacity(0.07),
                  width: 60,
                ),
              ),
            ),
          ),
          // Partículas
          ..._buildParticulas(acendeuHoje ? laranja : azul),
          // Conteúdo
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 40),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Logo
                _ShareLogo(),
                const Spacer(flex: 2),
                // Número de streak gigante
                Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      '🔥',
                      style: TextStyle(
                        fontSize: 52,
                        shadows: acendeuHoje
                            ? [Shadow(color: laranja.withOpacity(0.6), blurRadius: 20)]
                            : [],
                      ),
                    ),
                    const SizedBox(width: 10),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        ShaderMask(
                          shaderCallback: (bounds) => LinearGradient(
                            colors: acendeuHoje
                                ? [amarelo, laranja]
                                : [Colors.white, Colors.white70],
                          ).createShader(bounds),
                          child: Text(
                            '$dias',
                            style: const TextStyle(
                              fontSize: 80,
                              fontWeight: FontWeight.w900,
                              color: Colors.white,
                              height: 0.9,
                            ),
                          ),
                        ),
                        const Text(
                          'dias',
                          style: TextStyle(
                            color: Colors.white54,
                            fontSize: 18,
                            fontWeight: FontWeight.w300,
                            letterSpacing: 2,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  dias == 1 ? '1 dia de estudo seguido' : '$dias dias de estudo seguidos',
                  style: const TextStyle(color: Colors.white70, fontSize: 15, fontWeight: FontWeight.w300),
                ),
                if (acendeuHoje) ...[
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: laranja.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: laranja.withOpacity(0.4)),
                    ),
                    child: const Text(
                      'Streak activa hoje! 💪',
                      style: TextStyle(color: laranja, fontSize: 11, fontWeight: FontWeight.w600),
                    ),
                  ),
                ],
                const Spacer(flex: 1),
                // Conquistas desbloqueadas
                if (conquistas.where((c) => dias >= (c['dias'] as int)).isNotEmpty) ...[
                  const Text(
                    'CONQUISTAS DESBLOQUEADAS',
                    style: TextStyle(color: Colors.white38, fontSize: 9, letterSpacing: 2, fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    children: conquistas
                        .where((c) => dias >= (c['dias'] as int))
                        .map((c) => Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                              decoration: BoxDecoration(
                                color: laranja.withOpacity(0.12),
                                borderRadius: BorderRadius.circular(20),
                                border: Border.all(color: laranja.withOpacity(0.4)),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(c['icon'] as String, style: const TextStyle(fontSize: 14)),
                                  const SizedBox(width: 4),
                                  Text(
                                    c['label'] as String,
                                    style: const TextStyle(color: Colors.white70, fontSize: 10, fontWeight: FontWeight.w500),
                                  ),
                                ],
                              ),
                            ))
                        .toList(),
                  ),
                ],
                const Spacer(flex: 2),
                // Rodapé
                _ShareRodape(nomeUtilizador: nomeUtilizador),
              ],
            ),
          ),
        ],
      ),
    );
  }

  List<Widget> _buildParticulas(Color cor) {
    final posicoes = [
      const Offset(0.85, 0.12), const Offset(0.10, 0.25),
      const Offset(0.92, 0.40), const Offset(0.05, 0.60),
      const Offset(0.80, 0.75), const Offset(0.20, 0.88),
    ];
    return posicoes.asMap().entries.map((e) {
      final r = e.key % 2 == 0 ? 3.0 : 1.5;
      return Positioned.fill(
        child: FractionallySizedBox(
          alignment: Alignment(e.value.dx * 2 - 1, e.value.dy * 2 - 1),
          widthFactor: 0.0,
          heightFactor: 0.0,
          child: Container(
            width: r * 2, height: r * 2,
            decoration: BoxDecoration(
              color: cor.withOpacity(0.20),
              shape: BoxShape.circle,
            ),
          ),
        ),
      );
    }).toList();
  }
}

// =============================================================================
// CARTÃO DE INSIGHTS (formato story 9:16)
// =============================================================================

class _InsightsShareCard extends StatelessWidget {
  final int streakDias;
  final bool acendeuHoje;
  final int totalFocoSegundos;
  final int totalCiclos;
  final int totalSessoes;
  final String? tarefaMaisEstudada;
  final String? nomeUtilizador;

  const _InsightsShareCard({
    required this.streakDias,
    required this.acendeuHoje,
    required this.totalFocoSegundos,
    required this.totalCiclos,
    required this.totalSessoes,
    this.tarefaMaisEstudada,
    this.nomeUtilizador,
  });

  String get _tempoFormatado {
    final h = totalFocoSegundos ~/ 3600;
    final m = (totalFocoSegundos % 3600) ~/ 60;
    if (h > 0) return '${h}h ${m}m';
    return '${m}m';
  }

  @override
  Widget build(BuildContext context) {
    const azul = Color(0xFF1D81C7);
    const laranja = Color(0xFFFF6D00);
    const fundo = Color(0xFF080C12);

    return Container(
      color: fundo,
      child: Stack(
        children: [
          // Gradiente
          Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [azul.withOpacity(0.14), fundo, fundo, const Color(0xFF0A1A2E)],
              ),
            ),
          ),
          // Grade decorativa subtil
          Positioned.fill(
            child: CustomPaint(painter: _GradePainter()),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 40),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _ShareLogo(),
                const SizedBox(height: 6),
                const Text(
                  'OS MEUS INSIGHTS DE ESTUDO',
                  style: TextStyle(color: Colors.white38, fontSize: 9, letterSpacing: 1.5),
                ),
                const Spacer(flex: 1),
                // Streak destaque
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [laranja.withOpacity(0.15), laranja.withOpacity(0.05)],
                    ),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: laranja.withOpacity(0.35)),
                  ),
                  child: Row(
                    children: [
                      const Text('🔥', style: TextStyle(fontSize: 28)),
                      const SizedBox(width: 12),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '$streakDias ${streakDias == 1 ? 'dia' : 'dias'} de streak',
                            style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
                          ),
                          Text(
                            acendeuHoje ? 'Streak activa hoje! 💪' : 'Continua a estudar!',
                            style: const TextStyle(color: Colors.white54, fontSize: 11),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                // Grelha de stats
                Row(
                  children: [
                    Expanded(child: _ShareStatBox(emoji: '⏱', valor: _tempoFormatado, label: 'foco total', destaque: true)),
                    const SizedBox(width: 10),
                    Expanded(child: _ShareStatBox(emoji: '🔁', valor: '$totalCiclos', label: 'ciclos')),
                  ],
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(child: _ShareStatBox(emoji: '✅', valor: '$totalSessoes', label: 'sessões')),
                    const SizedBox(width: 10),
                    Expanded(child: _ShareStatBox(
                      emoji: '🎯',
                      valor: tarefaMaisEstudada ?? '—',
                      label: 'mais estudada',
                      pequeno: true,
                    )),
                  ],
                ),
                const Spacer(flex: 2),
                _ShareRodape(nomeUtilizador: nomeUtilizador),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// =============================================================================
// COMPONENTES PARTILHADOS DOS CARTÕES
// =============================================================================

class _ShareLogo extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        border: Border.all(color: const Color(0xFF1D81C7).withOpacity(0.6)),
        borderRadius: BorderRadius.circular(6),
      ),
      child: const Text(
        'THOTH',
        style: TextStyle(
          color: Color(0xFF1D81C7),
          fontSize: 12,
          fontWeight: FontWeight.bold,
          letterSpacing: 3,
        ),
      ),
    );
  }
}

class _ShareRodape extends StatelessWidget {
  final String? nomeUtilizador;
  const _ShareRodape({this.nomeUtilizador});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Row(
          children: [
            Container(
              width: 6, height: 6,
              decoration: const BoxDecoration(color: Color(0xFF1D81C7), shape: BoxShape.circle),
            ),
            const SizedBox(width: 6),
            const Text('thoth.app', style: TextStyle(color: Colors.white38, fontSize: 10, letterSpacing: 1)),
          ],
        ),
        if (nomeUtilizador != null && nomeUtilizador!.isNotEmpty)
          Text('@$nomeUtilizador', style: const TextStyle(color: Colors.white38, fontSize: 10)),
      ],
    );
  }
}

class _ShareStatBox extends StatelessWidget {
  final String emoji;
  final String valor;
  final String label;
  final bool destaque;
  final bool pequeno;

  const _ShareStatBox({
    required this.emoji,
    required this.valor,
    required this.label,
    this.destaque = false,
    this.pequeno = false,
  });

  @override
  Widget build(BuildContext context) {
    const azul = Color(0xFF1D81C7);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      decoration: BoxDecoration(
        color: destaque ? azul.withOpacity(0.12) : Colors.white.withOpacity(0.04),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: destaque ? azul.withOpacity(0.5) : Colors.white.withOpacity(0.08),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(emoji, style: const TextStyle(fontSize: 22)),
          const SizedBox(height: 6),
          Text(
            valor,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: Colors.white,
              fontSize: pequeno ? 13 : 22,
              fontWeight: FontWeight.bold,
              height: 1.1,
            ),
          ),
          const SizedBox(height: 2),
          Text(label, style: const TextStyle(color: Colors.white38, fontSize: 10, letterSpacing: 0.5)),
        ],
      ),
    );
  }
}

class _GradePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0xFF1D81C7).withOpacity(0.04)
      ..strokeWidth = 1;
    const step = 40.0;
    for (double x = 0; x < size.width; x += step) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }
    for (double y = 0; y < size.height; y += step) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
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
                          widget.state._guardarTudo();
                          setState(() {});
                        },
                      ),
                      IconButton(
                        tooltip: 'Eliminar definitivamente',
                        icon: const Icon(Icons.delete_outline, color: Colors.redAccent),
                        onPressed: () {
                          final tarefaId = t.id;
                          // ignore: invalid_use_of_protected_member
                          widget.state.setState(() {
                            widget.state.tarefas.removeWhere((x) => x.id == t.id);
                            if (widget.state.ultimaTarefa?.id == t.id) {
                              widget.state.ultimaTarefa = null;
                            }
                          });
                          // Apagar do Firestore
                          widget.state._tarefasCol.doc(tarefaId).delete()
                              .catchError((e) => debugPrint('Erro ao apagar tarefa: $e'));
                          widget.state._guardarTudo();
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



// =============================================================================
// STREAK FREEZE — já integrado em _StreakDialog acima
// =============================================================================

// =============================================================================
// META SEMANAL — Bottom Sheet
// =============================================================================

class _BottomSheetMetaSemanal extends StatefulWidget {
  final List<SessaoConcluida> sessoes;
  final int metaAtual;
  final ValueChanged<int> onSalvar;
  const _BottomSheetMetaSemanal({required this.sessoes, required this.metaAtual, required this.onSalvar});
  @override
  State<_BottomSheetMetaSemanal> createState() => _BottomSheetMetaSemanalState();
}

class _BottomSheetMetaSemanalState extends State<_BottomSheetMetaSemanal> {
  late int _meta;
  static const azul = Color(0xFF1D81C7);

  @override
  void initState() {
    super.initState();
    _meta = widget.metaAtual == 0 ? 300 : widget.metaAtual; // default 5h
  }

  int _minutosEstaSemana() {
    final hoje = DateTime.now();
    final inicioSemana = hoje.subtract(Duration(days: hoje.weekday - 1));
    final semanaStr = DateTime(inicioSemana.year, inicioSemana.month, inicioSemana.day);
    return widget.sessoes
        .where((s) => s.dataConclusao.isAfter(semanaStr))
        .fold(0, (acc, s) => acc + s.tempoFocoSegundos ~/ 60);
  }

  @override
  Widget build(BuildContext context) {
    final progresso = _meta > 0 ? (_minutosEstaSemana() / _meta).clamp(0.0, 1.0) : 0.0;
    final mins = _minutosEstaSemana();
    final bg = temaEscuro.value ? const Color(0xFF111111) : Colors.white;
    return Container(
      decoration: BoxDecoration(
        color: bg,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        border: const Border(top: BorderSide(color: azul, width: 2)),
      ),
      padding: EdgeInsets.only(
        left: 24, right: 24, top: 24,
        bottom: MediaQuery.of(context).viewInsets.bottom + 24,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(child: Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(2)))),
          const SizedBox(height: 20),
          const Text('🎯  Meta Semanal', style: TextStyle(color: azul, fontSize: 20, fontWeight: FontWeight.bold)),
          const SizedBox(height: 16),
          // Progresso desta semana
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: azul.withOpacity(0.07),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: azul.withOpacity(0.3)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('Esta semana', style: TextStyle(color: _tc54(), fontSize: 13)),
                    Text(
                      '${mins ~/ 60}h ${mins % 60}m / ${_meta ~/ 60}h ${_meta % 60 == 0 ? '' : '${_meta % 60}m'}',
                      style: TextStyle(color: _tc(), fontSize: 13, fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: LinearProgressIndicator(
                    value: progresso,
                    minHeight: 10,
                    color: progresso >= 1.0 ? Colors.greenAccent : azul,
                    backgroundColor: _tc().withOpacity(0.08),
                  ),
                ),
                if (progresso >= 1.0) ...[
                  const SizedBox(height: 8),
                  const Row(
                    children: [
                      Text('🏆', style: TextStyle(fontSize: 16)),
                      SizedBox(width: 6),
                      Text('Meta atingida esta semana!', style: TextStyle(color: Colors.greenAccent, fontSize: 13, fontWeight: FontWeight.bold)),
                    ],
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 24),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Meta: ${_meta ~/ 60}h ${_meta % 60 > 0 ? '${_meta % 60}m' : ''}', style: const TextStyle(color: azul, fontWeight: FontWeight.bold, fontSize: 15)),
              Text('por semana', style: TextStyle(color: _tc54(), fontSize: 13)),
            ],
          ),
          Slider(
            value: _meta.toDouble(),
            min: 30,
            max: 1200,
            divisions: 39,
            label: '${_meta ~/ 60}h ${_meta % 60 > 0 ? '${_meta % 60}m' : ''}',
            onChanged: (v) => setState(() => _meta = (v ~/ 30) * 30),
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [60, 120, 180, 300, 600].map((m) => OutlinedButton(
              onPressed: () => setState(() => _meta = m),
              style: OutlinedButton.styleFrom(
                foregroundColor: _meta == m ? Colors.white : azul,
                backgroundColor: _meta == m ? azul : null,
                side: BorderSide(color: azul.withOpacity(0.5)),
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                minimumSize: const Size(0, 32),
              ),
              child: Text('${m ~/ 60}h', style: const TextStyle(fontSize: 12)),
            )).toList(),
          ),
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: () {
                widget.onSalvar(_meta);
                Navigator.pop(context);
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: azul,
                foregroundColor: Colors.white,
                minimumSize: const Size(double.infinity, 50),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              child: const Text('GUARDAR META', style: TextStyle(fontWeight: FontWeight.bold, letterSpacing: 1)),
            ),
          ),
        ],
      ),
    );
  }
}

// =============================================================================
// LEADERBOARD GLOBAL
// =============================================================================

class TelaLeaderboard extends StatefulWidget {
  const TelaLeaderboard({super.key});
  @override
  State<TelaLeaderboard> createState() => _TelaLeaderboardState();
}

class _TelaLeaderboardState extends State<TelaLeaderboard> with SingleTickerProviderStateMixin {
  static const azul = Color(0xFF1D81C7);
  late TabController _tabCtrl;
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  String get _uid => FirebaseAuth.instance.currentUser!.uid;

  List<Map<String, dynamic>> _rankingStreak = [];
  List<Map<String, dynamic>> _rankingTempo = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: 2, vsync: this);
    _carregarLeaderboard();
  }

  @override
  void dispose() {
    _tabCtrl.dispose();
    super.dispose();
  }

  Future<void> _carregarLeaderboard() async {
    setState(() => _loading = true);
    try {
      // Buscar todos os utilizadores do índice global (máx 50)
      final snap = await _db.collection('usernames').limit(50).get();
      final lista = <Map<String, dynamic>>[];

      for (final doc in snap.docs) {
        final uid = doc.data()['uid'] as String? ?? '';
        if (uid.isEmpty) continue;
        try {
          // Verificar se conta é privada
          final cfgSnap = await _db.collection('users').doc(uid).collection('config').doc('dados').get();
          final privado = cfgSnap.exists ? (cfgSnap.data()?['contaPrivada'] as bool? ?? false) : false;
          if (privado && uid != _uid) continue;

          final perfilSnap = await _db.collection('users').doc(uid).collection('perfil').doc('dados').get();
          if (!perfilSnap.exists) continue;
          final perfil = PerfilUsuario.fromJson(perfilSnap.data()!);

          final sessoesSnap = await _db.collection('users').doc(uid).collection('sessoes').orderBy('dataConclusao').get();
          final sessoes = sessoesSnap.docs.map((d) => SessaoConcluida.fromJson(d.data())).toList();

          final freezeDias = cfgSnap.exists ? List<String>.from(cfgSnap.data()?['freezeDias'] as List? ?? []) : <String>[];
          final streak = StreakInfo.calcularComFreeze(sessoes, freezeDias);
          final totalFoco = sessoes.fold<int>(0, (s, e) => s + e.tempoFocoSegundos);

          lista.add({
            'uid': uid,
            'perfil': perfil,
            'streak': streak,
            'totalFoco': totalFoco,
            'totalSessoes': sessoes.length,
            'euProprio': uid == _uid,
          });
        } catch (_) {}
      }

      // Ranking por streak
      final porStreak = [...lista]..sort((a, b) => (b['streak'] as StreakInfo).dias.compareTo((a['streak'] as StreakInfo).dias));
      // Ranking por tempo de foco
      final porTempo = [...lista]..sort((a, b) => (b['totalFoco'] as int).compareTo(a['totalFoco'] as int));

      if (mounted) setState(() {
        _rankingStreak = porStreak;
        _rankingTempo = porTempo;
        _loading = false;
      });
    } catch (e) {
      debugPrint('Erro leaderboard: $e');
      if (mounted) setState(() => _loading = false);
    }
  }

  String _fmtTempo(int seg) {
    if (seg >= 3600) {
      final h = seg ~/ 3600;
      final m = (seg % 3600) ~/ 60;
      return m > 0 ? '${h}h ${m}m' : '${h}h';
    }
    return '${seg ~/ 60}m';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Leaderboard Global'),
        bottom: TabBar(
          controller: _tabCtrl,
          indicatorColor: azul,
          labelColor: azul,
          unselectedLabelColor: Colors.white54,
          tabs: const [
            Tab(icon: Icon(Icons.local_fire_department_outlined), text: 'Streak'),
            Tab(icon: Icon(Icons.timer_outlined), text: 'Tempo de Foco'),
          ],
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: azul))
          : TabBarView(
              controller: _tabCtrl,
              children: [
                _ListaRanking(
                  lista: _rankingStreak,
                  valorBuilder: (e) => '🔥 ${(e['streak'] as StreakInfo).dias} dias',
                  subBuilder: (e) => '${e['totalSessoes']} sessões',
                ),
                _ListaRanking(
                  lista: _rankingTempo,
                  valorBuilder: (e) => '⏱ ${_fmtTempo(e['totalFoco'] as int)}',
                  subBuilder: (e) => '${(e['streak'] as StreakInfo).dias} dias streak',
                ),
              ],
            ),
    );
  }
}

class _ListaRanking extends StatelessWidget {
  final List<Map<String, dynamic>> lista;
  final String Function(Map<String, dynamic>) valorBuilder;
  final String Function(Map<String, dynamic>) subBuilder;

  const _ListaRanking({required this.lista, required this.valorBuilder, required this.subBuilder});

  static const List<String> _medalhas = ['🥇', '🥈', '🥉'];

  @override
  Widget build(BuildContext context) {
    if (lista.isEmpty) {
      return Center(child: Text('Sem dados', style: TextStyle(color: _tc38())));
    }
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: lista.length,
      itemBuilder: (ctx, i) {
        final e = lista[i];
        final perfil = e['perfil'] as PerfilUsuario;
        final euProprio = e['euProprio'] as bool? ?? false;
        const azul = Color(0xFF1D81C7);
        return AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          margin: const EdgeInsets.only(bottom: 10),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: euProprio ? azul.withOpacity(0.08) : Colors.transparent,
            border: Border.all(
              color: euProprio ? azul.withOpacity(0.6) : _tc().withOpacity(0.1),
            ),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Row(
            children: [
              SizedBox(
                width: 32,
                child: Text(
                  i < 3 ? _medalhas[i] : '${i + 1}',
                  style: TextStyle(
                    fontSize: i < 3 ? 22 : 15,
                    fontWeight: FontWeight.bold,
                    color: i >= 3 ? _tc38() : null,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
              const SizedBox(width: 12),
              CircleAvatar(
                radius: 20,
                backgroundColor: azul.withOpacity(0.15),
                backgroundImage: perfil.fotoUrl.isNotEmpty ? NetworkImage(perfil.fotoUrl) as ImageProvider : null,
                child: perfil.fotoUrl.isEmpty
                    ? Text(perfil.nome.isNotEmpty ? perfil.nome[0].toUpperCase() : '?',
                        style: const TextStyle(color: azul, fontWeight: FontWeight.bold))
                    : null,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          perfil.nome.isNotEmpty ? perfil.nome : 'Utilizador',
                          style: TextStyle(color: _tc(), fontWeight: FontWeight.bold, fontSize: 14),
                        ),
                        if (euProprio) ...[
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                            decoration: BoxDecoration(color: azul, borderRadius: BorderRadius.circular(8)),
                            child: const Text('Tu', style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)),
                          ),
                        ],
                      ],
                    ),
                    Text(subBuilder(e), style: TextStyle(color: _tc54(), fontSize: 12)),
                  ],
                ),
              ),
              Text(valorBuilder(e), style: const TextStyle(color: Color(0xFF1D81C7), fontWeight: FontWeight.bold, fontSize: 14)),
            ],
          ),
        );
      },
    );
  }
}

// =============================================================================
// REACÇÕES ENTRE AMIGOS
// =============================================================================

class _BotaoReacao extends StatefulWidget {
  final String amigoUid;
  final String meuUid;
  const _BotaoReacao({required this.amigoUid, required this.meuUid});
  @override
  State<_BotaoReacao> createState() => _BotaoReacaoState();
}

class _BotaoReacaoState extends State<_BotaoReacao> {
  bool _enviando = false;
  String? _ultimaReacao;

  Future<void> _enviarReacao(String emoji) async {
    if (_enviando) return;
    setState(() { _enviando = true; _ultimaReacao = emoji; });
    try {
      await FirebaseFirestore.instance
          .collection('users')
          .doc(widget.amigoUid)
          .collection('reacoes')
          .add({
        'de': widget.meuUid,
        'emoji': emoji,
        'lida': false,
        'criadaEm': FieldValue.serverTimestamp(),
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('$emoji Reacção enviada!'),
            duration: const Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      debugPrint('Erro ao enviar reacção: $e');
    }
    if (mounted) setState(() => _enviando = false);
  }

  void _mostrarPicker(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: temaEscuro.value ? const Color(0xFF111111) : Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Enviar reacção', style: TextStyle(color: _tc(), fontWeight: FontWeight.bold, fontSize: 16)),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: _reacoes.map((emoji) => GestureDetector(
                  onTap: () {
                    Navigator.pop(ctx);
                    _enviarReacao(emoji);
                  },
                  child: Container(
                    width: 52, height: 52,
                    decoration: BoxDecoration(
                      color: const Color(0xFF1D81C7).withOpacity(0.08),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: const Color(0xFF1D81C7).withOpacity(0.2)),
                    ),
                    alignment: Alignment.center,
                    child: Text(emoji, style: const TextStyle(fontSize: 26)),
                  ),
                )).toList(),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => _mostrarPicker(context),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          border: Border.all(color: const Color(0xFF1D81C7).withOpacity(0.35)),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(_ultimaReacao ?? '👏', style: const TextStyle(fontSize: 16)),
            const SizedBox(width: 4),
            const Icon(Icons.add, size: 13, color: Color(0xFF1D81C7)),
          ],
        ),
      ),
    );
  }
}

// =============================================================================
// NOTIFICAÇÕES DE REACÇÕES (badge no drawer de Amigos)
// =============================================================================

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
