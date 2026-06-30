// cloud_firestore removido — earnings_repository usa 100% Supabase

import 'package:dartz/dartz.dart';
import 'package:uppi_motorista/core/datasources/firebase_datasource.dart';
import 'package:uppi_motorista/core/error/failure.dart';
import 'package:uppi_motorista/features/earnings/domain/entities/earnings_dataset.dart';
import 'package:uppi_motorista/features/earnings/domain/entities/earnings_ride_details.dart';
import 'package:uppi_motorista/features/earnings/domain/enums/earnings_timeframe.dart';
import 'package:injectable/injectable.dart';

import '../../domain/repositories/earnings_repository.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

@prod
@LazySingleton(as: EarningsRepository)
class EarningsRepositoryImpl implements EarningsRepository {
  final FirebaseDatasource firebaseDatasource;
  final SupabaseClient supabaseClient;

  EarningsRepositoryImpl(this.firebaseDatasource)
    : supabaseClient = Supabase.instance.client;

  @override
  Stream<Either<Failure, EarningsDataset>> startEarningsSubscription({
    required EarningsTimeFrame timeFrame,
    required DateTime startDate,
    required DateTime endDate,
  }) async* {
    final uid = firebaseDatasource.uid;
    if (uid == null) {
      yield Left(Failure.server(message: 'User not authenticated'));
      return;
    }
    // Emitir imediatamente via REST — não depender do websocket realtime
    // para a primeira carga (se ele falhar, os ganhos ficariam vazios).
    yield await getEarningsDataset(
      timeFrame: timeFrame,
      startDate: startDate,
      endDate: endDate,
    );

    yield* supabaseClient
        .from('rides')
        .stream(primaryKey: ['id'])
        .eq('driver_id', uid)
        .asyncMap((event) async {
      return await getEarningsDataset(
        timeFrame: timeFrame,
        startDate: startDate,
        endDate: endDate,
      );
    }).handleError((_) {});
  }

  @override
  Future<Either<Failure, EarningsDataset>> getEarningsDataset({
    required EarningsTimeFrame timeFrame,
    required DateTime startDate,
    required DateTime endDate,
  }) async {
    try {
      final uid = firebaseDatasource.uid;
      if (uid == null) {
        return Left(Failure.server(message: 'User not authenticated'));
      }

      final startIso = startDate.toUtc().toIso8601String();
      final endIso = endDate.toUtc().toIso8601String();

      // 🛡️ FONTE DA VERDADE: `driver_earnings` é gravado de forma atômica pela
      // RPC `finish_ride` (exatamente uma vez por corrida) e já contém o valor
      // líquido REAL creditado ao motorista (tarifa − comissão), honrando a
      // comissão individual do motorista, isenções (`commission_exempt_until`)
      // e o recálculo por desvio de rota. NUNCA recalcular a tarifa no cliente:
      // isso divergia da carteira (usava `original_fare`, ignorava gorjetas e a
      // comissão por motorista). Aqui apenas SOMAMOS o que o servidor gravou.
      final earningsRows = await supabaseClient
          .from('driver_earnings')
          .select(
            'id, net_amount, gross_amount, commission_amt, created_at, '
            'rides(id, actual_distance, distance_meters, distance, actual_duration, duration_seconds, service_type, pickup_address, dropoff_address, currency)',
          )
          .eq('driver_id', uid)
          .gte('created_at', startIso)
          .lte('created_at', endIso);

      // Gorjetas/incentivos (Uppi Flex) são repassados 100% ao motorista, porém
      // não ficam em `driver_earnings` — vêm do livro-razão da carteira.
      double tips = 0;
      try {
        final tipRows = await supabaseClient
            .from('wallet_transactions')
            .select('amount')
            .eq('user_id', uid)
            .eq('type', 'tip_incentive')
            .eq('status', 'completed')
            .gte('created_at', startIso)
            .lte('created_at', endIso);
        for (final t in tipRows) {
          tips += ((t['amount'] as num?) ?? 0).toDouble().abs();
        }
      } catch (_) {}

      // Moeda configurada no Painel Admin (fallback BRL).
      String appCurrency = 'BRL';
      try {
        final currencyRow = await supabaseClient
            .from('app_settings')
            .select('value')
            .eq('key', 'currency')
            .maybeSingle();
        if (currencyRow != null && currencyRow['value'] != null) {
          appCurrency = currencyRow['value'].toString();
        }
      } catch (_) {}

      final datapoints = <EarningsDatapoint>[];
      final ridesList = <EarningsRideDetails>[];

      if (earningsRows.isNotEmpty || tips > 0) {
        double totalEarnings = 0;
        int totalDistance = 0;
        int totalTime = 0;

        for (final data in earningsRows) {
          final double netAmt = ((data['net_amount'] as num?) ?? 0).toDouble();
          totalEarnings += netAmt;

          final ride = data['rides'] as Map<String, dynamic>?;
          if (ride != null) {
            // Distância real percorrida tem prioridade sobre a estimada;
            // > 200 km numa corrida urbana é dado corrompido/teste — ignora.
            final rideDistance = ((ride['actual_distance'] as num?) ??
                    (ride['distance_meters'] as num?) ??
                    (ride['distance'] as num?) ??
                    0)
                .toInt();
            if (rideDistance <= 200000) {
              totalDistance += rideDistance;
            }
            totalTime += ((ride['actual_duration'] as num?) ??
                    (ride['duration_seconds'] as num?) ??
                    0)
                .toInt();

            final DateTime rowCreatedAt = DateTime.tryParse(data['created_at'].toString())?.toLocal() ?? DateTime.now();
            final String rideId = ride['id']?.toString() ?? '';
            final String sName = ride['service_type']?.toString() ?? 'Padrão';
            final String pickup = ride['pickup_address']?.toString() ?? 'Ponto de Origem';
            final String dropoff = ride['dropoff_address']?.toString() ?? 'Ponto de Destino';

            ridesList.add(
              EarningsRideDetails(
                id: rideId,
                amount: double.parse(netAmt.toStringAsFixed(2)),
                createdAt: rowCreatedAt,
                serviceName: sName,
                pickupAddress: pickup,
                dropoffAddress: dropoff,
              ),
            );
          }
        }

        // Gorjetas entram no total (é dinheiro real do motorista).
        totalEarnings += tips;

        datapoints.add(
          EarningsDatapoint(
            title: "Total",
            earnings: double.parse(totalEarnings.toStringAsFixed(2)),
            rides: earningsRows.length,
            timeSpent: totalTime,
            distanceTraveled: totalDistance,
          ),
        );
      }

      return Right(EarningsDataset(
        currency: appCurrency,
        datapoints: datapoints,
        rides: ridesList,
      ));
    } catch (e) {
      return Left(Failure.server(message: e.toString()));
    }
  }
}
