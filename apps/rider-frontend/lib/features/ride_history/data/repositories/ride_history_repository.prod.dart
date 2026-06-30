import 'package:dartz/dartz.dart';
import 'package:injectable/injectable.dart';
import 'package:rider_flutter/core/datasources/firebase_datasource.dart';
import 'package:rider_flutter/core/entities/order_compact.dart';
import 'package:rider_flutter/core/entities/driver.dart';
import 'package:rider_flutter/core/error/failure.dart';
import 'package:flutter_common/core/entities/place.dart';
import 'package:flutter_common/core/entities/payment_method_union.dart';
import 'package:flutter_common/core/entities/payment_gateway.dart';
import 'package:flutter_common/core/enums/gateway_link_method.dart';

import '../../domain/repositories/ride_history_repository.dart';
import 'package:rider_flutter/core/mappers/firestore_mapper.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

@prod
@LazySingleton(as: RideHistoryRepository)
class RideHistoryRepositoryImpl implements RideHistoryRepository {
  final FirebaseDatasource firebaseDatasource;
  final SupabaseClient supabaseClient;

  RideHistoryRepositoryImpl(
    this.firebaseDatasource, {
    SupabaseClient? supabaseClient,
  }) : supabaseClient = supabaseClient ?? Supabase.instance.client;

  @override
  Stream<Either<Failure, List<OrderCompactEntity>>> startRideHistorySubscription() async* {
    yield await getRideHistory();
  }

  @override
  Future<Either<Failure, List<OrderCompactEntity>>> getRideHistory() async {
    try {
      final uid = firebaseDatasource.uid;
      if (uid == null) {
        return Left(Failure.serverError('User not authenticated'));
      }

      final queryResult = await supabaseClient
          .from('rides')
          .select()
          .eq('rider_id', uid)
          .inFilter('status', ['completed', 'finished', 'canceled', 'rider_canceled', 'driver_canceled', 'expired', 'no_driver', 'no_close_found'])
          .order('created_at', ascending: false)
          .limit(20);

      final driverIds = queryResult
          .map((d) => d['driver_id']?.toString())
          .whereType<String>()
          .toSet()
          .toList();

      final Map<String, DriverEntity> driversById = {};
      if (driverIds.isNotEmpty) {
        final driverProfiles = await supabaseClient
            .from('profiles')
            .select()
            .inFilter('id', driverIds);
        for (final dp in driverProfiles) {
          final id = dp['id']?.toString();
          if (id == null) continue;
          final dbRating =
              double.tryParse(dp['rating']?.toString() ?? '5.0') ?? 5.0;
          final fullName = dp['full_name']?.toString();
          final driverName = (fullName != null && fullName != 'unknown' && fullName.trim().isNotEmpty)
              ? fullName
              : 'Dev Motorista';

          final model = dp['vehicle_details']?['model']?.toString();
          final vehicleModel = (model != null && model != 'Regular' && model.trim().isNotEmpty)
              ? model
              : 'Veículo de Testes';

          driversById[id] = DriverEntity(
            firstName: driverName,
            lastName: '',
            mobileNumber: dp['id']?.toString() ?? '',
            imageUrl: dp['avatar_url']?.toString() ??
                'https://ui-avatars.com/api/?name=Motorista&background=096EFF&color=fff&size=128',
            rating: (dbRating * 20).toInt(), // escala /20 usada pelos widgets
            ratingCount: (dp['rating_count'] as num?)?.toInt() ?? 0,
            vehiclePlateNumber:
                dp['vehicle_details']?['plate']?.toString() ?? '',
            vehicleColor: dp['vehicle_details']?['color']?.toString() ?? '',
            vehicleModel: vehicleModel,
          );
        }
      }

      // Buscar os serviços (nome/imagem) das corridas em UMA query, para o
      // histórico mostrar o serviço real (ex.: "Uppi Moto") em vez de "Uppi".
      final serviceIds = queryResult
          .map((d) => d['service_id']?.toString())
          .whereType<String>()
          .toSet()
          .toList();

      final Map<String, Map<String, dynamic>> servicesById = {};
      if (serviceIds.isNotEmpty) {
        final serviceRows = await supabaseClient
            .from('services')
            .select('id, name, image_url')
            .inFilter('id', serviceIds);
        for (final s in serviceRows) {
          final id = s['id']?.toString();
          if (id != null) servicesById[id] = s;
        }
      }

      final orders = queryResult.map((data) {
        final service = servicesById[data['service_id']?.toString()];
        final mockData = {
          'id': data['id'].toString(),
          'status': (data['status'] == 'completed' || data['status'] == 'finished')
              ? 'Finished'
              : (data['status'] == 'canceled' || data['status'] == 'rider_canceled' || data['status'] == 'driver_canceled')
                  ? 'RiderCanceled'
                  : 'Expired',
          'createdAt': data['created_at'],
          'endedAt': data['finished_at'] ?? data['canceled_at'] ?? data['updated_at'],
          'distanceBest': data['distance_meters'] ?? 0,
          'durationBest': data['duration_seconds'] ?? 0,
          'costBest': data['fare'] ?? 0.0,
          'serviceName': service?['name']?.toString() ??
              data['service_type']?.toString() ??
              'Uppi',
          'currency': data['currency']?.toString() ?? 'BRL',
          'waypoints': [
            PlaceEntity(
              coordinates: LatLngEntity(lat: (data['pickup_lat'] as num?)?.toDouble() ?? 0, lng: (data['pickup_lng'] as num?)?.toDouble() ?? 0),
              address: data['pickup_address']?.toString() ?? 'Ponto de Origem',
            ),
            PlaceEntity(
              coordinates: LatLngEntity(lat: (data['dropoff_lat'] as num?)?.toDouble() ?? 0, lng: (data['dropoff_lng'] as num?)?.toDouble() ?? 0),
              address: data['dropoff_address']?.toString() ?? 'Ponto de Destino',
            ),
          ],
        };
        final driverId = data['driver_id']?.toString();
        return FirestoreMapper.toOrderCompact(mockData).copyWith(
          driver: driverId != null ? driversById[driverId] : null,
          // Forma de pagamento real da corrida (antes vinha sempre "Dinheiro").
          paymentMethodUnion:
              _paymentMethodFromString(data['payment_method']?.toString()),
          serviceImageUrl: () {
            final rawImg = service?['image_url']?.toString();
            if (rawImg == null || rawImg.isEmpty) return null;
            if (rawImg.startsWith('http://') || rawImg.startsWith('https://')) {
              return rawImg;
            }
            final supabaseUrl = dotenv.isInitialized
                ? dotenv.maybeGet('SUPABASE_URL') ?? 'https://kqfmahrxjuqlvxngeurj.supabase.co'
                : 'https://kqfmahrxjuqlvxngeurj.supabase.co';
            return '$supabaseUrl/storage/v1/object/public/service-images/$rawImg';
          }(),
        );
      }).toList();

      return Right(orders);
    } catch (e) {
      return Left(Failure.serverError(e.toString()));
    }
  }

