import 'package:auto_route/auto_route.dart';
import 'package:flutter/material.dart';
import 'package:flutter_common/core/color_palette/color_palette.dart';
import 'package:flutter_common/core/presentation/snackbar/snackbar.dart';
import 'package:ionicons/ionicons.dart';
import 'package:rider_flutter/config/locator/locator.dart';
import 'package:rider_flutter/core/extensions/extensions.dart';
import 'package:flutter_common/core/presentation/buttons/app_primary_button.dart';
import 'package:flutter_common/core/presentation/responsive_dialog/app_responsive_dialog.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../blocs/wallet.dart';

class RiderWithdrawDialog extends StatefulWidget {
  final double availableBalance;
  final String currency;

  const RiderWithdrawDialog({
    super.key,
    required this.availableBalance,
    required this.currency,
  });

  @override
  State<RiderWithdrawDialog> createState() => _RiderWithdrawDialogState();
}

class _RiderWithdrawDialogState extends State<RiderWithdrawDialog> {
  final SupabaseClient _supabase = Supabase.instance.client;
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  final GlobalKey<FormState> _accountFormKey = GlobalKey<FormState>();

  final TextEditingController _amountController = TextEditingController();
  final TextEditingController _pixKeyController = TextEditingController();
  final TextEditingController _holderNameController = TextEditingController();
  final TextEditingController _bankNameController = TextEditingController();

  String _selectedKeyType = 'CPF';
  bool _isLoading = true;
  bool _isCreatingAccount = false;
  bool _isSubmitting = false;

  List<Map<String, dynamic>> _payoutAccounts = [];
  Map<String, dynamic>? _selectedAccount;

  @override
  void initState() {
    super.initState();
    _loadPayoutAccounts();
  }

  @override
  void dispose() {
    _amountController.dispose();
    _pixKeyController.dispose();
    _holderNameController.dispose();
    _bankNameController.dispose();
    super.dispose();
  }

  Future<void> _loadPayoutAccounts() async {
    setState(() {
      _isLoading = true;
    });

    try {
      final uid = _supabase.auth.currentUser?.id;
      if (uid == null) {
        throw Exception("Usuário não autenticado");
      }

      final data = await _supabase
          .from('payout_accounts')
          .select()
          .eq('driver_id', uid)
          .order('created_at', ascending: false);

      final accounts = List<Map<String, dynamic>>.from(data);

      setState(() {
        _payoutAccounts = accounts;
        if (accounts.isNotEmpty) {
          _selectedAccount = accounts.firstWhere(
            (acc) => acc['is_default'] == true,
            orElse: () => accounts.first,
          );
          _isCreatingAccount = false;
        } else {
          _isCreatingAccount = true;
        }
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _isLoading = false;
      });
      if (mounted) context.showErrorSnackBar(e, fallback: 'Não foi possível carregar suas contas de saque.');
    }
  }

  Future<void> _registerPayoutAccount() async {
    if (_accountFormKey.currentState?.validate() != true) return;

    setState(() {
      _isSubmitting = true;
    });

    try {
      final uid = _supabase.auth.currentUser?.id;
      if (uid == null) {
        throw Exception("Usuário não autenticado");
      }

      await _supabase.functions.invoke(
        'user-actions',
        body: {
          'action': 'insert',
          'table': 'payout_accounts',
          'data': {
            'account_number': _pixKeyController.text.trim(),
            'routing_number': _selectedKeyType,
            'account_holder_name': _holderNameController.text.trim(),
            'bank_name': _bankNameController.text.trim().isNotEmpty 
                ? _bankNameController.text.trim() 
                : 'Banco Pix',
            'is_default': _payoutAccounts.isEmpty,
          },
        },
      );

      // Limpar campos
      _pixKeyController.clear();
      _holderNameController.clear();
      _bankNameController.clear();

      if (!mounted) return;
      context.showSnackBar(message: "Chave Pix cadastrada com sucesso!");
      await _loadPayoutAccounts();
    } catch (e) {
      setState(() {
        _isSubmitting = false;
      });
      if (mounted) context.showErrorSnackBar(e, fallback: 'Não foi possível cadastrar a chave Pix.');
    }
  }

