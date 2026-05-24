import 'dart:io';
import 'package:equatable/equatable.dart';

import 'logger_service.dart';

/// Classe para validações da aplicação
class ValidationService {
  // Constantes de limite
  static const int maxUsernameLength = 30;
  static const int minUsernameLength = 3;
  static const int maxNomePerfilLength = 100;
  static const int maxTituloTarefaLength = 200;
  static const int maxDescricaoLength = 1000;
  static const int maxFileSize = 10 * 1024 * 1024; // 10MB
  static const Duration maxDuracaoEstudio = Duration(hours: 8);

  // Padrões de validação
  static final RegExp _usernameRegex = RegExp(r'^[a-zA-Z0-9_-]{3,30}$');
  static final RegExp _emailRegex = RegExp(
    r'^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$',
  );

  /// Valida username
  static ValidationResult validarUsername(String? username) {
    if (username == null || username.isEmpty) {
      return ValidationResult.fail('Username não pode estar vazio');
    }

    if (username.length < minUsernameLength) {
      return ValidationResult.fail('Username deve ter pelo menos $minUsernameLength caracteres');
    }

    if (username.length > maxUsernameLength) {
      return ValidationResult.fail('Username não pode exceder $maxUsernameLength caracteres');
    }

    if (!_usernameRegex.hasMatch(username)) {
      return ValidationResult.fail(
        'Username pode conter apenas letras, números, traços e underscores',
      );
    }

    return ValidationResult.success();
  }

  /// Valida email
  static ValidationResult validarEmail(String? email) {
    if (email == null || email.isEmpty) {
      return ValidationResult.fail('Email não pode estar vazio');
    }

    if (!_emailRegex.hasMatch(email)) {
      return ValidationResult.fail('Email inválido');
    }

    if (email.length > 254) {
      return ValidationResult.fail('Email muito longo');
    }

    return ValidationResult.success();
  }

  /// Valida título de tarefa
  static ValidationResult validarTituloTarefa(String? titulo) {
    if (titulo == null || titulo.isEmpty) {
      return ValidationResult.fail('Título não pode estar vazio');
    }

    final trimmed = titulo.trim();
    if (trimmed.length < 3) {
      return ValidationResult.fail('Título deve ter pelo menos 3 caracteres');
    }

    if (trimmed.length > maxTituloTarefaLength) {
      return ValidationResult.fail('Título muito longo');
    }

    return ValidationResult.success();
  }

  /// Valida descrição
  static ValidationResult validarDescricao(String? descricao) {
    if (descricao == null) return ValidationResult.success();

    if (descricao.length > maxDescricaoLength) {
      return ValidationResult.fail('Descrição muito longa');
    }

    return ValidationResult.success();
  }

  /// Valida duração em minutos
  static ValidationResult validarDuracao(int? duracao) {
    if (duracao == null) {
      return ValidationResult.fail('Duração não pode estar vazia');
    }

    if (duracao < 1) {
      return ValidationResult.fail('Duração deve ser positiva');
    }

    if (duracao > maxDuracaoEstudio.inMinutes) {
      return ValidationResult.fail('Duração não pode exceder 8 horas');
    }

    return ValidationResult.success();
  }

  /// Valida prioridade (1-5)
  static ValidationResult validarPrioridade(int? prioridade) {
    if (prioridade == null) {
      return ValidationResult.fail('Prioridade não pode estar vazia');
    }

    if (prioridade < 1 || prioridade > 5) {
      return ValidationResult.fail('Prioridade deve estar entre 1 e 5');
    }

    return ValidationResult.success();
  }

  /// Valida ficheiro de imagem
  static ValidationResult validarImagemUpload(File? file) {
    if (file == null) {
      return ValidationResult.fail('Ficheiro não selecionado');
    }

    if (!file.existsSync()) {
      return ValidationResult.fail('Ficheiro não existe');
    }

    final size = file.lengthSync();
    if (size > maxFileSize) {
      return ValidationResult.fail('Ficheiro muito grande (máximo: 10MB)');
    }

    final path = file.path.toLowerCase();
    const allowedExtensions = ['.jpg', '.jpeg', '.png', '.gif', '.webp'];
    
    final isValidExtension = allowedExtensions.any(
      (ext) => path.endsWith(ext),
    );

    if (!isValidExtension) {
      return ValidationResult.fail('Formato de ficheiro não suportado');
    }

    return ValidationResult.success();
  }

  /// Valida matéria/disciplina
  static ValidationResult validarMateria(String? materia) {
    if (materia == null || materia.isEmpty) {
      return ValidationResult.fail('Matéria não pode estar vazia');
    }

    if (materia.length < 2 || materia.length > 50) {
      return ValidationResult.fail('Matéria deve ter entre 2 e 50 caracteres');
    }

    return ValidationResult.success();
  }

  /// Sanitiza string para evitar injeções
  static String sanitizar(String input) {
    return input
        .replaceAll(RegExp(r'[<>\"\'`]'), '') // Remove caracteres perigosos
        .trim();
  }
}

/// Resultado de validação
class ValidationResult extends Equatable {
  final bool isValid;
  final String? message;

  const ValidationResult({
    required this.isValid,
    this.message,
  });

  factory ValidationResult.success() {
    return const ValidationResult(isValid: true);
  }

  factory ValidationResult.fail(String message) {
    LoggerService().warning('Validação falhou: $message');
    return ValidationResult(isValid: false, message: message);
  }

  @override
  List<Object?> get props => [isValid, message];
}
