// STUB: flutter_background_service não existe na web.
// Este ficheiro é importado condicionalmente apenas quando a plataforma é web.
// Não alteres este ficheiro — é necessário para o build web funcionar.

// Stub mínimo para compilação na web.
class FlutterBackgroundService {
  Future<void> configure({
    required dynamic androidConfiguration,
    required dynamic iosConfiguration,
  }) async {}

  // invoke existe na instância na web — é um no-op
  void invoke(String method, [Map<String, dynamic>? args]) {}

  Stream<Map<String, dynamic>?> on(String method) => const Stream.empty();
}

class AndroidConfiguration {
  const AndroidConfiguration({
    required dynamic onStart,
    required bool autoStart,
    required bool isForegroundMode,
    required String notificationChannelId,
    required String initialNotificationTitle,
    required String initialNotificationContent,
    required int foregroundServiceNotificationId,
  });
}

class IosConfiguration {
  const IosConfiguration({
    required bool autoStart,
    required dynamic onForeground,
    required dynamic onBackground,
  });
}

abstract class ServiceInstance {
  void invoke(String method, [Map<String, dynamic>? args]);
  Stream<Map<String, dynamic>?> on(String method);
  void stopSelf();
}

class AndroidServiceInstance extends ServiceInstance {
  @override
  void invoke(String method, [Map<String, dynamic>? args]) {}
  @override
  Stream<Map<String, dynamic>?> on(String method) => const Stream.empty();
  @override
  void stopSelf() {}
  void setForegroundNotificationInfo({required String title, required String content}) {}
}
