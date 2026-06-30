import 'package:auto_route/auto_route.dart';
import 'package:uppi_motorista/config/locator/locator.dart';
import 'package:uppi_motorista/core/extensions/extensions.dart';
import 'package:uppi_motorista/features/payout_methods/domain/entitites/payout_method.dart';
import 'package:uppi_motorista/features/payout_methods/presentation/blocs/add_bank_transfer_payout_method_form_cubit.dart';
import 'package:uppi_motorista/features/payout_methods/presentation/blocs/payout_accounts.dart';
import 'package:uppi_motorista/features/payout_methods/presentation/components/app_form_field.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_common/core/color_palette/color_palette.dart';
import 'package:flutter_common/core/presentation/buttons/app_primary_button.dart';
import 'package:flutter_common/core/presentation/responsive_dialog/app_top_bar.dart';
import 'package:flutter_common/core/presentation/snackbar/snackbar.dart';

@RoutePage(name: 'DriverAddPayoutAccountRoute')
class AddPayoutAccountScreen extends StatefulWidget {
  final PayoutMethodEntity payoutMethod;

  const AddPayoutAccountScreen({super.key, required this.payoutMethod});

  @override
  State<AddPayoutAccountScreen> createState() => _AddPayoutAccountScreenState();
}

// ─── Reusable Section Header ──────────────────────────────────────────────────
class _SectionHeader extends StatelessWidget {
  final IconData icon;
  final String title;

  const _SectionHeader({required this.icon, required this.title});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 20, color: Theme.of(context).colorScheme.primary),
        const SizedBox(width: 8),
        Text(
          title,
          style: Theme.of(context).textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.w700,
            color: Theme.of(context).colorScheme.primary,
            letterSpacing: 0.3,
          ),
        ),
      ],
    );
  }
}

// ─── Reusable Form Card ───────────────────────────────────────────────────────
class _FormCard extends StatelessWidget {
  final List<Widget> children;

  const _FormCard({required this.children});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: Theme.of(context).colorScheme.outlineVariant.withOpacity(0.3),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.03),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: children,
      ),
    );
  }
}

class _AddPayoutAccountScreenState extends State<AddPayoutAccountScreen> {
  final GlobalKey<FormState> formKey = GlobalKey<FormState>();

  /// Cadastro de chave PIX usa um formulário simplificado.
  bool get isPix => widget.payoutMethod.name.toLowerCase().contains('pix');

  String _pixKeyType = 'CPF/CNPJ';

  @override
  void initState() {
    final cubit = locator<AddBankTransferPayoutMethodFormCubit>();
    cubit.init(payoutMethodId: widget.payoutMethod.id);
    if (isPix) {
      // bankName é obrigatório no input — para PIX gravamos o identificador
      // e o tipo de chave segue no campo routingNumber.
      cubit.onBankNameChanged('PIX');
      cubit.onRoutingNumberChanged(_pixKeyType);
    }
    super.initState();
  }

