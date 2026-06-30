import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:geolocator/geolocator.dart';
import 'package:flutter_common/core/color_palette/color_palette.dart';
import 'package:rider_flutter/config/locator/locator.dart';
import 'package:rider_flutter/core/blocs/location.dart';
import 'package:flutter_common/core/blocs/settings.dart';
import 'package:rider_flutter/core/extensions/extensions.dart';
import 'package:flutter_common/core/presentation/buttons/app_bordered_button.dart';
import 'package:flutter_common/core/presentation/buttons/app_primary_button.dart';
import 'package:flutter_common/core/presentation/responsive_dialog/app_responsive_dialog.dart';
import 'package:ionicons/ionicons.dart';
import 'package:rider_flutter/features/home/presentation/blocs/home.dart';
import 'package:rider_flutter/core/datasources/location_datasource.dart';

class LocationPermissionRequestDialog extends StatefulWidget {
  const LocationPermissionRequestDialog({super.key});

  @override
  State<LocationPermissionRequestDialog> createState() =>
      _LocationPermissionRequestDialogState();
}

class _LocationPermissionRequestDialogState
    extends State<LocationPermissionRequestDialog> with WidgetsBindingObserver {
  bool _notificationGranted = false;
  bool _locationGranted = false;
  bool _locationPermissionGrantedButGpsDisabled = false;
  bool _isPopped = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _checkCurrentStatuses();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _checkCurrentStatuses();
    }
  }

  void _safePop([dynamic result]) {
    if (!_isPopped && mounted) {
      _isPopped = true;
      Navigator.of(context).pop(result);
    }
  }

  Future<void> _checkCurrentStatuses() async {
    if (kIsWeb) {
      final locGranted = await locator<LocationDatasource>().isLocationPermissionGranted();
      if (mounted) {
        setState(() {
          _notificationGranted = true;
          _locationGranted = locGranted;
          _locationPermissionGrantedButGpsDisabled = false;
        });
        if (locGranted) {
          locator<LocationCubit>().fetchCurrentLocation(
            language: locator<SettingsCubit>().state.locale,
            mapProvider: locator<SettingsCubit>().state.mapProviderEnum,
          );
          WidgetsBinding.instance.addPostFrameCallback((_) {
            _safePop(true);
          });
        }
      }
      return;
    }
    final notif = await Permission.notification.isGranted;
    final loc = await Permission.location.isGranted;
    final serviceEnabled = await locator<LocationDatasource>().isLocationServiceEnabled();
    if (mounted) {
      setState(() {
        _notificationGranted = notif;
        _locationGranted = loc && serviceEnabled;
        _locationPermissionGrantedButGpsDisabled = loc && !serviceEnabled;
      });

      // Se a permissão de localização foi concedida e o GPS está ativo (ex: ao voltar das configurações),
      // inicializa a localização e fecha o diálogo automaticamente.
      if (loc && serviceEnabled) {
        locator<LocationCubit>().fetchCurrentLocation(
          language: locator<SettingsCubit>().state.locale,
          mapProvider: locator<SettingsCubit>().state.mapProviderEnum,
        );
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _safePop(true);
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.basic,
      child: AppResponsiveDialog(
        type: DialogType.dialog,
        iconColor: ColorPalette.primary40,
        header: (
          Ionicons.navigate_circle,
          "Permissões Necessárias",
          "Para uma experiência de viagem impecável, precisamos configurar o acesso à sua localização e notificações push.",
        ),
        primaryButton: AppPrimaryButton(
        onPressed: () async {
          if (kIsWeb) {
            final granted = await locator<LocationDatasource>().isLocationPermissionGranted();
            if (granted) {
              locator<LocationCubit>().fetchCurrentLocation(
                language: locator<SettingsCubit>().state.locale,
                mapProvider: locator<SettingsCubit>().state.mapProviderEnum,
              );
              _safePop(true);
            } else {
              locator<HomeCubit>().initializeWelcome(pickupPoint: null);
              _safePop();
            }
            return;
          }
          // 1. Requisitar permissão de localização (primeiro plano)
          final locStatus = await Permission.location.request();

          // 2. Requisitar permissão de notificações push
          await Permission.notification.request();

          // Verifica se o serviço de localização está ativo
          final serviceEnabled = await locator<LocationDatasource>().isLocationServiceEnabled();

          await _checkCurrentStatuses();

          if ((locStatus.isGranted || locStatus.isLimited) && serviceEnabled) {
            locator<LocationCubit>().fetchCurrentLocation(
              language: locator<SettingsCubit>().state.locale,
              mapProvider: locator<SettingsCubit>().state.mapProviderEnum,
            );
            _safePop(true);
          } else if (locStatus.isPermanentlyDenied) {
            // Se foi negada permanentemente, abre as configurações do sistema
            openAppSettings();
          } else if ((locStatus.isGranted || locStatus.isLimited) && !serviceEnabled) {
            // Se a permissão foi concedida, mas o GPS está desligado, abre as configurações de localização (GPS)
            await Geolocator.openLocationSettings();
          } else {
            // Caso recuse o GPS comum, inicializa a Home vazia para conseguir digitar manualmente
            locator<HomeCubit>().initializeWelcome(pickupPoint: null);
            _safePop();
          }
        },child: const Text("Permitir Acesso"),
      ),
      secondaryButton: AppBorderedButton(
        onPressed: () {
          // Inicializa a Home com pickup nulo, liberando a digitação manual de partida/destino
          locator<HomeCubit>().initializeWelcome(pickupPoint: null);
          _safePop();
        },
        title: "Digitar Manualmente",
      ),
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 16),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: ColorPalette.neutralVariant95,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: ColorPalette.neutralVariant90,
            width: 1,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildPermissionItem(
              icon: Ionicons.location_sharp,
              title: _locationGranted
                  ? "Localização Precisa"
                  : (_locationPermissionGrantedButGpsDisabled
                      ? "GPS Desativado"
                      : "Localização Precisa"),
              description: _locationPermissionGrantedButGpsDisabled
                  ? "A permissão foi concedida, mas o GPS do aparelho está desativado. Ative o GPS para continuar."
                  : "Encontra sua posição no mapa de forma automática e mostra o carro do motorista chegando em tempo real.",
              isGranted: _locationGranted,
              isWarning: _locationPermissionGrantedButGpsDisabled,
            ),
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 12),
              child: Divider(color: ColorPalette.neutralVariant90, height: 1),
            ),
            _buildPermissionItem(
              icon: Ionicons.notifications,
              title: "Notificações de Corrida",
              description: "Receba alertas sonoros importantes quando o motorista aceitar a viagem ou chegar ao seu local.",
              isGranted: _notificationGranted,
            ),
          ],
        ),
      ),
    ),
  );
}

  Widget _buildPermissionItem({
    required IconData icon,
    required String title,
    required String description,
    required bool isGranted,
    bool isWarning = false,
  }) {
    Color iconColor = ColorPalette.neutral50;
    if (isGranted) {
      iconColor = ColorPalette.semanticgreen60;
    } else if (isWarning) {
      iconColor = Colors.orange;
    }
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(
          icon,
          color: iconColor,
          size: 24,
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: context.titleSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                description,
                style: context.bodySmall?.copyWith(
                  color: ColorPalette.neutral40,
                  height: 1.2,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
