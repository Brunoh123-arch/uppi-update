import 'package:flutter/foundation.dart';

import 'package:flutter_common/core/entities/media.dart';
import 'package:injectable/injectable.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:path/path.dart' as path;


import 'upload_datasource.dart';

/// Upload datasource do rider com compressão inteligente.
/// Foto de perfil → máx 150 KB
/// Garante que o 1 GB gratuito do Supabase Storage dure muito mais tempo.
@LazySingleton(as: UploadDatasource)
class UploadDatasourceImpl implements UploadDatasource {
  final SupabaseClient _supabase = Supabase.instance.client;

  UploadDatasourceImpl();

  String? get _uid => _supabase.auth.currentUser?.id;

  /// Retorna o UID do usuário autenticado no Supabase.
  /// Se não houver sessão ativa, lança exceção clara em vez de criar contas fake.
  Future<String> _resolveUid() async {
    // 1. Tentar obter UID da sessão Supabase atual
    if (_uid != null) return _uid!;

    // 2. Sem sessão válida → exigir login real
    debugPrint('UPPI UPLOAD - Nenhuma sessão ativa. Upload bloqueado.');
    throw Exception(
      'Sessão expirada. Faça login novamente para enviar imagens.',
    );
  }

  @override
  Future<MediaEntity> uploadProfilePicture(String filePath) async {
    final xfile = XFile(filePath);
    final uid = await _resolveUid();
    var extension = path.extension(xfile.name).toLowerCase();
    if (extension.isEmpty) {
      if (xfile.mimeType == 'image/png') {
        extension = '.png';
      } else if (xfile.mimeType == 'image/webp') extension = '.webp';
      else extension = '.jpg';
    }
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final storagePath = '$uid/profile_$timestamp$extension';

    // Comprime para máx 150KB
    final compressed = await _compressImage(
      filePath,
      maxSizeKb: 150,
      quality: 80,
      maxWidth: 800,
      maxHeight: 800,
    );

    await _supabase.storage.from('avatars').uploadBinary(
          storagePath,
          compressed,
          fileOptions: FileOptions(
            contentType: _getContentType(extension),
            upsert: true,
          ),
        );

    final downloadUrl =
        _supabase.storage.from('avatars').getPublicUrl(storagePath);

    return MediaEntity(id: storagePath, address: downloadUrl);
  }

  /// Comprime imagem progressivamente até atingir tamanho alvo.
  Future<Uint8List> _compressImage(
    String filePath, {
    required int maxSizeKb,
    required int quality,
    required int maxWidth,
    required int maxHeight,
  }) async {
    final xfile = XFile(filePath);
    final originalBytes = await xfile.readAsBytes();

    if (kIsWeb) {
      return originalBytes; // Skip compression on Web
    }

    if (originalBytes.lengthInBytes <= maxSizeKb * 1024) {
      return originalBytes;
    }

    Uint8List? result = await FlutterImageCompress.compressWithList(
      originalBytes,
      minWidth: maxWidth,
      minHeight: maxHeight,
      quality: quality,
    );

    if (result.lengthInBytes > maxSizeKb * 1024) {
      int q = quality - 10;
      while (result!.lengthInBytes > maxSizeKb * 1024 && q >= 40) {
        result = await FlutterImageCompress.compressWithList(
          originalBytes,
          minWidth: maxWidth ~/ 2,
          minHeight: maxHeight ~/ 2,
          quality: q,
        );
        q -= 10;
      }
    }

    return result ?? originalBytes;
  }

  String _getContentType(String extension) {
    switch (extension) {
      case '.jpg':
      case '.jpeg':
        return 'image/jpeg';
      case '.png':
        return 'image/png';
      case '.webp':
        return 'image/webp';
      default:
        return 'image/jpeg';
    }
  }
}

