import 'package:flutter/cupertino.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_common/core/presentation/buttons/app_radio_button.dart';
import 'package:flutter_common/core/theme/animation_duration.dart';
import 'package:ionicons/ionicons.dart';
import 'package:flutter_common/core/color_palette/color_palette.dart';
import 'package:rider_flutter/config/locator/locator.dart';
import 'package:rider_flutter/core/extensions/extensions.dart';
import 'package:flutter_common/core/presentation/buttons/app_bordered_button.dart';
import 'package:flutter_common/core/presentation/responsive_dialog/app_responsive_dialog.dart';
import 'package:flutter_common/core/presentation/buttons/app_text_button.dart';
import 'package:flutter_common/core/entities/cancel_reason.dart';
import 'package:rider_flutter/features/home/features/track_order/presentation/blocs/cancel_reason.dart';
import 'package:rider_flutter/features/home/features/track_order/presentation/blocs/track_order.dart';
import 'package:rider_flutter/features/home/presentation/blocs/home.dart';
import 'package:rider_flutter/core/blocs/location.dart';
import 'package:flutter_common/core/presentation/common_skeletons.dart';

class CancelRideReasonDialog extends StatefulWidget {
  const CancelRideReasonDialog({
    super.key,
  });

  @override
  State<CancelRideReasonDialog> createState() => _CancelRideReasonDialogState();
}

class _CancelRideReasonDialogState extends State<CancelRideReasonDialog> {
  CancelReasonEntity? selectedReason;

  @override
  void initState() {
    super.initState();
    locator<CancelReasonCubit>().onStarted();
  }

  @override
  Widget build(BuildContext context) {
    return BlocProvider.value(
      value: locator<CancelReasonCubit>(),
      child: AppResponsiveDialog(
        type: context.responsive(
          DialogType.bottomSheet,
          xl: DialogType.dialog,
        ),
        primaryButton: AppBorderedButton(
          isDisabled: selectedReason == null,
          onPressed: () {
            Navigator.of(context).pop();

            locator<TrackOrderBloc>().cancelRide(
              cancelReasonId: selectedReason!.id,
              cancelReasonNote: null,
            );

            locator.resetLazySingleton<TrackOrderBloc>();
            locator<HomeCubit>().initializeWelcome(
              pickupPoint: locator<LocationCubit>().state.place,
            );
          },
          title: context.translate.confirmAndCancelRide,
          textColor: ColorPalette.error40,
          isPrimary: true,
        ),
        header: (
          Ionicons.close_circle,
          context.translate.rideCancellation,
          null,
        ),
        iconColor: ColorPalette.error40,
        secondaryButton: AppTextButton(
          onPressed: () {
            Navigator.of(context).pop();
          },
          text: context.translate.goBackToRide,
        ),
        child: BlocBuilder<CancelReasonCubit, CancelReasonState>(
          builder: (context, state) {
            return AnimatedSwitcher(
              duration: AnimationDuration.pageStateTransitionMobile,
              child: state.map(
                initial: (_) => const SizedBox.shrink(),
                loading: (_) => const CancelReasonSkeleton(),
                error: (error) => Text(error.message),
                loaded: (loaded) {
                  final trackState = locator<TrackOrderBloc>().state;
                  // Taxa zero temporariamente — sem cobrança de cancelamento
                  final showWarning = false;

                  return Column(
                    children: [
                      if (showWarning) ...[
                        Container(
                          margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: ColorPalette.secondary50.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: ColorPalette.secondary50, width: 1.5),
                          ),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Icon(
                                Ionicons.warning_outline,
                                color: ColorPalette.secondary50,
                                size: 24,
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'Taxa de Cancelamento Aplicável',
                                      style: context.titleMedium?.copyWith(
                                        color: ColorPalette.secondary50,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                    const SizedBox(height: 6),
                                    Text(
                                      'Como o motorista já aceitou ou chegou ao local de embarque, cancelar a corrida agora cobrará uma taxa de R\$ 5,00 que será repassada ao motorista.',
                                      style: context.bodyMedium?.copyWith(
                                        color: ColorPalette.neutral70,
                                        height: 1.3,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                      ...loaded.data
                          .map(
                            (e) => CupertinoButton(
                              padding: const EdgeInsets.symmetric(
                                  vertical: 8, horizontal: 16),
                              child: Row(
                                children: [
                                  Expanded(
                                      child: Text(
                                    e.name,
                                    style: context.labelLarge,
                                  )),
                                  AppRadioButton(
                                    groupValue: selectedReason,
                                    value: e,
                                    onChanged: (value) => setState(
                                      () => selectedReason = e,
                                    ),
                                  ),
                                ],
                              ),
                              onPressed: () => setState(
                                () => selectedReason = e,
                              ),
                            ),
                          )
                          ,
                    ],
                  );
                },
              ),
            );
          },
        ),
      ),
    );
  }
}
