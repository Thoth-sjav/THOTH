// lib/utils/platform_file.dart
//
// Ponto de entrada único para utilitários de ficheiro/plataforma.
// Usa conditional exports do Dart para escolher a implementação certa:
//   - mobile/desktop → platform_file_io.dart  (usa dart:io + path_provider)
//   - web            → platform_file_web.dart (usa dart:html)
//
// Basta importar este ficheiro no main.dart. NÃO importes _io ou _web diretamente.

export 'platform_file_io.dart'
    if (dart.library.html) 'platform_file_web.dart';