  Widget _buildPixForm(
    BuildContext context,
    AddBankTransferPayoutMethodFormCubit cubit,
    AddBankTransferPayoutMethodFormState state,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SectionHeader(icon: Icons.pix_rounded, title: 'Chave PIX'),
        const SizedBox(height: 12),
        _FormCard(
          children: [
            Text('Tipo de chave', style: context.labelLarge),
            const SizedBox(height: 8),
            DropdownButtonFormField<String>(
              initialValue: _pixKeyType,
              decoration: InputDecoration(
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 12,
                ),
              ),
              items: const [
                DropdownMenuItem(value: 'CPF/CNPJ', child: Text('CPF/CNPJ')),
                DropdownMenuItem(value: 'Celular', child: Text('Celular')),
                DropdownMenuItem(value: 'E-mail', child: Text('E-mail')),
                DropdownMenuItem(
                  value: 'Aleatória',
                  child: Text('Chave aleatória'),
                ),
              ],
              onChanged: (value) {
                if (value == null) return;
                setState(() => _pixKeyType = value);
                cubit.onRoutingNumberChanged(value);
              },
            ),
            const SizedBox(height: 16),
            AppFormField(
              label: 'Chave PIX',
              hintText: 'Digite sua chave PIX',
              validator: (value) => value?.isEmpty == true
                  ? context.translate.fieldIsRequired
                  : null,
              initialValue: state.accountNumber,
              onChanged: cubit.onAccountNumberChanged,
            ),
            const SizedBox(height: 16),
            AppFormField(
              label: 'Nome do titular',
              hintText: context.translate.nameHint,
              validator: (value) => value?.isEmpty == true
                  ? context.translate.fieldIsRequired
                  : null,
              initialValue: state.accountHolderName,
              onChanged: cubit.onAccountHolderNameChanged,
            ),
          ],
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final cubit = locator<AddBankTransferPayoutMethodFormCubit>();
    return BlocProvider.value(
      value: locator<AddBankTransferPayoutMethodFormCubit>(),
      child: Container(
        color: ColorPalette.neutralVariant99,
        padding: context.responsive(
          const EdgeInsets.all(16).copyWith(bottom: 0),
          xl: const EdgeInsets.all(16).copyWith(top: 96, bottom: 0),
        ),
        child: SafeArea(
          child:
              BlocConsumer<
                AddBankTransferPayoutMethodFormCubit,
                AddBankTransferPayoutMethodFormState
              >(
                listener: (context, state) {
                  state.pageState.mapOrNull(
                    success: (value) {
                      context.router.maybePop();
                      locator<AddBankTransferPayoutMethodFormCubit>().reset();
                      locator<PayoutAccountsBloc>().load();
                    },
                    error: (value) =>
                        context.showErrorSnackBar(value.message, fallback: 'Não foi possível salvar a conta de repasse.'),
                  );
                },
                builder: (context, state) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      AppTopBar(title: context.translate.addPayoutMethod),
                      const SizedBox(height: 16),
                      Expanded(
                        child: SingleChildScrollView(
                          child: Form(
                            key: formKey,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                // ── Info Badge ──
                                Container(
                                  width: double.infinity,
                                  margin: const EdgeInsets.only(bottom: 24),
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 16,
                                    vertical: 12,
                                  ),
                                  decoration: BoxDecoration(
                                    color: Colors.green.withOpacity(0.08),
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(
                                      color: Colors.green.withOpacity(0.2),
                                    ),
                                  ),
                                  child: Row(
                                    children: [
                                      Icon(
                                        Icons.pix_rounded,
                                        size: 20,
                                        color: Colors.green[700],
                                      ),
                                      const SizedBox(width: 10),
                                      Expanded(
                                        child: Text(
                                          'Os pagamentos são realizados via PIX pelo Mercado Pago.',
                                          style: context.bodySmall?.copyWith(
                                            color: Colors.green[800],
                                            fontWeight: FontWeight.w500,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),

                                if (isPix)
                                  _buildPixForm(context, cubit, state)
                                else ...[
                                // ── Dados Bancários ──
                                _SectionHeader(
                                  icon: Icons.account_balance_outlined,
                                  title: 'Dados Bancários',
                                ),
                                const SizedBox(height: 12),
                                _FormCard(
                                  children: [
                                    AppFormField(
                                      label: context.translate.bankName,
                                      validator: (value) =>
                                          value?.isEmpty == true
                                          ? context.translate.fieldIsRequired
                                          : null,
                                      hintText: context.translate.bankNameHint,
                                      initialValue: state.bankName,
                                      onChanged: cubit.onBankNameChanged,
                                    ),
                                    const SizedBox(height: 16),
                                    AppFormField(
                                      label: context.translate.branchName,
                                      hintText:
                                          context.translate.branchNameHint,
                                      initialValue: state.branchName,
                                      onChanged: cubit.onBranchNameChanged,
                                    ),
                                    const SizedBox(height: 16),
                                    AppFormField(
                                      label: context.translate.routingNumber,
                                      hintText:
                                          context.translate.routingNumberHint,
                                      initialValue: state.routingNumber,
                                      onChanged: cubit.onRoutingNumberChanged,
                                    ),
                                    const SizedBox(height: 16),
                                    AppFormField(
                                      label: context.translate.accountNumber,
                                      validator: (value) =>
                                          value?.isEmpty == true
                                          ? context.translate.fieldIsRequired
                                          : null,
                                      hintText:
                                          context.translate.accountNumberHint,
                                      initialValue: state.accountNumber,
                                      onChanged: cubit.onAccountNumberChanged,
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 24),

                                // ── Dados Pessoais ──
                                _SectionHeader(
                                  icon: Icons.person_outline,
                                  title: 'Dados do Titular',
                                ),
                                const SizedBox(height: 12),
                                _FormCard(
                                  children: [
                                    AppFormField(
                                      label:
                                          context.translate.accountHolderName,
                                      hintText: context.translate.nameHint,
                                      validator: (value) =>
                                          value?.isEmpty == true
                                          ? context.translate.fieldIsRequired
                                          : null,
                                      initialValue: state.accountHolderName,
                                      onChanged:
                                          cubit.onAccountHolderNameChanged,
                                    ),
                                    const SizedBox(height: 16),
                                    Text(
                                      context.translate.dateOfBith,
                                      style: context.labelLarge,
                                    ),
                                    const SizedBox(height: 8),
                                    Row(
                                      children: [
                                        Expanded(
                                          child: AppFormField(
                                            hintText: context.translate.dayHint,
                                            validator: (value) {
                                              if (value?.isEmpty == true) {
                                                return context
                                                    .translate
                                                    .fieldIsRequired;
                                              }
                                              if (int.tryParse(value ?? "0") ==
                                                  null) {
                                                return "invalid value";
                                              }
                                              if (int.tryParse(value ?? "0")! >
                                                  31) {
                                                return "invalid value";
                                              }
                                              return null;
                                            },
                                            initialValue: state
                                                .accountHolderDateOfBirth
                                                ?.day
                                                .toString(),
                                            keyboardType: TextInputType.number,
                                            inputFormatters: [
                                              FilteringTextInputFormatter
                                                  .digitsOnly,
                                            ],
                                            onChanged: (value) {
                                              cubit.onAccountHolderDateOfBirthChanged(
                                                DateTime(
                                                  int.tryParse(value ?? "0") ??
                                                      0,
                                                  state
                                                          .accountHolderDateOfBirth
                                                          ?.month ??
                                                      0,
                                                  state
                                                          .accountHolderDateOfBirth
                                                          ?.year ??
                                                      0,
                                                ),
                                              );
                                            },
                                          ),
                                        ),
                                        const SizedBox(width: 16),
                                        Expanded(
                                          child: AppFormField(
                                            hintText:
                                                context.translate.monthHint,
                                            validator: (value) {
                                              if (value?.isEmpty == true) {
                                                return context
                                                    .translate
                                                    .fieldIsRequired;
                                              }
                                              if (int.tryParse(value ?? "0") ==
                                                  null) {
                                                return "invalid value";
                                              }
                                              if (int.tryParse(value ?? "0")! >
                                                  12) {
                                                return "invalid value";
                                              }
                                              return null;
                                            },
                                            keyboardType: TextInputType.number,
                                            inputFormatters: [
                                              FilteringTextInputFormatter
                                                  .digitsOnly,
                                            ],
                                            initialValue: state
                                                .accountHolderDateOfBirth
                                                ?.month
                                                .toString(),
                                            onChanged: (value) {
                                              cubit.onAccountHolderDateOfBirthChanged(
                                                DateTime(
                                                  state
                                                          .accountHolderDateOfBirth
                                                          ?.day ??
                                                      0,
                                                  int.tryParse(value ?? "0") ??
                                                      0,
                                                  state
                                                          .accountHolderDateOfBirth
                                                          ?.year ??
                                                      0,
                                                ),
                                              );
                                            },
                                          ),
                                        ),
                                        const SizedBox(width: 16),
                                        Expanded(
                                          child: AppFormField(
                                            hintText:
                                                context.translate.yearHint,
                                            validator: (value) {
                                              if (value?.isEmpty == true) {
                                                return context
                                                    .translate
                                                    .fieldIsRequired;
                                              }
                                              if (int.tryParse(value ?? "0") ==
                                                  null) {
                                                return "invalid value";
                                              }
                                              if (int.tryParse(value ?? "0")! >
                                                  4000) {
                                                return "invalid value";
                                              }
                                              return null;
                                            },
                                            initialValue: state
                                                .accountHolderDateOfBirth
                                                ?.year
                                                .toString(),
                                            keyboardType: TextInputType.number,
                                            inputFormatters: [
                                              FilteringTextInputFormatter.allow(
                                                RegExp(r'[0-9]'),
                                              ),
                                            ],
                                            onChanged: (value) {
                                              cubit.onAccountHolderDateOfBirthChanged(
                                                DateTime(
                                                  state
                                                          .accountHolderDateOfBirth
                                                          ?.day ??
                                                      0,
                                                  state
                                                          .accountHolderDateOfBirth
                                                          ?.month ??
                                                      0,
                                                  int.tryParse(value ?? "0") ??
                                                      0,
                                                ),
                                              );
                                            },
                                          ),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 24),

                                // ── Endereço ──
                                _SectionHeader(
                                  icon: Icons.location_on_outlined,
                                  title: 'Endereço',
                                ),
                                const SizedBox(height: 12),
                                _FormCard(
                                  children: [
                                    AppFormField(
                                      label: context.translate.zipCode,
                                      hintText: context.translate.zipCodeHint,
                                      initialValue: state.accountHolderZip,
                                      onChanged:
                                          cubit.onAccountHolderZipCodeChanged,
                                    ),
                                    const SizedBox(height: 16),
                                    AppFormField(
                                      label: context.translate.state,
                                      hintText: context.translate.stateHint,
                                      initialValue: state.accountHolderState,
                                      onChanged:
                                          cubit.onAccountHolderStateChanged,
                                    ),
                                    const SizedBox(height: 16),
                                    AppFormField(
                                      label: context.translate.city,
                                      hintText: context.translate.cityHint,
                                      initialValue: state.accountHolderCity,
                                      onChanged:
                                          cubit.onAccountHolderCityChanged,
                                    ),
                                    const SizedBox(height: 16),
                                    AppFormField(
                                      label: context.translate.address,
                                      hintText: context.translate.addressHint,
                                      initialValue: state.accountHolderAddress,
                                      onChanged:
                                          cubit.onAccountHolderAddressChanged,
                                    ),
                                  ],
                                ),
                                ],
                              ],
                            ),
                          ),
                        ),
                      ),
                      Align(
                        alignment: Alignment.centerRight,
                        child: Container(
                          width: context.responsive(double.infinity, xl: null),
                          padding: const EdgeInsets.only(bottom: 16),
                          child: AppPrimaryButton(
                            onPressed: () {
                              if (formKey.currentState?.validate() == true) {
                                formKey.currentState?.save();

                                cubit.submit(input: state.toInput);
                              }
                            },
                            child: Text(context.translate.saveChanges),
                          ),
                        ),
                      ),
                    ],
                  );
                },
              ),
        ),
      ),
    );
  }
}