  Future<void> _submitWithdrawRequest() async {
    if (_formKey.currentState?.validate() != true) return;

    if (_selectedAccount == null) {
      context.showSnackBar(message: "Selecione uma chave Pix para a transferência");
      return;
    }

    final amountStr = _amountController.text.replaceAll(',', '.');
    final amount = double.tryParse(amountStr);

    if (amount == null || amount <= 0) {
      context.showSnackBar(message: "Digite um valor de saque válido");
      return;
    }

    if (amount > widget.availableBalance) {
      context.showSnackBar(message: "Saldo insuficiente");
      return;
    }

    setState(() {
      _isSubmitting = true;
    });

    try {
      final uid = _supabase.auth.currentUser?.id;
      if (uid == null) {
        throw Exception("Usuário não autenticado");
      }

      await _supabase.functions.invoke(
        'user-actions',
        body: {
          'action': 'insert',
          'table': 'payout_requests',
          'data': {
            'payout_account_id': _selectedAccount!['id'],
            'amount': amount,
          },
        },
      );

      setState(() {
        _isSubmitting = false;
      });

      if (!mounted) return;
      context.showSnackBar(message: "Solicitação de saque Pix enviada para processamento!");
      locator<WalletBloc>().load();
      context.router.maybePop(true);
    } catch (e) {
      setState(() {
        _isSubmitting = false;
      });
      if (mounted) context.showErrorSnackBar(e, fallback: 'Não foi possível solicitar o saque Pix.');
    }
  }

