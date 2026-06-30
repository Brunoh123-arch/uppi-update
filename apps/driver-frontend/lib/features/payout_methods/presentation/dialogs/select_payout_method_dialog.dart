import 'package:auto_route/auto_route.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:uppi_motorista/config/locator/locator.dart';
import 'package:uppi_motorista/core/extensions/extensions.dart';
import 'package:uppi_motorista/core/router/app_router.dart';
import 'package:uppi_motorista/features/payout_methods/domain/entitites/payout_method.dart';
import 'package:uppi_motorista/features/payout_methods/domain/repositories/payout_methods_repository.dart';
import 'package:uppi_motorista/features/payout_methods/presentation/blocs/payout_methods.dart';
import 'package:flutter_common/core/presentation/common_skeletons.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_common/core/enums/gateway_link_method.dart';
import 'package:flutter_common/core/presentation/buttons/app_primary_button.dart';
import 'package:flutter_common/core/presentation/responsive_dialog/app_responsive_dialog.dart';
import 'package:flutter_common/core/presentation/rounded_checkbox.dart';
import 'package:flutter_common/core/presentation/snackbar/snackbar.dart';
import 'package:flutter_common/core/theme/animation_duration.dart';
import 'package:ionicons/ionicons.dart';
import 'package:url_launcher/url_launcher_string.dart';
import 'package:uppi_motorista/core/error/failure.dart';

class SelectPayoutMethodDialog extends StatefulWidget {
  const SelectPayoutMethodDialog({super.key});

  @override
  State<SelectPayoutMethodDialog> createState() =>
      _SelectPayoutMethodDialogState();
}

class _SelectPayoutMethodDialogState extends State<SelectPayoutMethodDialog> {
  final GlobalKey<FormState> formKey = GlobalKey<FormState>();
  PayoutMethodEntity? selectedPayoutMethod;

  @override
  void initState() {
    locator<PayoutMethodsBloc>().load();
    super.initState();
  }

  @override
  Widget build(BuildContext context) {
    return BlocProvider.value(
      value: locator<PayoutMethodsBloc>(),
      child: AppResponsiveDialog(
        type: context.responsive(DialogType.bottomSheet, xl: DialogType.dialog),
        onBackPressed: () => context.router.maybePop(),
        header: (
          Ionicons.wallet,
          context.translate.addPayoutMethod,
          "Select a payout method to link your account with:",
        ),
        primaryButton: AppPrimaryButton(
          isDisabled: selectedPayoutMethod == null,
          onPressed: () async {
            if (selectedPayoutMethod!.linkMethod == GatewayLinkMethod.manual) {
              Navigator.pop(context);
              context.router.push(
                DriverAddPayoutAccountRoute(
                  payoutMethod: selectedPayoutMethod!,
                ),
              );
              return;
            } else {
              final payoutMethod = await locator<PayoutMethodsRepository>()
                  .getLinkUrlForPayoutMethod(selectedPayoutMethod!);
              payoutMethod.fold(
                (l) => context.showErrorSnackBar(l.errorMessage),
                (r) async {
                  Navigator.pop(context);
                  try {
                    await launchUrlString(r, mode: LaunchMode.externalApplication);
                  } catch (e) {
                    debugPrint('Erro ao redirecionar para método de saque: $e');
                  }
                },
              );
            }
          },
          child: Text(context.translate.payNow),
        ),
        child: Form(
          key: formKey,
          child: BlocBuilder<PayoutMethodsBloc, PayoutMethodsState>(
            builder: (context, state) {
              return AnimatedSwitcher(
                duration: AnimationDuration.pageStateTransitionMobile,
                child: switch (state) {
                  InitialState() => const SizedBox(),
                  ErrorState(:final message) => Center(
                    child: Text(message, style: context.titleSmall),
                  ),
                  LoadingState() => const PayoutMethodDialogSkeleton(),
                  LoadedState(:final payoutMethods) => Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      FormField<PayoutMethodEntity>(
                        builder: (state) {
                          return ListView.separated(
                            padding: EdgeInsets.zero,
                            shrinkWrap: true,
                            itemBuilder: (context, index) {
                              final item = payoutMethods[index];
                              return CupertinoButton(
                                onPressed: () {
                                  state.didChange(item);
                                  setState(() {
                                    selectedPayoutMethod = item;
                                  });
                                },
                                padding: const EdgeInsets.symmetric(
                                  vertical: 0,
                                ),
                                minimumSize: Size(0, 0),
                                child: Row(
                                  children: [
                                    item.media?.address != null
                                        ? CachedNetworkImage(
                                            imageUrl: item.media!.address,
                                            width: 24,
                                            height: 24,
                                          )
                                        : const Icon(Ionicons.business),
                                    const SizedBox(width: 12),
                                    Text(item.name, style: context.labelLarge),
                                    const Spacer(),
                                    RoundedCheckbox(
                                      isSelected: state.value == item,
                                    ),
                                  ],
                                ),
                              );
                            },
                            separatorBuilder: (context, index) {
                              return const Divider(indent: 48);
                            },
                            itemCount: payoutMethods.length,
                          );
                        },
                      ),
                    ],
                  ),
                  EmptyState() => Center(
                    child: Text(
                      context.translate.noPayoutMethods,
                      style: context.titleSmall,
                    ),
                  ),
                  _ => const SizedBox(),
                },
              );
            },
          ),
        ),
      ),
    );
  }
}
