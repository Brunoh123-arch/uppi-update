import 'dart:convert';
import 'dart:math';
import 'package:http/http.dart' as http;
import 'package:dartz/dartz.dart';
import 'package:flutter_common/core/entities/place.dart';
import 'package:generic_map/generic_map.dart';
import 'package:injectable/injectable.dart';
import 'package:latlong2/latlong.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

import '../error/failure.dart';
import 'geo_datasource.dart';
import 'firebase_datasource.dart';
import 'location_datasource.dart';

/// Geocoding gratuito via OpenStreetMap Nominatim
/// Sem custo e ajustado para não ser tão vago (tenta capturar números)
@prod
@LazySingleton(as: GeoDatasource)
class GeoDatasourceImpl implements GeoDatasource {
  static final ValueNotifier<String> searchProviderNotifier = ValueNotifier<String>("Nenhuma");
  static final ValueNotifier<String> reverseProviderNotifier = ValueNotifier<String>("Nenhuma");

  final LocationDatasource locationDatasource;
  final FirebaseDatasource firebaseDatasource;

  // Persistent HTTP client for Keep-Alive (avoids TCP/SSL handshake latency on every request)
  final http.Client _httpClient = http.Client();

  @visibleForTesting
  http.Client? mockClient;

  // In-memory reverse-geocoding cache to resolve addresses instantaneously when dragging back and forth
  final Map<String, PlaceEntity> _geocodeCache = {};
  final List<String> _cacheKeys = [];

  double _distanceInMeters(double lat1, double lon1, double lat2, double lon2) {
    final p = 0.017453292519943295; // double.pi / 180
    final a = 0.5 -
        cos((lat2 - lat1) * p) / 2 +
        cos(lat1 * p) * cos(lat2 * p) * (1 - cos((lon2 - lon1) * p)) / 2;
    return 12742000 * asin(sqrt(a));
  }

  PlaceEntity? _findInCache(LatLng latLng) {
    const double maxDistanceMeters = 15.0;
    for (final entry in _geocodeCache.values) {
      final double distance = _distanceInMeters(
        latLng.latitude,
        latLng.longitude,
        entry.coordinates.lat,
        entry.coordinates.lng,
      );
      if (distance <= maxDistanceMeters) {
        // Return a copy with exact requested coordinates so the pin snaps correctly
        return PlaceEntity(
          coordinates: LatLngEntity(lat: latLng.latitude, lng: latLng.longitude),
          address: entry.address,
          title: entry.title,
        );
      }
    }
    return null;
  }

  void _addToCache(LatLng latLng, PlaceEntity place) {
    final key = '${latLng.latitude},${latLng.longitude}';
    if (_geocodeCache.containsKey(key)) {
      _cacheKeys.remove(key);
    }
    _geocodeCache[key] = place;
    _cacheKeys.add(key);
    if (_cacheKeys.length > 100) {
      final oldKey = _cacheKeys.removeAt(0);
      _geocodeCache.remove(oldKey);
    }
  }

  static const _nominatimBase = 'https://nominatim.openstreetmap.org';
  static const _userAgent = 'UppiTaxiApp/3.3.0';

  // Centro do Pará (entre Castanhal e Bragança) — foco padrão
  static const _defaultLat = -1.20;
  static const _defaultLng = -47.30;

  // Viewbox amplo: cobre de Belém até Bragança e região (~300km)
  // Oeste: Belém/Barcarena | Leste: Bragança/Viseu | Norte: litoral | Sul: interior
  static const _viewboxWest = -48.60;
  static const _viewboxEast = -46.00;
  static const _viewboxNorth = -0.50;
  static const _viewboxSouth = -2.20;

  String? _cachedGoogleApiKey;

