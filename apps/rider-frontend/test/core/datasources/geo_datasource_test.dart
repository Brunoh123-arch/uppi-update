import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart' as http_testing;
import 'package:latlong2/latlong.dart';
import 'package:generic_map/generic_map.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

import 'package:rider_flutter/core/datasources/geo_datasource.prod.dart';
import 'package:rider_flutter/core/datasources/location_datasource.dart';
import 'package:rider_flutter/core/datasources/firebase_datasource.dart';

class MockLocationDatasource extends Mock implements LocationDatasource {}
class MockFirebaseDatasource extends Mock implements FirebaseDatasource {}

void main() {
  late MockLocationDatasource mockLocationDatasource;
  late MockFirebaseDatasource mockFirebaseDatasource;
  late GeoDatasourceImpl geoDatasource;

  setUpAll(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    dotenv.testLoad(fileInput: 'GOOGLE_MAP_API_KEY=mock-api-key');
  });

  setUp(() {
    mockLocationDatasource = MockLocationDatasource();
    mockFirebaseDatasource = MockFirebaseDatasource();
    geoDatasource = GeoDatasourceImpl(mockFirebaseDatasource, mockLocationDatasource);
  });

  group('GeoDatasourceImpl.getAddressForLocation - Google Maps Reverse Geocoding Accuracy', () {
    test('should select the closest result with a street_number', () async {
      final queryLatLng = LatLng(-1.3106472, -47.9249035);

      final mockGoogleResponse = {
        'status': 'OK',
        'results': [
          {
            'formatted_address': 'Tv. Quintino Bocaiúva, 290 - Pirapora, Castanhal - PA, 68740-020, Brasil',
            'types': ['street_address', 'subpremise'],
            'geometry': {
              'location_type': 'ROOFTOP',
              'location': {'lat': -1.3107109, 'lng': -47.9248806}
            },
            'address_components': [
              {'long_name': '290', 'short_name': '290', 'types': ['street_number']},
              {'long_name': 'Tv. Quintino Bocaiúva', 'short_name': 'Tv. Quintino Bocaiúva', 'types': ['route']}
            ]
          },
          {
            'formatted_address': 'Tv. Quintino Bocaiúva, 100 - Pirapora, Castanhal - PA, 68740-570, Brasil',
            'types': ['premise', 'street_address'],
            'geometry': {
              'location_type': 'ROOFTOP',
              'location': {'lat': -1.3106472, 'lng': -47.9249035}
            },
            'address_components': [
              {'long_name': '100', 'short_name': '100', 'types': ['street_number']},
              {'long_name': 'Tv. Quintino Bocaiúva', 'short_name': 'Tv. Quintino Bocaiúva', 'types': ['route']}
            ]
          }
        ]
      };

      geoDatasource.mockClient = http_testing.MockClient((request) async {
        print('MOCK CLIENT RECEIVED REQUEST: ${request.url}');
        return http.Response(
          json.encode(mockGoogleResponse),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      });

      final result = await geoDatasource.getAddressForLocation(
        latLng: queryLatLng,
        language: 'pt-BR',
        mapProvider: MapProviderEnum.googleMaps,
      );

      print('RESULT IS: $result');
      result.fold(
        (l) => print('LEFT FAILURE IS: $l'),
        (r) => print('RIGHT SUCCESS IS: $r'),
      );

      expect(result.isRight(), isTrue);
      final place = result.getOrElse(() => throw Exception('Failed'));
      expect(place.address, contains('100'));
      expect(place.address, isNot(contains('290')));
    });
  });
}
