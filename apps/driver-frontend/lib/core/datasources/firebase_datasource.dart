import 'package:injectable/injectable.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Datasource central — 100% Supabase.
/// Firebase Auth removido (projeto suspenso). UID agora vem do Supabase Auth.
@lazySingleton
class FirebaseDatasource {
  final SupabaseClient supabaseClient;

  FirebaseDatasource({required this.supabaseClient});

  String? get uid => supabaseClient.auth.currentUser?.id;

  dynamic get auth => _FakeAuth(supabaseClient);

  /// Getter para compatibilidade com código legado (ex: profile_repository)
  _FakeUser? get currentUser {
    final user = supabaseClient.auth.currentUser;
    if (user == null) return null;
    return _FakeUser(supabaseClient);
  }

  Future<void> signOut() async {
    await supabaseClient.auth.signOut();
  }

  Future<Map<String, dynamic>?> getDocument(String table, String id) async {
    final row = await supabaseClient
        .from(table)
        .select()
        .eq('id', id)
        .maybeSingle();
    return row;
  }

  Future<List<Map<String, dynamic>>> getCollection(String table) async {
    final rows = await supabaseClient.from(table).select();
    return List<Map<String, dynamic>>.from(rows);
  }

  Future<void> updateDocument(
    String table,
    String id,
    Map<String, dynamic> data,
  ) async {
    await supabaseClient.from(table).update(data).eq('id', id);
  }
}

class _FakeAuth {
  final SupabaseClient client;
  _FakeAuth(this.client);

  dynamic get currentUser => _FakeUser(client);
}

class _FakeUser {
  final SupabaseClient client;
  _FakeUser(this.client);

  String get uid => client.auth.currentUser!.id;

  Future<String?> getIdToken() async {
    return client.auth.currentSession?.accessToken;
  }

  Future<void> delete() async {
    // Supabase user deletion handled server-side
  }
}