  Future<String?> _getGoogleApiKey() async {
    if (_cachedGoogleApiKey != null && _cachedGoogleApiKey!.isNotEmpty) {
      return _cachedGoogleApiKey;
    }
    
    // Tenta ler do dotenv primeiro
    final envKey = dotenv.maybeGet('GOOGLE_MAP_API_KEY');
    if (envKey != null && envKey.isNotEmpty && !envKey.contains('AIzaSy_SUA_CHAVE_AQUI')) {
      _cachedGoogleApiKey = envKey;
      return envKey;
    }
    
    // Tenta carregar do Supabase app_settings
    try {
      final settingsRows = await firebaseDatasource.supabaseClient
          .from('app_settings')
          .select();
      
      final Map<String, String> settings = {};
      for (final row in settingsRows) {
        final key = row['key']?.toString() ?? '';
        final value = row['value']?.toString() ?? '';
        if (key.isNotEmpty) settings[key] = value;
      }

      Map<String, dynamic>? globalConfigRow;
      for (final row in settingsRows) {
        if (row['key'] == 'global_config') {
          globalConfigRow = Map<String, dynamic>.from(row);
          break;
        }
      }
      
      String? keyFromDb;
      if (globalConfigRow != null) {
        keyFromDb = globalConfigRow['google_map_api_key']?.toString();
      }
      keyFromDb ??= settings['google_map_api_key'];
      
      if (keyFromDb != null && keyFromDb.isNotEmpty) {
        _cachedGoogleApiKey = keyFromDb;
        try {
          dotenv.env['GOOGLE_MAP_API_KEY'] = keyFromDb;
        } catch (_) {}
        return keyFromDb;
      }
    } catch (e) {
      debugPrint('[GeoDatasource] Error loading API Key from Supabase: $e');
    }
    
    return null;
  }

  GeoDatasourceImpl(this.firebaseDatasource, this.locationDatasource);