  /// Converte a string `payment_method` da tabela `rides`
  /// (cash / wallet / pix / credit_card) na união usada pela UI do histórico.
  PaymentMethodUnion _paymentMethodFromString(String? method) {
    switch (method?.toLowerCase()) {
      case 'wallet':
      case 'carteira':
        return const PaymentMethodUnion.wallet();
      case 'pix':
        return const PaymentMethodUnion.paymentGateway(
          paymentGateway: PaymentGatewayEntity(
            id: 'pix',
            name: 'PIX',
            logoUrl: null,
            linkMethod: GatewayLinkMethod.none,
          ),
        );
      case 'credit_card':
      case 'card':
      case 'cartao':
      case 'cartão':
        return const PaymentMethodUnion.paymentGateway(
          paymentGateway: PaymentGatewayEntity(
            id: 'credit_card',
            name: 'Cartão de crédito',
            logoUrl: null,
            linkMethod: GatewayLinkMethod.none,
          ),
        );
      case 'cash':
      case 'dinheiro':
      default:
        return const PaymentMethodUnion.cash();
    }
  }

  @override
  Future<Either<Failure, bool>> reportIssue({
    required String orderId,
    required String subject,
    required String issue,
  }) async {
    try {
      final uid = firebaseDatasource.uid;
      if (uid == null) {
        return Left(Failure.serverError('User not authenticated'));
      }

      // Registra reclamação via Edge Function (garante RLS e integridade)
      final response = await supabaseClient.functions.invoke(
        'submit-feedback',
        body: {
          'ride_id': orderId,
          'subject': subject,
          'review': issue,
          'is_complaint': true,
        },
      );

      if (response.status != 200) {
        throw Exception('Failed to submit feedback');
      }

      return const Right(true);
    } catch (e) {
      return Left(Failure.serverError(e.toString()));
    }
  }
}
