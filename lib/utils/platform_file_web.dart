// lib/utils/platform_file_web.dart
//
// Implementação web (usa dart:html).
// Importado automaticamente quando o target é web.

// ignore: avoid_web_libraries_in_flutter
import 'dart:html' as html;
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

/// Devolve um ImageProvider a partir de um XFile na web (usa MemoryImage).
ImageProvider platformFileImage(XFile xfile) {
  // Na web, XFile.readAsBytes() lê os bytes do blob — não há path de ficheiro.
  // Usamos um FutureBuilder no lado do widget, mas aqui devolvemos um placeholder
  // porque o CircleAvatar aceita backgroundImage nulo quando o child existe.
  // O display correto para a web já está coberto pelo campo _fotoUrl em base64.
  return const AssetImage('assets/sounds/timer_fase.wav'); // fallback nunca visível
}

/// Faz download do PNG no browser via âncora HTML.
Future<void> partilharImagemWeb(List<int> bytes, String texto) async {
  try {
    final blob = html.Blob([Uint8List.fromList(bytes)], 'image/png');
    final url = html.Url.createObjectUrlFromBlob(blob);
    final anchor = html.AnchorElement(href: url)
      ..setAttribute('download', 'thoth_progresso_${DateTime.now().millisecondsSinceEpoch}.png')
      ..click();
    html.Url.revokeObjectUrl(url);
  } catch (e) {
    debugPrint('Erro ao fazer download da imagem: $e');
  }
}

// Os métodos abaixo nunca são chamados na web (protegidos por kIsWeb e _isDesktop),
// mas precisam de existir para que o compilador não dê erro.

Future<dynamic> getDownloadsDesktop() async => null;
Future<dynamic> getTempDesktop() async => null;
Future<String> criarFicheiroTemp(dynamic dir, List<int> bytes) async => '';
Future<String?> guardarEPartilhar(List<int> bytes) async => null;