  /// Reverse geocoding: coordenadas -> endereço
  @override
  Future<Either<Failure, PlaceEntity>> getAddressForLocation({
    required LatLng latLng,
    required String language,
    required MapProviderEnum mapProvider,
  }) async {
    final cached = _findInCache(latLng);
    if (cached != null) {
      reverseProviderNotifier.value = "Cache Google";
      return Right(cached);
    }

    final apiKey = await _getGoogleApiKey();
    final hasGoogleKey = apiKey != null && apiKey.isNotEmpty;
    final shouldTryGoogle = mapProvider == MapProviderEnum.googleMaps || hasGoogleKey;

    if (shouldTryGoogle && hasGoogleKey) {
      try {
        final googleUri = Uri.parse(
          'https://maps.googleapis.com/maps/api/geocode/json'
          '?latlng=${latLng.latitude},${latLng.longitude}'
          '&key=$apiKey'
          '&language=${language.isNotEmpty ? language : "pt-BR"}'
        );
        final googleResponse = await _httpGet(googleUri);
        if (googleResponse != null && googleResponse['status'] == 'OK') {
          final results = googleResponse['results'] as List?;
          if (results != null && results.isNotEmpty) {
            Map<String, dynamic>? bestResult;
            double minDistance = double.infinity;

            // Primeira passagem: encontra o resultado mais próximo que possui número de rua (street_number)
            for (final r in results) {
              final components = r['address_components'] as List?;
              if (components != null) {
                final hasStreetNumber = components.any(
                  (c) => (c['types'] as List).contains('street_number')
                );
                if (hasStreetNumber) {
                  final geometry = r['geometry'] as Map<String, dynamic>?;
                  final location = geometry?['location'] as Map<String, dynamic>?;
                  if (location != null) {
                    final lat = (location['lat'] as num?)?.toDouble();
                    final lng = (location['lng'] as num?)?.toDouble();
                    if (lat != null && lng != null) {
                      final distance = _distanceInMeters(
                        latLng.latitude,
                        latLng.longitude,
                        lat,
                        lng,
                      );
                      if (distance < minDistance) {
                        minDistance = distance;
                        bestResult = r as Map<String, dynamic>;
                      }
                    }
                  }
                }
              }
            }

            // Segunda passagem: se nenhum resultado tiver número de rua, seleciona o resultado mais próximo no geral
            if (bestResult == null) {
              minDistance = double.infinity;
              for (final r in results) {
                final geometry = r['geometry'] as Map<String, dynamic>?;
                final location = geometry?['location'] as Map<String, dynamic>?;
                if (location != null) {
                  final lat = (location['lat'] as num?)?.toDouble();
                  final lng = (location['lng'] as num?)?.toDouble();
                  if (lat != null && lng != null) {
                    final distance = _distanceInMeters(
                      latLng.latitude,
                      latLng.longitude,
                      lat,
                      lng,
                    );
                    if (distance < minDistance) {
                      minDistance = distance;
                      bestResult = r as Map<String, dynamic>;
                    }
                  }
                }
              }
            }

            final selectedResult = bestResult ?? (results.first as Map<String, dynamic>);
            final rawAddress = selectedResult['formatted_address'] as String? ?? '';
            
            var formattedAddress = rawAddress.replaceAll(RegExp(r',\s*Brasi?l\s*$', caseSensitive: false), '');
            formattedAddress = formattedAddress.replaceAll(RegExp(r',\s*\d{5}-\d{3}'), '');
            formattedAddress = formattedAddress.replaceAll(RegExp(r'\s*\d{5}-\d{3}'), '');
            formattedAddress = formattedAddress.trim();
            
            String? title;
            final addressComponents = selectedResult['address_components'] as List?;
            if (addressComponents != null && addressComponents.isNotEmpty) {
              final routeComponent = addressComponents.firstWhere(
                (c) => (c['types'] as List).contains('route'),
                orElse: () => null,
              );
              final streetNumberComponent = addressComponents.firstWhere(
                (c) => (c['types'] as List).contains('street_number'),
                orElse: () => null,
              );

              if (routeComponent != null) {
                final route = routeComponent['long_name'] as String? ?? '';
                final streetNumber = streetNumberComponent != null 
                    ? streetNumberComponent['long_name'] as String? ?? '' 
                    : '';
                if (streetNumber.isNotEmpty) {
                  title = '$route, $streetNumber';
                } else {
                  title = route;
                }
              }
            }

            final resolvedPlace = PlaceEntity(
              coordinates: LatLngEntity(lat: latLng.latitude, lng: latLng.longitude),
              address: formattedAddress,
              title: title,
            );
            _addToCache(latLng, resolvedPlace);
            reverseProviderNotifier.value = "Google Maps";
            return Right(resolvedPlace);
          }
        }
      } catch (e) {
        debugPrint('[Google-Geocode] Error: $e');
      }
    }

    // Se o provedor é Google Maps, NÃO faz fallback para Nominatim.
    // Retorna diretamente as coordenadas brutas.
    if (mapProvider == MapProviderEnum.googleMaps) {
      debugPrint('[GeoDatasource] Google Maps selecionado — ignorando fallback Nominatim para reverse geocoding');
      reverseProviderNotifier.value = "Fallback LatLng (Google)";
      return Right(PlaceEntity(
        coordinates: LatLngEntity(lat: latLng.latitude, lng: latLng.longitude),
        address: '${latLng.latitude.toStringAsFixed(5)}, ${latLng.longitude.toStringAsFixed(5)}',
        title: 'Local no mapa',
      ));
    }

    try {
      final uri = Uri.parse(
        '$_nominatimBase/reverse'
        '?format=jsonv2'
        '&lat=${latLng.latitude}'
        '&lon=${latLng.longitude}'
        '&accept-language=${language.isNotEmpty ? language : "pt-BR"}'
        '&addressdetails=1',
      );

      final response = await _httpGet(uri);
      if (response == null) {
        return Right(PlaceEntity(
          coordinates:
              LatLngEntity(lat: latLng.latitude, lng: latLng.longitude),
          address:
              '${latLng.latitude.toStringAsFixed(5)}, ${latLng.longitude.toStringAsFixed(5)}',
        ));
      }

      final displayName = response['display_name'] as String? ?? '';
      final address = response['address'] as Map<String, dynamic>? ?? {};

      final road = address['road'] as String? ?? '';
      final houseNumber = address['house_number'] as String? ?? '';
      final suburb = address['suburb'] as String? ??
          address['neighbourhood'] as String? ??
          '';
      final city = address['city'] as String? ??
          address['town'] as String? ??
          address['village'] as String? ??
          '';

      final formattedAddress = _formatAddress(road, houseNumber, suburb, city);

      final resolvedPlace = PlaceEntity(
        coordinates: LatLngEntity(lat: latLng.latitude, lng: latLng.longitude),
        address: formattedAddress.isNotEmpty ? formattedAddress : displayName,
      );
      _addToCache(latLng, resolvedPlace);
      reverseProviderNotifier.value = "Nominatim (OSM)";
      return Right(resolvedPlace);
    } catch (e) {
      debugPrint('[GeoDatasource] Reverse geocoding exception, returning fallback coordinates: $e');
      reverseProviderNotifier.value = "Fallback LatLng";
      return Right(PlaceEntity(
        coordinates: LatLngEntity(lat: latLng.latitude, lng: latLng.longitude),
        address: '${latLng.latitude.toStringAsFixed(5)}, ${latLng.longitude.toStringAsFixed(5)}',
        title: 'Local no mapa',
      ));
    }
  }

