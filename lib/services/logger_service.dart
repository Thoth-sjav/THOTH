import 'package:logger/logger.dart';

/// Serviço centralizado de logging
class LoggerService {
  static final _instance = LoggerService._internal();
  
  factory LoggerService() {
    return _instance;
  }
  
  LoggerService._internal();

  final Logger _logger = Logger(
    printer: PrettyPrinter(
      methodCount: 2,
      errorMethodCount: 5,
      lineLength: 80,
      colors: true,
      printEmojis: true,
    ),
  );

  void debug(String message, [dynamic error, StackTrace? stackTrace]) {
    _logger.d(message, error: error, stackTrace: stackTrace);
  }

  void info(String message, [dynamic error, StackTrace? stackTrace]) {
    _logger.i(message, error: error, stackTrace: stackTrace);
  }

  void warning(String message, [dynamic error, StackTrace? stackTrace]) {
    _logger.w(message, error: error, stackTrace: stackTrace);
  }

  void error(String message, [dynamic error, StackTrace? stackTrace]) {
    _logger.e(message, error: error, stackTrace: stackTrace);
  }

  void trace(String message) {
    _logger.t(message);
  }
}

/// Exceções customizadas da aplicação
abstract class ThothException implements Exception {
  final String message;
  final dynamic originalError;
  final StackTrace? stackTrace;

  ThothException({
    required this.message,
    this.originalError,
    this.stackTrace,
  });

  @override
  String toString() => message;
}

class AuthException extends ThothException {
  AuthException({
    required String message,
    dynamic originalError,
    StackTrace? stackTrace,
  }) : super(
    message: message,
    originalError: originalError,
    stackTrace: stackTrace,
  );
}

class DatabaseException extends ThothException {
  DatabaseException({
    required String message,
    dynamic originalError,
    StackTrace? stackTrace,
  }) : super(
    message: message,
    originalError: originalError,
    stackTrace: stackTrace,
  );
}

class ValidationException extends ThothException {
  ValidationException({
    required String message,
    dynamic originalError,
    StackTrace? stackTrace,
  }) : super(
    message: message,
    originalError: originalError,
    stackTrace: stackTrace,
  );
}

class StorageException extends ThothException {
  StorageException({
    required String message,
    dynamic originalError,
    StackTrace? stackTrace,
  }) : super(
    message: message,
    originalError: originalError,
    stackTrace: stackTrace,
  );
}

/// Helper para tratamento seguro de erros
class ErrorHandler {
  static Future<T> tryAsync<T>({
    required Future<T> Function() operation,
    required T fallback,
    required String operationName,
  }) async {
    try {
      return await operation();
    } on ThothException {
      rethrow;
    } catch (e, stackTrace) {
      LoggerService().error(
        'Erro em $operationName: $e',
        e,
        stackTrace,
      );
      return fallback;
    }
  }

  static T trySync<T>({
    required T Function() operation,
    required T fallback,
    required String operationName,
  }) {
    try {
      return operation();
    } catch (e, stackTrace) {
      LoggerService().error(
        'Erro em $operationName: $e',
        e,
        stackTrace,
      );
      return fallback;
    }
  }
}
