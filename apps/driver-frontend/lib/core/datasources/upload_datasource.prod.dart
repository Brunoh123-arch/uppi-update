import 'package:flutter/foundation.dart';

import 'package:flutter_common/core/entities/media.dart';
import 'package:injectable/injectable.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:path/path.dart' as path;


import 'upload_datasource.dart';

/// Upload datasource com compressão inteligente antes do envio.
/// Metas:
///   - Foto de perfil → máx 150 KB (qualidade visual mantida)
///   - Documentos (CNH, CRLV) → máx 300 KB (legibilidade preservada)
/// Economiza até 95% do espaço no Supabase Storage.
@prod
@LazySingleton(as: UploadDatasource)
class UploadDatasourceImpl implements UploadDatasource {
  final SupabaseClient _supabase = Supabase.instance.client;

  UploadDatasourceImpl();

  String? get _uid => _supabase.auth.currentUser?.id;

  Future<String> _resolveUid() async {
    if (_uid != null) return _uid!;

    throw Exception(
      'Não foi possível autenticar para upload. Faça login primeiro.',
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

    // Comprime para máx 150KB — preserva qualidade visual do rosto
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

  @override
  Future<MediaEntity> uploadMedia(XFile file, String folder) async {
    final uid = await _resolveUid();
    var extension = path.extension(file.name).toLowerCase();
    if (extension.isEmpty) {
      if (file.mimeType == 'image/png') {
        extension = '.png';
      } else if (file.mimeType == 'image/webp') extension = '.webp';
      else extension = '.jpg';
    }
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final storagePath = '$uid/$folder/$timestamp$extension';

    // Documentos como CNH e CRLV — comprime para máx 300KB
    // mantendo resolução suficiente para leitura do texto
    final compressed = await _compressImage(
      file.path,
      maxSizeKb: 300,
      quality: 85,
      maxWidth: 1200,
      maxHeight: 1200,
    );

    await _supabase.storage.from('documents').uploadBinary(
          storagePath,
          compressed,
          fileOptions: FileOptions(
            contentType: _getContentType(extension),
            upsert: true,
          ),
        );

    final downloadUrl = await _supabase.storage
        .from('documents')
        .createSignedUrl(storagePath, 315360000);

    return MediaEntity(id: storagePath, address: downloadUrl);
  }

  @override
  Future<MediaEntity> uploadDocument(String filePath) async {
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
    final storagePath = '$uid/documents/$timestamp$extension';

    final compressed = await _compressImage(
      filePath,
      maxSizeKb: 300,
      quality: 85,
      maxWidth: 1200,
      maxHeight: 1200,
    );

    await _supabase.storage.from('documents').uploadBinary(
          storagePath,
          compressed,
          fileOptions: FileOptions(
            contentType: _getContentType(extension),
            upsert: true,
          ),
        );

    final downloadUrl = await _supabase.storage
        .from('documents')
        .createSignedUrl(storagePath, 315360000);

    return MediaEntity(id: storagePath, address: downloadUrl);
  }

  @override
  Future<void> deleteDocument(String storagePath) async {
    try {
      await _supabase.storage.from('documents').remove([storagePath]);
      debugPrint('[UploadDatasource] Documento obsoleto deletado do Storage: $storagePath');
    } catch (e) {
      debugPrint('[UploadDatasource] Erro ao deletar documento do Storage: $e');
    }
  }

  /// Comprime uma imagem para um tamanho máximo alvo.
  /// Tenta qualidade progressivamente menor até atingir o alvo.
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

    // Se já está dentro do limite, não comprime
    if (originalBytes.lengthInBytes <= maxSizeKb * 1024) {
      return originalBytes;
    }

    try {
      // Compressão inicial
      Uint8List? result = await FlutterImageCompress.compressWithList(
        originalBytes,
        minWidth: maxWidth,
        minHeight: maxHeight,
        quality: quality,
      );

      // Se ainda muito grande, reduz qualidade progressivamente
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
    } catch (e) {
      // Fallback seguro em caso de falha no plugin nativo de compressão
      debugPrint('[UploadDatasource] Erro na compressão nativa da imagem: $e. Usando arquivo original como fallback.');
      return originalBytes;
    }
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