  @override
  Future<Either<Failure, List<PlaceEntity>>> getAddressCandidatesForLocation({
    required LatLng latLng,
    required String language,
    required MapProviderEnum mapProvider,
  }) async {
    final apiKey = await _getGoogleApiKey();
    final hasGoogleKey = apiKey != null && apiKey.isNotEmpty;
    final shouldTryGoogle = mapProvider == MapProviderEnum.googleMaps || hasGoogleKey;

    if (shouldTryGoogle && hasGoogleKey) {
      try {
        final googleUri = Uri.parse(
          'https://maps.googleapis.com/maps/api/geocode/json'
          '?latlng=${latLng.latitude},${latLng.longitude}'
          '&key=$apiKey'
          '&language=${language.isNotEmpty ? language : "pt-BR"}'
        );
        final googleResponse = await _httpGet(googleUri);
        if (googleResponse != null && googleResponse['status'] == 'OK') {
          final results = googleResponse['results'] as List?;
          if (results != null && results.isNotEmpty) {
            final candidates = <PlaceEntity>[];
            final seenAddresses = <String>{};

            for (final r in results) {
              final rawAddress = r['formatted_address'] as String? ?? '';
              if (rawAddress.isEmpty) continue;

              var formattedAddress = rawAddress.replaceAll(RegExp(r',\s*Brasi?l\s*$', caseSensitive: false), '');
              formattedAddress = formattedAddress.replaceAll(RegExp(r',\s*\d{5}-\d{3}'), '');
              formattedAddress = formattedAddress.replaceAll(RegExp(r'\s*\d{5}-\d{3}'), '');
              formattedAddress = formattedAddress.trim();

              if (seenAddresses.contains(formattedAddress)) continue;
              seenAddresses.add(formattedAddress);

              final types = ((r['types'] as List?) ?? const []).map((t) => t.toString()).toSet();
              const preciseTypes = {
                'street_address', 'premise', 'subpremise', 'route', 'intersection', 'establishment', 'point_of_interest'
              };
              if (!types.any(preciseTypes.contains)) continue;

              String? title;
              final addressComponents = r['address_components'] as List?;
              if (addressComponents != null && addressComponents.isNotEmpty) {
                final routeComponent = addressComponents.firstWhere(
                  (c) => (c['types'] as List).contains('route'),
                  orElse: () => null,
                );
                final streetNumberComponent = addressComponents.firstWhere(
                  (c) => (c['types'] as List).contains('street_number'),
                  orElse: () => null,
                );

                if (routeComponent != null) {
                  final route = routeComponent['long_name'] as String? ?? '';
                  final streetNumberStr = streetNumberComponent != null 
                      ? streetNumberComponent['long_name'] as String? ?? '' 
                      : '';
                  if (streetNumberStr.isNotEmpty) {
                    title = '$route, $streetNumberStr';
                  } else {
                    title = route;
                  }
                }
              }

              candidates.add(PlaceEntity(
                coordinates: LatLngEntity(
                  lat: (r['geometry']?['location']?['lat'] as num?)?.toDouble() ?? latLng.latitude,
                  lng: (r['geometry']?['location']?['lng'] as num?)?.toDouble() ?? latLng.longitude,
                ),
                address: formattedAddress,
                title: title,
              ));

              if (candidates.length >= 5) break;
            }

            if (candidates.isNotEmpty) {
              return Right(candidates);
            }
          }
        }
      } catch (e) {
        debugPrint('[Google-GeocodeCandidates] Error: $e');
      }
    }

    final singleResult = await getAddressForLocation(
      latLng: latLng,
      language: language,
      mapProvider: mapProvider,
    );
    return singleResult.fold(
      (l) => Left(l),
      (r) => Right([r]),
    );
  }