  @override
  Widget build(BuildContext context) {
    return AppResponsiveDialog(
      type: context.responsive(DialogType.bottomSheet, xl: DialogType.dialog),
      onBackPressed: () => context.router.maybePop(),
      header: (Ionicons.cash, "Retirada Pix", null),
      primaryButton: _isLoading
          ? null
          : AppPrimaryButton(
              isDisabled: _isSubmitting,
              onPressed: _isCreatingAccount ? _registerPayoutAccount : _submitWithdrawRequest,
              child: _isSubmitting
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                    )
                  : Text(_isCreatingAccount ? "Cadastrar Chave Pix" : "Confirmar Saque Pix"),
            ),
      child: _isLoading
          ? const Center(
              child: Padding(
                padding: EdgeInsets.all(32.0),
                child: CircularProgressIndicator(),
              ),
            )
          : _isCreatingAccount
              ? _buildCreateAccountForm()
              : _buildWithdrawForm(),
    );
  }

  Widget _buildCreateAccountForm() {
    return Form(
      key: _accountFormKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                "Cadastrar Chave Pix",
                style: context.titleMedium?.copyWith(fontWeight: FontWeight.bold),
              ),
              if (_payoutAccounts.isNotEmpty)
                TextButton(
                  onPressed: () {
                    setState(() {
                      _isCreatingAccount = false;
                    });
                  },
                  child: const Text("Voltar"),
                ),
            ],
          ),
          const SizedBox(height: 16),
          Text(
            "Selecione o tipo de chave Pix:",
            style: context.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(
              color: ColorPalette.neutralVariant95,
              borderRadius: BorderRadius.circular(12),
            ),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                value: _selectedKeyType,
                isExpanded: true,
                onChanged: (val) {
                  if (val != null) {
                    setState(() {
                      _selectedKeyType = val;
                    });
                  }
                },
                items: const [
                  DropdownMenuItem(value: 'CPF', child: Text('CPF')),
                  DropdownMenuItem(value: 'CNPJ', child: Text('CNPJ')),
                  DropdownMenuItem(value: 'Email', child: Text('E-mail')),
                  DropdownMenuItem(value: 'Telefone', child: Text('Celular')),
                  DropdownMenuItem(value: 'Chave Aleatoria', child: Text('Chave Aleatória')),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            "Chave Pix",
            style: context.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 8),
          TextFormField(
            controller: _pixKeyController,
            decoration: InputDecoration(
              hintText: 'Digite a chave Pix',
              filled: true,
              fillColor: ColorPalette.neutralVariant95,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none,
              ),
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
            ),
            validator: (value) {
              if (value == null || value.trim().isEmpty) {
                return "A chave Pix é obrigatória";
              }
              return null;
            },
          ),
          const SizedBox(height: 16),
          Text(
            "Nome do Titular da Conta",
            style: context.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 8),
          TextFormField(
            controller: _holderNameController,
            decoration: InputDecoration(
              hintText: 'Nome completo do titular',
              filled: true,
              fillColor: ColorPalette.neutralVariant95,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none,
              ),
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
            ),
            validator: (value) {
              if (value == null || value.trim().isEmpty) {
                return "O nome do titular é obrigatório";
              }
              return null;
            },
          ),
          const SizedBox(height: 16),
          Text(
            "Nome do Banco (Opcional)",
            style: context.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 8),
          TextFormField(
            controller: _bankNameController,
            decoration: InputDecoration(
              hintText: 'Ex: Nubank, Itaú, etc.',
              filled: true,
              fillColor: ColorPalette.neutralVariant95,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none,
              ),
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
            ),
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }

  Widget _buildWithdrawForm() {
    return Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          // Card de Saldo Disponível
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: ColorPalette.primary30.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: ColorPalette.primary30.withValues(alpha: 0.15),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  "Saldo disponível para retirada",
                  style: context.bodySmall?.copyWith(color: ColorPalette.neutral40),
                ),
                const SizedBox(height: 4),
                Text(
                  widget.availableBalance.formatCurrency(widget.currency),
                  style: context.headlineMedium?.copyWith(
                    color: ColorPalette.primary30,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),

          // Seletor de Chave Pix
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                "Receber na Chave Pix",
                style: context.titleSmall?.copyWith(fontWeight: FontWeight.bold),
              ),
              TextButton.icon(
                onPressed: () {
                  setState(() {
                    _isCreatingAccount = true;
                  });
                },
                icon: const Icon(Ionicons.add_circle_outline, size: 16),
                label: const Text("Nova chave"),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(
              color: ColorPalette.neutralVariant95,
              borderRadius: BorderRadius.circular(12),
            ),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<Map<String, dynamic>>(
                value: _selectedAccount,
                isExpanded: true,
                icon: const Icon(Ionicons.chevron_down_outline),
                borderRadius: BorderRadius.circular(12),
                onChanged: (account) {
                  setState(() {
                    _selectedAccount = account;
                  });
                },
                items: _payoutAccounts.map((account) {
                  return DropdownMenuItem<Map<String, dynamic>>(
                    value: account,
                    child: Row(
                      children: [
                        const Icon(Ionicons.key_outline, size: 16, color: ColorPalette.primary40),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text(
                                account['account_holder_name'] ?? 'Titular',
                                style: context.bodyMedium?.copyWith(fontWeight: FontWeight.bold),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              Text(
                                "${account['routing_number'] ?? 'Pix'}: ${account['account_number'] ?? ''}",
                                style: context.bodySmall?.copyWith(color: ColorPalette.neutral40),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  );
                }).toList(),
              ),
            ),
          ),
          const SizedBox(height: 24),

          // Campo de Valor do Saque
          Text(
            "Valor da Retirada",
            style: context.titleSmall?.copyWith(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          TextFormField(
            controller: _amountController,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            style: context.bodyLarge?.copyWith(fontWeight: FontWeight.bold),
            decoration: InputDecoration(
              prefixText: widget.currency == 'BRL' ? r'R$ ' : '${widget.currency} ',
              prefixStyle: context.bodyLarge?.copyWith(fontWeight: FontWeight.bold),
              hintText: '0,00',
              filled: true,
              fillColor: ColorPalette.neutralVariant95,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none,
              ),
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
            ),
            validator: (value) {
              if (value == null || value.trim().isEmpty) {
                return "O valor é obrigatório";
              }
              final parsedVal = double.tryParse(value.replaceAll(',', '.'));
              if (parsedVal == null || parsedVal <= 0) {
                return "Digite um valor válido";
              }
              if (parsedVal > widget.availableBalance) {
                return "Saldo insuficiente";
              }
              return null;
            },
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }
}
