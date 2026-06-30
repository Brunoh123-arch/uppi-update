import 'package:flutter_common/core/enums/measurement_system.dart';
import 'package:generic_map/generic_map.dart';

import '../core/entities/place.dart';
import '../features/country_code_dialog/domain/entities/country_code.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

/// Tipo nomeado para o callback de troca de modo de app.
/// Uso deliberado de [typedef] para melhorar rastreabilidade e eliminar
/// o risco de atribuição acidental de closures incompatíveis.
typedef AppModeCallback = void Function();

class Constants {
  /// Callback injetado pelo rider-frontend para alternar o modo do app de
  /// volta para Passageiro. Definido em `main.dart` durante a inicialização.
  /// Item 62: Acoplamento global intencional e documentado — necessário para
  /// que telas internas do módulo driver (ex: logout) consigam trocar o modo
  /// sem depender de injeção de contexto ou navegação cruzada.
  static AppModeCallback? onSwitchToPassenger;

  static const int resendOtpTime = 90;
  static const bool isDemoMode = false;
  static bool showTimeIn24HourFormat = true;
  static final CountryCode defaultCountry = CountryCode.parseByIso('BR');

  static MapBoxProvider get mapBoxProvider => MapBoxProvider(
    secretKey: dotenv.maybeGet('MAPBOX_TOKEN') ?? '',
    userId: "mapbox",
    tileSetId: "streets-v12",
  );
  static const PlaceEntity defaultLocation = PlaceEntity(
    coordinates: LatLngEntity(lat: -1.296181, lng: -47.925418),
    address: "Castanhal, Pará, Brasil",
  );
  static const List<double> walletPresets = [20, 50, 100];
  static GoogleMapProvider get googleMapProvider => GoogleMapProvider();
  static const MapProviderEnum defaultMapProvider = MapProviderEnum.googleMaps;
  static const MeasurementSystem defaultMeasurementSystem =
      MeasurementSystem.metric;

  // Super App Links globais — domínio comercial definitivo: uppi.app
  static const String supportWhatsAppNumber = "5591987655951";
  static const String supportWhatsAppText =
      "Olá, sou usuário e preciso de suporte com a Uppi.";
  static const String privacyPolicyUrl =
      "https://uppi.app/privacidade";
  static const String termsAndConditionsUrl =
      "https://uppi.app/termos";
  static const String playStoreUrl =
      "https://play.google.com/store/apps/details?id=online.uppi.rider";
  static const String playStoreDriverUrl =
      "https://play.google.com/store/apps/details?id=online.uppi.motorista";
}

