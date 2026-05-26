// STUB: window_manager não existe na web.
// Este ficheiro é importado condicionalmente apenas quando a plataforma é web.
// Não alteres este ficheiro — é necessário para o build web funcionar.

// Stub mínimo para que o código compile na web sem erros.
final windowManager = _WindowManagerStub();

class _WindowManagerStub {
  Future<void> ensureInitialized() async {}
  Future<void> waitUntilReadyToShow(dynamic options, Future<void> Function() callback) async {}
  Future<void> show() async {}
  Future<void> focus() async {}
}

class WindowOptions {
  final dynamic size;
  final dynamic minimumSize;
  final bool center;
  final String title;
  final dynamic backgroundColor;
  final bool skipTaskbar;
  final dynamic titleBarStyle;
  const WindowOptions({
    this.size,
    this.minimumSize,
    this.center = false,
    this.title = '',
    this.backgroundColor,
    this.skipTaskbar = false,
    this.titleBarStyle,
  });
}

// Enums necessários
enum TitleBarStyle { normal, hidden }