  @override
  Future<Either<Failure, PlaceEntity>> getCurrentLocation({
    required String language,
    required MapProviderEnum mapProvider,
  }) async {
    final currentPosition = await locationDatasource.getCurrentLocation();
    return getAddressForLocation(
      latLng: currentPosition,
      language: language,
      mapProvider: mapProvider,
    );
  }

  /// Forward geocoding: texto -> lista de locais
  @override
  Future<Either<Failure, List<PlaceEntity>>> getNearbyPlaces({
    required String query,
    required LatLng? latLng,
    required int radius,
    required String language,
    required MapProviderEnum mapProvider,
  }) async {
    try {
      if (query.trim().isEmpty) return const Right([]);

      final lang = language.isNotEmpty ? language : 'pt-BR';
      final apiKey = await _getGoogleApiKey();
      final hasGoogleKey = apiKey != null && apiKey.isNotEmpty;
      final shouldTryGoogle = mapProvider == MapProviderEnum.googleMaps || hasGoogleKey;

      if (shouldTryGoogle && hasGoogleKey) {
        try {
          final queryLower = query.toLowerCase();
          final temUF = queryLower.contains('pará') || queryLower.contains('para') || queryLower.contains(', pa');
          final searchQuery = temUF ? query : '$query, Pará';

          // Busca em paralelo: Text Search (estabelecimentos/POIs) e
          // Geocoding (endereços residenciais com precisão de rua)
          final searchResults = await Future.wait([
            _googleTextSearch(searchQuery, apiKey, lang, latLng, radius),
            _googleGeocodeSearch(searchQuery, apiKey, lang, latLng),
          ]);
          final poiPlaces = searchResults[0];
          final geoPlaces = searchResults[1];

          final merged = _mergeSearchResults(
            query: query,
            geocodePlaces: geoPlaces,
            poiPlaces: poiPlaces,
          );
          debugPrint(
              '[Busca] GOOGLE: ${geoPlaces.length} endereços precisos + ${poiPlaces.length} POIs para "$query"');
          if (merged.isNotEmpty) {
            searchProviderNotifier.value = "Google Maps";
            return Right(merged);
          }
        } catch (e) {
          debugPrint('[Google-Places] Error: $e');
        }
      } else {
        debugPrint(
            '[Busca] SEM CHAVE GOOGLE (hasGoogleKey=$hasGoogleKey) — caindo para OpenStreetMap/Nominatim');
      }

      // Se o provedor é Google Maps, NÃO faz fallback para Nominatim.
      // Retorna lista vazia em vez de buscar no OpenStreetMap.
      if (mapProvider == MapProviderEnum.googleMaps) {
        debugPrint('[GeoDatasource] Google Maps selecionado — ignorando fallback Nominatim para busca de "$query"');
        searchProviderNotifier.value = "Google Maps (sem resultados)";
        return const Right([]);
      }

      final queryLower = query.toLowerCase();
      final cidadesPA = [
        'castanhal',
        'belém',
        'belem',
        'ananindeua',
        'marituba',
        'santa izabel',
        'santa isabel',
        'bragança',
        'braganca',
        'capanema',
        'salinópolis',
        'salinopolis',
        'salinas',
        'vigia',
        'igarapé-açu',
        'igarape-acu',
        'igarapé açu',
        'santa maria',
        'são francisco',
        'sao francisco',
        'maracanã',
        'maracana',
        'terra alta',
        'são caetano',
        'bonito',
        'primavera',
        'peixe-boi',
        'nova timboteua',
        'santa luzia',
        'tracuateua',
        'augusto corrêa',
        'viseu',
        'barcarena',
        'abaetetuba',
        'moju',
        'tomé-açu',
        'paragominas',
        'ipixuna',
        'aurora',
        'benevides',
        'inhangapi',
        'santo antônio',
        'bujaru',
        'concórdia',
        'irituia',
        'mãe do rio',
        'mae do rio',
        'ourem',
        'ourém',
        'pará',
        'para',
      ];
      final temCidade = cidadesPA.any((c) => queryLower.contains(c));
      // Remove termos de unidade (apto, bloco...) que o Nominatim não entende
      final sanitizedQuery = _sanitizeAddressQuery(query);
      final baseQuery = sanitizedQuery.isNotEmpty ? sanitizedQuery : query;
      final searchQuery = temCidade ? baseQuery : '$baseQuery, Pará';

      var url = '$_nominatimBase/search'
          '?format=jsonv2'
          '&q=${Uri.encodeComponent(searchQuery)}'
          '&limit=7'
          '&accept-language=$lang'
          '&addressdetails=1'
          '&countrycodes=br';

      final vbLat = latLng?.latitude ?? _defaultLat;
      final vbLng = latLng?.longitude ?? _defaultLng;

      url += '&viewbox='
          '${(vbLng - 1.5).clamp(_viewboxWest, _viewboxEast)},'
          '${(vbLat + 1.0).clamp(_viewboxSouth, _viewboxNorth)},'
          '${(vbLng + 1.5).clamp(_viewboxWest, _viewboxEast)},'
          '${(vbLat - 1.0).clamp(_viewboxSouth, _viewboxNorth)}'
          '&bounded=0';

      debugPrint('[Busca] OPENSTREETMAP/Nominatim usado para "$query"');
      final uri = Uri.parse(url);
      final responseBody = await _httpGetRaw(uri);
      if (responseBody == null) {
        searchProviderNotifier.value = "OSM (Sem resposta)";
        return const Right([]);
      }

      final List<dynamic> results = json.decode(responseBody);

      final places = results.map((item) {
        final lat = double.tryParse(item['lat']?.toString() ?? '0') ?? 0;
        final lng = double.tryParse(item['lon']?.toString() ?? '0') ?? 0;
        final displayName = item['display_name'] as String? ?? '';
        final address = item['address'] as Map<String, dynamic>? ?? {};

        final road = address['road'] as String? ?? '';
        String houseNumber = address['house_number'] as String? ?? '';

        if (houseNumber.isEmpty) {
          final numberMatch = RegExp(r'\b\d+\b').firstMatch(query);
          if (numberMatch != null) {
            houseNumber = numberMatch.group(0)!;
          }
        }

        final suburb = address['suburb'] as String? ??
            address['neighbourhood'] as String? ??
            '';
        final city = address['city'] as String? ??
            address['town'] as String? ??
            address['village'] as String? ??
            '';

        String name = item['name'] as String? ?? '';
        final formattedAddress =
            _formatAddress(road, houseNumber, suburb, city);

        if (houseNumber.isNotEmpty &&
            name.isNotEmpty &&
            !name.contains(houseNumber)) {
          name = '$name, $houseNumber';
        }

        return PlaceEntity(
          coordinates: LatLngEntity(lat: lat, lng: lng),
          title: name.isNotEmpty ? name : null,
          address: formattedAddress.isNotEmpty ? formattedAddress : displayName,
        );
      }).toList();

      searchProviderNotifier.value = "Nominatim (OSM)";
      return Right(places);
    } catch (e) {
      return Left(Failure.serverError(e.toString()));
    }
  }

