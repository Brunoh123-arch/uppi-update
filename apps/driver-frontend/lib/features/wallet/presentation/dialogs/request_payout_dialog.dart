import 'package:auto_route/auto_route.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_common/core/color_palette/color_palette.dart';
import 'package:flutter_common/core/presentation/snackbar/snackbar.dart';
import 'package:flutter_common/core/utils/friendly_error.dart';
import 'package:ionicons/ionicons.dart';
import 'package:uppi_motorista/config/locator/locator.dart';
import 'package:uppi_motorista/core/extensions/extensions.dart';
import 'package:flutter_common/core/presentation/buttons/app_primary_button.dart';
import 'package:flutter_common/core/presentation/responsive_dialog/app_responsive_dialog.dart';
import 'package:uppi_motorista/features/payout_methods/presentation/blocs/payout_accounts.dart';
import 'package:uppi_motorista/features/payout_methods/domain/entitites/payout_account.dart';
import 'package:uppi_motorista/core/error/failure.dart';
import '../blocs/wallet.dart';

class RequestPayoutDialog extends StatefulWidget {
  final double availableBalance;
  final String currency;

  const RequestPayoutDialog({
    super.key,
    required this.availableBalance,
    required this.currency,
  });

  @override
  State<RequestPayoutDialog> createState() => _RequestPayoutDialogState();
}

class _RequestPayoutDialogState extends State<RequestPayoutDialog> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  final TextEditingController _amountController = TextEditingController();
  PayoutAccountEntity? _selectedAccount;
  bool _isLoading = false;

  @override
  void initState() {
    locator<PayoutAccountsBloc>().load();
    super.initState();
  }

  @override
  void dispose() {
    _amountController.dispose();
    super.dispose();
  }

  void _submit() async {
    if (_formKey.currentState?.validate() != true) return;

    final accountsState = locator<PayoutAccountsBloc>().state;
    PayoutAccountEntity? activeAccount = _selectedAccount;
    if (activeAccount == null) {
      accountsState.mapOrNull(
        loaded: (loaded) {
          if (loaded.linkedMethods.isNotEmpty) {
            activeAccount = loaded.linkedMethods.defaultPayoutAccount ?? loaded.linkedMethods.first;
          }
        },
      );
    }

    if (activeAccount == null) {
      context.showSnackBar(message: "Selecione uma conta de saque (Pix)");
      return;
    }

    final amountStr = _amountController.text.replaceAll(',', '.');
    final amount = double.tryParse(amountStr);

    if (amount == null || amount <= 0) {
      context.showSnackBar(message: "Digite um valor válido para o saque");
      return;
    }

    if (amount > widget.availableBalance) {
      context.showSnackBar(message: "Saldo insuficiente");
      return;
    }

    setState(() {
      _isLoading = true;
    });

    final walletBloc = locator<WalletBloc>();
    final result = await walletBloc.requestPayout(
      amount: amount,
      payoutAccountId: activeAccount!.id,
    );

    setState(() {
      _isLoading = false;
    });

    result.fold(
      (failure) {
        context.showErrorSnackBar(failure.errorMessage, fallback: 'Não foi possível solicitar o saque.');
      },
      (_) {
        context.showSnackBar(message: "Solicitação de saque PIX enviada com sucesso!");
        context.router.maybePop(true);
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return BlocProvider.value(
      value: locator<PayoutAccountsBloc>(),
      child: AppResponsiveDialog(
        type: context.responsive(DialogType.bottomSheet, xl: DialogType.dialog),
        onBackPressed: () => context.router.maybePop(),
        header: (Ionicons.cash, "Solicitar Saque (Pix)", null),
        primaryButton: AppPrimaryButton(
          isDisabled: _isLoading,
          onPressed: _submit,
          child: _isLoading
              ? const SizedBox(
                  height: 20,
                  width: 20,
                  child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                )
              : const Text("Solicitar Saque"),
        ),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              // Card mostrando saldo disponível
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
                      "Saldo Disponível para Resgate",
                      style: context.bodySmall?.copyWith(
                        color: ColorPalette.neutral40,
                      ),
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

              // Campo de entrada de valor
              Text(
                "Valor do Saque",
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
                  if (value == null || value.isEmpty) {
                    return "Campo obrigatório";
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
              const SizedBox(height: 24),

              // Seletor de conta de recebimento (PIX)
              Text(
                "Receber na Chave Pix",
                style: context.titleSmall?.copyWith(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              BlocBuilder<PayoutAccountsBloc, PayoutAccountsState>(
                builder: (context, state) {
                  return state.map(
                    initial: (_) => const SizedBox(),
                    loading: (_) => const Center(
                      child: Padding(
                        padding: EdgeInsets.all(16.0),
                        child: CircularProgressIndicator(),
                      ),
                    ),
                    empty: (_) => Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          "Você não tem chave Pix cadastrada para receber.",
                          style: context.bodyMedium?.copyWith(color: ColorPalette.error40),
                        ),
                        const SizedBox(height: 8),
                        TextButton.icon(
                          onPressed: () {
                            context.router.pushNamed('/payout-methods');
                          },
                          icon: const Icon(Ionicons.add_circle_outline),
                          label: const Text("Cadastrar Chave Pix"),
                        ),
                      ],
                    ),
                    error: (error) => Text(friendlyErrorMessage(error.message, fallback: 'Não foi possível buscar suas contas.')),
                    loaded: (loaded) {
                      if (loaded.linkedMethods.isEmpty) {
                        return const SizedBox();
                      }
                      final activeAccount = _selectedAccount ?? loaded.linkedMethods.defaultPayoutAccount ?? loaded.linkedMethods.first;

                      return Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        decoration: BoxDecoration(
                          color: ColorPalette.neutralVariant95,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: DropdownButtonHideUnderline(
                          child: DropdownButton<PayoutAccountEntity>(
                            value: activeAccount,
                            isExpanded: true,
                            icon: const Icon(Ionicons.chevron_down_outline),
                            borderRadius: BorderRadius.circular(12),
                            onChanged: (account) {
                              setState(() {
                                _selectedAccount = account;
                              });
                            },
                            items: loaded.linkedMethods.map((account) {
                              return DropdownMenuItem<PayoutAccountEntity>(
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
                                            account.accountHolderName ?? 'Chave Pix',
                                            style: context.bodyMedium?.copyWith(fontWeight: FontWeight.bold),
                                          ),
                                          Text(
                                            account.accountNumber ?? '',
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
                      );
                    },
                  );
                },
              ),
              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );
  }
}
