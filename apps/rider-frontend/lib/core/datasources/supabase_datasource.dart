import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class SupabaseDatasource {
  final SupabaseClient client;

  SupabaseDatasource({
    required this.client,
  });

  String? get uid => client.auth.currentUser?.id;

  User? get currentUser => client.auth.currentUser;

  Future<Map<String, dynamic>?> getDocument(String table, String id) async {
    try {
      final data = await client.from(table).select().eq('id', id).single();
      return data;
    } catch (e) {
      debugPrint('[SupabaseDatasource] Erro ao buscar documento na tabela "$table" (ID: $id): $e');
      return null;
    }
  }

  Future<List<Map<String, dynamic>>> getCollection(String table) async {
    final data = await client.from(table).select();
    return List<Map<String, dynamic>>.from(data);
  }



  Stream<Map<String, dynamic>?> watchDocument(String table, String id) {
    return client
        .from(table)
        .stream(primaryKey: ['id'])
        .eq('id', id)
        .map((events) {
          if (events.isEmpty) return null;
          return events.first;
        });
  }

  Stream<List<Map<String, dynamic>>> watchCollection(
    String table, {
    String? orderBy,
  }) {
    var query = client.from(table).stream(primaryKey: ['id']);
    // Nota: O order by no stream do Supabase pode exigir customização adicional
    return query.map((events) => List<Map<String, dynamic>>.from(events));
  }

  Future<void> signOut() async {
    await client.auth.signOut();
  }
}