  // ──── Helpers ────

  /// Remove termos de unidade (apartamento, bloco, casa, lote, fundos...)
  /// que confundem os geocoders e fazem o alfinete cair longe do endereço real
  String _sanitizeAddressQuery(String query) {
    var s = query;
    s = s.replaceAll(
        RegExp(r'\b(apartamento|apart\.?|apto\.?|apt\.?|ap\.?)\s*:?\s*\d+\w*',
            caseSensitive: false),
        '');
    s = s.replaceAll(
        RegExp(r'\b(bloco|bl\.?)\s*:?\s*\w+', caseSensitive: false), '');
    s = s.replaceAll(
        RegExp(r'\b(casa|cs\.?)\s*:?\s*\d+\w*', caseSensitive: false), '');
    s = s.replaceAll(
        RegExp(r'\b(lote|lt\.?)\s*:?\s*\d+\w*', caseSensitive: false), '');
    s = s.replaceAll(
        RegExp(r'\b(fundos|altos|sobrado|andar\s*\d*)\b', caseSensitive: false),
        '');
    // Limpa separadores que sobraram ("- ,", ", -", duplicados)
    s = s.replaceAll(RegExp(r'\s*[-,]\s*(?=[-,])'), '');
    s = s.replaceAll(RegExp(r'\s{2,}'), ' ');
    s = s.replaceAll(RegExp(r'^[\s,\-]+|[\s,\-]+$'), '');
    return s.trim();
  }

