import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class PrivacyLgpdScreen extends StatefulWidget {
  const PrivacyLgpdScreen({super.key});

  @override
  State<PrivacyLgpdScreen> createState() => _PrivacyLgpdScreenState();
}

class _PrivacyLgpdScreenState extends State<PrivacyLgpdScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  // Tab 1: Busca e Gestão de Titulares
  String _searchQuery = '';
  List<Map<String, dynamic>> _searchResults = [];
  bool _isSearching = false;
  Map<String, dynamic>? _selectedUser;
  bool _isLoadingDetails = false;
  List<Map<String, dynamic>> _userRides = [];
  List<Map<String, dynamic>> _userTransactions = [];

  // Tab 3: Configurações de Políticas e DPO
  final _privacyController = TextEditingController();
  final _termsController = TextEditingController();
  final _dpoEmailController = TextEditingController();
  final _dpoPhoneController = TextEditingController();
  bool _isLoadingConfig = false;
  bool _isSavingConfig = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _loadPrivacyConfig();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _privacyController.dispose();
    _termsController.dispose();
    _dpoEmailController.dispose();
    _dpoPhoneController.dispose();
    super.dispose();
  }

  // Carrega links e contatos do DPO a partir de app_settings
  Future<void> _loadPrivacyConfig() async {
    setState(() => _isLoadingConfig = true);
    try {
      final data = await Supabase.instance.client
          .from('app_settings')
          .select('key, value')
          .inFilter('key', ['privacy_url', 'terms_url', 'support_email', 'support_phone']);

      for (var row in data) {
        final val = row['value']?.toString() ?? '';
        if (row['key'] == 'privacy_url') _privacyController.text = val;
        if (row['key'] == 'terms_url') _termsController.text = val;
        if (row['key'] == 'support_email') _dpoEmailController.text = val;
        if (row['key'] == 'support_phone') _dpoPhoneController.text = val;
      }
    } catch (e) {
      _showSnackBar('Erro ao carregar configurações: $e', Colors.redAccent);
    } finally {
      if (mounted) setState(() => _isLoadingConfig = false);
    }
  }

  // Salva links e contatos do DPO no app_settings
  Future<void> _savePrivacyConfig() async {
    setState(() => _isSavingConfig = true);
    try {
      final updates = [
        {'key': 'privacy_url', 'value': _privacyController.text.trim()},
        {'key': 'terms_url', 'terms_url': _termsController.text.trim(), 'value': _termsController.text.trim()},
        {'key': 'support_email', 'value': _dpoEmailController.text.trim()},
        {'key': 'support_phone', 'value': _dpoPhoneController.text.trim()},
      ];

      // Remove a chave duplicada do Map antes de upsertar
      final cleanedUpdates = updates.map((m) => {'key': m['key'], 'value': m['value']}).toList();

      await Supabase.instance.client.from('app_settings').upsert(cleanedUpdates);
      _showSnackBar('Configurações de privacidade salvas com sucesso!', Colors.greenAccent);
    } catch (e) {
      _showSnackBar('Erro ao salvar configurações: $e', Colors.redAccent);
    } finally {
      if (mounted) setState(() => _isSavingConfig = false);
    }
  }

  // Busca de usuários ativos
  Future<void> _searchUsers() async {
    if (_searchQuery.trim().isEmpty) return;
    setState(() {
      _isSearching = true;
      _selectedUser = null;
    });

    try {
      final data = await Supabase.instance.client
          .from('profiles')
          .select()
          .or('full_name.ilike.%$_searchQuery%,email.ilike.%$_searchQuery%,cpf.eq.$_searchQuery')
          .eq('is_deleted', false)
          .limit(20);

      setState(() {
        _searchResults = List<Map<String, dynamic>>.from(data);
        _isSearching = false;
      });
    } catch (e) {
      setState(() => _isSearching = false);
      _showSnackBar('Erro na busca: $e', Colors.redAccent);
    }
  }

  // Carrega detalhes completos do usuário para exportação de dados
  Future<void> _loadUserDetails(Map<String, dynamic> user) async {
    setState(() {
      _selectedUser = user;
      _isLoadingDetails = true;
      _userRides = [];
      _userTransactions = [];
    });

    try {
      final userId = user['id'];
      final isDriver = user['role'] == 'driver';

      // Busca corridas associadas
      final ridesData = await Supabase.instance.client
          .from('rides')
          .select('id, created_at, status, fare, service_type, pickup_address, dropoff_address')
          .eq(isDriver ? 'driver_id' : 'rider_id', userId)
          .order('created_at', ascending: false)
          .limit(50);

      // Busca transações financeiras
      final txData = await Supabase.instance.client
          .from('wallet_transactions')
          .select('id, created_at, amount, type, description, status')
          .eq('user_id', userId)
          .order('created_at', ascending: false)
          .limit(50);

      setState(() {
        _userRides = List<Map<String, dynamic>>.from(ridesData);
        _userTransactions = List<Map<String, dynamic>>.from(txData);
        _isLoadingDetails = false;
      });
    } catch (e) {
      setState(() => _isLoadingDetails = false);
      _showSnackBar('Erro ao buscar detalhes adicionais: $e', Colors.redAccent);
    }
  }

  // Exportar/Copiar Portabilidade de dados como JSON
  void _exportUserData() {
    if (_selectedUser == null) return;

    final exportData = {
      'timestamp_exportacao': DateTime.now().toUtc().toIso8601String(),
      'perfil': _selectedUser,
      'historico_corridas': _userRides,
      'historico_financeiro': _userTransactions,
    };

    final jsonString = const JsonEncoder.withIndent('  ').convert(exportData);

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            const Icon(Icons.download_rounded, color: Colors.tealAccent),
            const SizedBox(width: 10),
            Text('Exportar Dados (Portabilidade)', style: GoogleFonts.outfit()),
          ],
        ),
        content: SizedBox(
          width: 600,
          height: 400,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Os dados pessoais e operacionais do usuário foram estruturados no formato JSON de portabilidade (art. 18, V da LGPD).',
                style: TextStyle(color: Colors.white70, fontSize: 13),
              ),
              const SizedBox(height: 12),
              Expanded(
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.black26,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.white10),
                  ),
                  child: SingleChildScrollView(
                    child: SelectableText(
                      jsonString,
                      style: const TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 12,
                        color: Colors.lightGreenAccent,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Fechar', style: TextStyle(color: Colors.white54)),
          ),
          ElevatedButton.icon(
            onPressed: () {
              Clipboard.setData(ClipboardData(text: jsonString));
              _showSnackBar('JSON copiado para a área de transferência!', Colors.greenAccent);
              Navigator.pop(context);
            },
            icon: const Icon(Icons.copy),
            label: const Text('Copiar JSON'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.teal,
              foregroundColor: Colors.white,
            ),
          ),
        ],
      ),
    );
  }

  // Confirma e processa solicitação de exclusão (Soft Delete) via Edge Function
  Future<void> _requestAccountDeletion(String userId) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            const Icon(Icons.warning_amber_rounded, color: Colors.redAccent),
            const SizedBox(width: 10),
            Text('Solicitar Exclusão de Conta', style: GoogleFonts.outfit()),
          ],
        ),
        content: const Text(
          'Atenção: Esta ação irá mascarar os dados pessoais do usuário (nome, e-mail, telefone, CPF) e marcar a conta como deletada. Esta ação cumpre o Artigo 16 da LGPD e NÃO pode ser desfeita. Confirmar exclusão?',
          style: TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar', style: TextStyle(color: Colors.white54)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent, foregroundColor: Colors.white),
            child: const Text('Excluir Definitivamente'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    _showSnackBar('Processando solicitação de exclusão...', Colors.amber);

    try {
      final response = await Supabase.instance.client.functions.invoke(
        'delete-user-account',
        body: {'uid': userId},
      );

      if (response.status == 200) {
        _showSnackBar('Conta excluída e dados pessoais anonimizados com sucesso!', Colors.greenAccent);
        setState(() {
          _selectedUser = null;
          _searchResults.removeWhere((u) => u['id'] == userId);
        });
      } else {
        throw 'Erro retornado pela API: Status ${response.status}';
      }
    } catch (e) {
      _showSnackBar('Falha ao excluir conta: $e', Colors.redAccent);
    }
  }

  void _showSnackBar(String message, Color color) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: color, duration: const Duration(seconds: 4)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Header
        Container(
          padding: const EdgeInsets.fromLTRB(32, 20, 32, 0),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface,
            border: const Border(bottom: BorderSide(color: Colors.white10)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.gavel_rounded, color: Colors.tealAccent, size: 28),
                  const SizedBox(width: 12),
                  Text(
                    'Privacidade e Conformidade LGPD',
                    style: GoogleFonts.outfit(
                      fontSize: 28,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              TabBar(
                controller: _tabController,
                indicatorColor: Colors.tealAccent,
                labelColor: Colors.tealAccent,
                unselectedLabelColor: Colors.white54,
                tabs: const [
                  Tab(
                    icon: Icon(Icons.search, size: 18),
                    text: 'Direitos do Titular (Art. 18)',
                  ),
                  Tab(
                    icon: Icon(Icons.delete_sweep, size: 18),
                    text: 'Contas Excluídas (Real-time)',
                  ),
                  Tab(
                    icon: Icon(Icons.settings, size: 18),
                    text: 'Políticas & DPO',
                  ),
                ],
              ),
            ],
          ),
        ),

        Expanded(
          child: TabBarView(
            controller: _tabController,
            children: [
              _buildRightsManagementTab(),
              _buildDeletedAccountsTab(),
              _buildSettingsTab(),
            ],
          ),
        ),
      ],
    );
  }

  // ABA 1: Busca de Usuários e Exercício de Direitos (Portabilidade/Exclusão)
  Widget _buildRightsManagementTab() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Painel de busca e listagem (Esquerda)
        Expanded(
          flex: 2,
          child: Container(
            padding: const EdgeInsets.all(24),
            decoration: const BoxDecoration(
              border: Border(right: BorderSide(color: Colors.white10)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Buscar Titular para Solicitação',
                  style: GoogleFonts.outfit(fontSize: 18, fontWeight: FontWeight.w500),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        onChanged: (v) => _searchQuery = v,
                        onSubmitted: (_) => _searchUsers(),
                        decoration: InputDecoration(
                          hintText: 'Digite nome, e-mail ou CPF do usuário...',
                          prefixIcon: const Icon(Icons.search),
                          filled: true,
                          fillColor: Colors.white.withAlpha(15),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide.none,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    ElevatedButton(
                      onPressed: _searchUsers,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.teal,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      child: const Text('Buscar'),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                if (_isSearching)
                  const Expanded(child: Center(child: CircularProgressIndicator()))
                else if (_searchResults.isEmpty)
                  const Expanded(
                    child: Center(
                      child: Text(
                        'Nenhum usuário buscado ou encontrado.',
                        style: TextStyle(color: Colors.white38),
                      ),
                    ),
                  )
                else
                  Expanded(
                    child: ListView.builder(
                      itemCount: _searchResults.length,
                      itemBuilder: (context, index) {
                        final u = _searchResults[index];
                        final isSelected = _selectedUser?['id'] == u['id'];
                        return Card(
                          color: isSelected
                              ? Colors.teal.withAlpha(50)
                              : Theme.of(context).colorScheme.surface.withAlpha(200),
                          margin: const EdgeInsets.only(bottom: 8),
                          child: ListTile(
                            leading: CircleAvatar(
                              backgroundColor: Colors.teal.withAlpha(50),
                              child: Icon(
                                u['role'] == 'driver' ? Icons.drive_eta : Icons.person,
                                color: Colors.tealAccent,
                              ),
                            ),
                            title: Text(
                              u['full_name'] ?? 'Nome não cadastrado',
                              style: const TextStyle(fontWeight: FontWeight.bold),
                            ),
                            subtitle: Text('${u['email'] ?? 'Sem email'} • CPF: ${u['cpf'] ?? 'Não informado'}'),
                            trailing: const Icon(Icons.chevron_right, color: Colors.white38),
                            onTap: () => _loadUserDetails(u),
                          ),
                        );
                      },
                    ),
                  ),
              ],
            ),
          ),
        ),

        // Detalhes do Usuário Selecionado & Ações de LGPD (Direita)
        Expanded(
          flex: 3,
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: _selectedUser == null
                ? const Center(
                    child: Text(
                      'Selecione um usuário na busca para exercer os direitos LGPD.',
                      style: TextStyle(color: Colors.white38),
                    ),
                  )
                : _isLoadingDetails
                    ? const Center(child: CircularProgressIndicator())
                    : SingleChildScrollView(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      _selectedUser!['full_name'] ?? 'Nome Indefinido',
                                      style: GoogleFonts.outfit(fontSize: 22, fontWeight: FontWeight.bold),
                                    ),
                                    Text(
                                      'ID do Titular: ${_selectedUser!['id']}',
                                      style: const TextStyle(color: Colors.white54, fontSize: 12),
                                    ),
                                  ],
                                ),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                  decoration: BoxDecoration(
                                    color: Colors.teal.withAlpha(40),
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(color: Colors.tealAccent.withAlpha(100)),
                                  ),
                                  child: Text(
                                    _selectedUser!['role'] == 'driver' ? 'MOTORISTA' : 'PASSAGEIRO',
                                    style: const TextStyle(
                                      color: Colors.tealAccent,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 11,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const Divider(height: 32, color: Colors.white12),

                            // Ficha de Informações Pessoais
                            Card(
                              color: Colors.white.withAlpha(10),
                              child: Padding(
                                padding: const EdgeInsets.all(16),
                                child: Column(
                                  children: [
                                    _buildInfoRow('Nome Completo', _selectedUser!['full_name'] ?? '-'),
                                    _buildInfoRow('E-mail', _selectedUser!['email'] ?? '-'),
                                    _buildInfoRow('Telefone', _selectedUser!['phone'] ?? _selectedUser!['phone_number'] ?? '-'),
                                    _buildInfoRow('CPF', _selectedUser!['cpf'] ?? '-'),
                                    _buildInfoRow('Data de Criação', _selectedUser!['created_at'] != null ? DateTime.tryParse(_selectedUser!['created_at'].toString())?.toLocal().toString().substring(0, 16) ?? '-' : '-'),
                                    _buildInfoRow('Verificação de Identidade', _selectedUser!['identity_verification_status'] ?? 'Não Verificado'),
                                  ],
                                ),
                              ),
                            ),
                            const SizedBox(height: 24),

                            // Métricas de Volume de Dados
                            Row(
                              children: [
                                Expanded(
                                  child: _buildDataMetricCard(
                                    icon: Icons.history_rounded,
                                    title: 'Corridas Registradas',
                                    value: '${_userRides.length} corridas',
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: _buildDataMetricCard(
                                    icon: Icons.account_balance_wallet_rounded,
                                    title: 'Transações de Carteira',
                                    value: '${_userTransactions.length} txs',
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 32),

                            // Seção de Exercício de Direitos (Ações Críticas)
                            Text(
                              'Ações de Conformidade Legal (Art. 18)',
                              style: GoogleFonts.outfit(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.tealAccent),
                            ),
                            const SizedBox(height: 12),
                            Row(
                              children: [
                                Expanded(
                                  child: ElevatedButton.icon(
                                    onPressed: _exportUserData,
                                    icon: const Icon(Icons.download_rounded),
                                    label: const Text('Exportar Dados (Portabilidade)'),
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: Colors.teal,
                                      foregroundColor: Colors.white,
                                      padding: const EdgeInsets.symmetric(vertical: 16),
                                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: ElevatedButton.icon(
                                    onPressed: () => _requestAccountDeletion(_selectedUser!['id']),
                                    icon: const Icon(Icons.delete_forever_rounded),
                                    label: const Text('Excluir Conta (Art. 16)'),
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: Colors.redAccent,
                                      foregroundColor: Colors.white,
                                      padding: const EdgeInsets.symmetric(vertical: 16),
                                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
          ),
        ),
      ],
    );
  }

  // ABA 2: Solicitações de Exclusão (Real-time Stream)
  Widget _buildDeletedAccountsTab() {
    return StreamBuilder<List<Map<String, dynamic>>>(
      stream: Supabase.instance.client
          .from('profiles')
          .stream(primaryKey: ['id'])
          .eq('is_deleted', true),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return Center(
            child: Text(
              'Erro ao carregar dados: ${snapshot.error}',
              style: const TextStyle(color: Colors.redAccent),
            ),
          );
        }

        final items = snapshot.data ?? [];
        if (items.isEmpty) {
          return const Center(
            child: Text(
              'Nenhuma solicitação de exclusão processada no momento.',
              style: TextStyle(color: Colors.white38),
            ),
          );
        }

        return ListView.builder(
          padding: const EdgeInsets.all(32),
          itemCount: items.length,
          itemBuilder: (context, index) {
            final u = items[index];
            final deletionDate = u['deleted_at'] != null
                ? DateTime.tryParse(u['deleted_at'].toString())?.toLocal()
                : null;

            return Card(
              color: Theme.of(context).colorScheme.surface.withAlpha(200),
              margin: const EdgeInsets.only(bottom: 12),
              child: ListTile(
                leading: const Icon(Icons.no_accounts_rounded, color: Colors.redAccent, size: 32),
                title: Text(
                  'ID do Usuário Excluído: ${u['id']}',
                  style: const TextStyle(fontWeight: FontWeight.bold, fontFamily: 'monospace', fontSize: 13),
                ),
                subtitle: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(height: 4),
                    Text(
                      'Tipo: ${u['role'] == 'driver' ? 'Motorista' : 'Passageiro'} • Status da conta: ${u['status']}',
                      style: const TextStyle(color: Colors.white70),
                    ),
                    if (deletionDate != null)
                      Text(
                        'Excluído em: ${deletionDate.day.toString().padLeft(2, '0')}/${deletionDate.month.toString().padLeft(2, '0')}/${deletionDate.year} ${deletionDate.hour.toString().padLeft(2, '0')}:${deletionDate.minute.toString().padLeft(2, '0')}',
                        style: const TextStyle(color: Colors.white38, fontSize: 11),
                      ),
                  ],
                ),
                trailing: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.redAccent.withAlpha(40),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Text(
                    'Anonimizado / Deletado',
                    style: TextStyle(color: Colors.redAccent, fontSize: 11, fontWeight: FontWeight.bold),
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  // ABA 3: Configuração de Políticas
  Widget _buildSettingsTab() {
    if (_isLoadingConfig) {
      return const Center(child: CircularProgressIndicator());
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(32),
      child: Center(
        child: SizedBox(
          width: 800,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Links Legais e Contato do Encarregado (DPO)',
                style: GoogleFonts.outfit(fontSize: 20, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              const Text(
                'Defina os links dos termos legais exibidos nos aplicativos e o e-mail do canal de privacidade (exigido pelos Artigos 9 e 41 da LGPD).',
                style: TextStyle(color: Colors.white54, fontSize: 13),
              ),
              const Divider(height: 32, color: Colors.white10),

              // Links
              _buildConfigTextField(
                controller: _privacyController,
                label: 'URL da Política de Privacidade',
                hint: 'https://exemplo.com/privacidade.html',
                icon: Icons.privacy_tip_outlined,
              ),
              const SizedBox(height: 16),
              _buildConfigTextField(
                controller: _termsController,
                label: 'URL dos Termos de Uso',
                hint: 'https://exemplo.com/termos.html',
                icon: Icons.description_outlined,
              ),
              const SizedBox(height: 16),
              _buildConfigTextField(
                controller: _dpoEmailController,
                label: 'E-mail do DPO / Canal de Privacidade',
                hint: 'privacidade@exemplo.com',
                icon: Icons.email_outlined,
              ),
              const SizedBox(height: 16),
              _buildConfigTextField(
                controller: _dpoPhoneController,
                label: 'Telefone de Suporte / DPO',
                hint: '+5511999999999',
                icon: Icons.phone_android_outlined,
              ),
              const SizedBox(height: 32),

              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  ElevatedButton.icon(
                    onPressed: _isSavingConfig ? null : _savePrivacyConfig,
                    icon: _isSavingConfig
                        ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.save_rounded),
                    label: const Text('Salvar Parâmetros'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.teal,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 20),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildConfigTextField({
    required TextEditingController controller,
    required String label,
    required String hint,
    required IconData icon,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.tealAccent)),
        const SizedBox(height: 8),
        TextField(
          controller: controller,
          decoration: InputDecoration(
            hintText: hint,
            prefixIcon: Icon(icon, color: Colors.white54),
            filled: true,
            fillColor: Colors.white.withAlpha(10),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: const BorderSide(color: Colors.white10),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: const BorderSide(color: Colors.tealAccent),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(color: Colors.white60, fontSize: 13)),
          Text(value, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
        ],
      ),
    );
  }

  Widget _buildDataMetricCard({
    required IconData icon,
    required String title,
    required String value,
  }) {
    return Card(
      color: Colors.white.withAlpha(5),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Icon(icon, size: 36, color: Colors.tealAccent),
            const SizedBox(width: 16),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(color: Colors.white54, fontSize: 12)),
                const SizedBox(height: 4),
                Text(value, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
