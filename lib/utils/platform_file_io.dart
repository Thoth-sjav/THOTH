// lib/utils/platform_file_io.dart
//
// Implementação mobile/desktop (usa dart:io e path_provider reais).
// Importado automaticamente em Android, iOS, Windows, macOS, Linux.

import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';

/// Devolve um ImageProvider a partir de um XFile (usa FileImage em mobile/desktop).
ImageProvider platformFileImage(XFile xfile) {
  return FileImage(File(xfile.path));
}

/// Partilha imagem na web — não é chamado nesta plataforma, mas precisa de existir.
Future<void> partilharImagemWeb(List<int> bytes, String texto) async {
  // Não faz nada em mobile/desktop — o main.dart usa Share.shareXFiles diretamente.
}

/// Obtém a pasta Downloads em desktop.
Future<Directory?> getDownloadsDesktop() async {
  try {
    return await getDownloadsDirectory();
  } catch (_) {
    return null;
  }
}

/// Obtém a pasta temporária em desktop/mobile.
Future<Directory?> getTempDesktop() async {
  try {
    return await getTemporaryDirectory();
  } catch (_) {
    return null;
  }
}

/// Cria um ficheiro PNG temporário e devolve o seu path.
Future<String> criarFicheiroTemp(Directory? dir, List<int> bytes) async {
  final d = dir ?? await getTemporaryDirectory();
  final file = File('${d.path}/thoth_share_${DateTime.now().millisecondsSinceEpoch}.png');
  await file.writeAsBytes(bytes);
  return file.path;
}

/// Guarda PNG em temp e devolve o path (para share em mobile).
Future<String?> guardarEPartilhar(List<int> bytes) async {
  try {
    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/thoth_share_${DateTime.now().millisecondsSinceEpoch}.png');
    await file.writeAsBytes(bytes);
    return file.path;
  } catch (_) {
    return null;
  }
}