  /// Detecta se a busca parece um endereço (rua, travessa, número...)
  /// em vez de um nome de estabelecimento
  bool _looksLikeAddress(String query) {
    final hasStreetWord = RegExp(
      r'\b(r\.|rua|av\.?|avenida|tv\.?|travessa|trav\.?|al\.?|alameda|'
      r'rod\.?|rodovia|estrada|passagem|psg\.?|pass\.?|conjunto|conj\.?|'
      r'quadra|qd\.?|vila|residencial|res\.?|loteamento)\b',
      caseSensitive: false,
    ).hasMatch(query);
    return hasStreetWord || RegExp(r'\d').hasMatch(query);
  }

  String _cleanFormattedAddress(String rawAddress) {
    var address = rawAddress.replaceAll(
        RegExp(r',\s*Brasi?l\s*$', caseSensitive: false), '');
    address = address.replaceAll(RegExp(r',\s*\d{5}-\d{3}'), '');
    address = address.replaceAll(RegExp(r'\s*\d{5}-\d{3}'), '');
    return address.trim();
  }

  /// Text Search: bom para estabelecimentos (POIs)
  Future<List<PlaceEntity>> _googleTextSearch(
    String searchQuery,
    String apiKey,
    String lang,
    LatLng? latLng,
    int radius,
  ) async {
    var url = 'https://maps.googleapis.com/maps/api/place/textsearch/json'
        '?query=${Uri.encodeComponent(searchQuery)}'
        '&key=$apiKey'
        '&language=$lang';

    if (latLng != null) {
      url += '&location=${latLng.latitude},${latLng.longitude}&radius=$radius';
    }

    final googleResponse = await _httpGet(Uri.parse(url));
    if (googleResponse == null || googleResponse['status'] != 'OK') {
      return [];
    }
    final results = googleResponse['results'] as List?;
    if (results == null) return [];

    return results.map((item) {
      final name = item['name'] as String? ?? '';
      final address =
          _cleanFormattedAddress(item['formatted_address'] as String? ?? '');

      final geometry = item['geometry'] as Map<String, dynamic>? ?? {};
      final location = geometry['location'] as Map<String, dynamic>? ?? {};
      final lat = (location['lat'] as num?)?.toDouble() ?? 0.0;
      final lng = (location['lng'] as num?)?.toDouble() ?? 0.0;

      return PlaceEntity(
        coordinates: LatLngEntity(lat: lat, lng: lng),
        title: name.isNotEmpty ? name : null,
        address: address,
      );
    }).toList();
  }

  /// Geocoding API: a API correta para endereços residenciais.
  /// Retorna apenas resultados com precisão de rua ou melhor.
  Future<List<PlaceEntity>> _googleGeocodeSearch(
    String searchQuery,
    String apiKey,
    String lang,
    LatLng? latLng,
  ) async {
    final sanitized = _sanitizeAddressQuery(searchQuery);
    if (sanitized.isEmpty) return [];

    var url = 'https://maps.googleapis.com/maps/api/geocode/json'
        '?address=${Uri.encodeComponent(sanitized)}'
        '&components=country:BR'
        '&key=$apiKey'
        '&language=$lang';

    // Viés de proximidade: prioriza resultados perto do usuário
    if (latLng != null) {
      final south = latLng.latitude - 0.5;
      final north = latLng.latitude + 0.5;
      final west = latLng.longitude - 0.5;
      final east = latLng.longitude + 0.5;
      url += '&bounds=$south,$west|$north,$east';
    }

    final response = await _httpGet(Uri.parse(url));
    if (response == null || response['status'] != 'OK') return [];
    final results = response['results'] as List?;
    if (results == null) return [];

    // Tipos com precisão suficiente para posicionar o alfinete:
    // descarta resultados vagos (bairro, cidade) que jogam o pino longe
    const preciseTypes = {
      'street_address',
      'premise',
      'subpremise',
      'route',
      'intersection',
      'establishment',
      'point_of_interest',
    };

    final places = <PlaceEntity>[];
    for (final item in results) {
      final types =
          ((item['types'] as List?) ?? const []).map((t) => t.toString());
      if (!types.any(preciseTypes.contains)) continue;

      final geometry = item['geometry'] as Map<String, dynamic>? ?? {};
      final location = geometry['location'] as Map<String, dynamic>? ?? {};
      final lat = (location['lat'] as num?)?.toDouble();
      final lng = (location['lng'] as num?)?.toDouble();
      if (lat == null || lng == null) continue;

      final address =
          _cleanFormattedAddress(item['formatted_address'] as String? ?? '');

      String? title;
      final components = item['address_components'] as List? ?? const [];
      final route = components.firstWhere(
        (c) => (c['types'] as List).contains('route'),
        orElse: () => null,
      );
      final streetNumber = components.firstWhere(
        (c) => (c['types'] as List).contains('street_number'),
        orElse: () => null,
      );
      if (route != null) {
        final routeName = route['long_name'] as String? ?? '';
        final number = streetNumber != null
            ? streetNumber['long_name'] as String? ?? ''
            : '';
        title = number.isNotEmpty ? '$routeName, $number' : routeName;
      }

      places.add(PlaceEntity(
        coordinates: LatLngEntity(lat: lat, lng: lng),
        title: title,
        address: address,
      ));
    }
    return places;
  }

  /// Mescla resultados: para buscas que parecem endereço, a Geocoding API
  /// (precisa) vem primeiro; para nomes de lugares, os POIs vêm primeiro.
  /// Remove duplicados muito próximos (< 80 m) ou com o mesmo título.
  List<PlaceEntity> _mergeSearchResults({
    required String query,
    required List<PlaceEntity> geocodePlaces,
    required List<PlaceEntity> poiPlaces,
  }) {
    final addressFirst = _looksLikeAddress(query) && geocodePlaces.isNotEmpty;
    final primary = addressFirst ? geocodePlaces : poiPlaces;
    final secondary = addressFirst ? poiPlaces : geocodePlaces;

    final merged = <PlaceEntity>[...primary];
    for (final place in secondary) {
      final isDuplicate = merged.any((existing) {
        final distance = _distanceInMeters(
          existing.coordinates.lat,
          existing.coordinates.lng,
          place.coordinates.lat,
          place.coordinates.lng,
        );
        final sameTitle = place.title != null &&
            place.title!.isNotEmpty &&
            existing.title == place.title;
        return distance < 80 || sameTitle;
      });
      if (!isDuplicate) merged.add(place);
    }
    return merged.take(7).toList();
  }

  String _formatAddress(
      String road, String houseNumber, String suburb, String city) {
    final parts = <String>[];
    if (road.isNotEmpty) {
      parts.add(houseNumber.isNotEmpty ? '$road, $houseNumber' : road);
    }
    if (suburb.isNotEmpty) parts.add(suburb);
    if (city.isNotEmpty) parts.add(city);
    return parts.join(' - ');
  }

  Future<Map<String, dynamic>?> _httpGet(Uri uri) async {
    try {
      final raw = await _httpGetRaw(uri);
      if (raw == null) return null;
      return json.decode(raw) as Map<String, dynamic>;
    } catch (_) {
      return null;
    }
  }

  Future<String?> _httpGetRaw(Uri uri) async {
    try {
      final response = await (mockClient ?? _httpClient).get(uri, headers: {
        'User-Agent': _userAgent,
      }).timeout(const Duration(seconds: 4));
      if (response.statusCode != 200) return null;
      return utf8.decode(response.bodyBytes);
    } catch (e) {
      debugPrint('[GeoDatasource] HTTP GET raw exception: $e');
      return null;
    }
  }
}
