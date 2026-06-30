import 'package:dartz/dartz.dart';
import 'package:uppi_motorista/core/datasources/firebase_datasource.dart';
import 'package:uppi_motorista/core/error/failure.dart';
import 'package:injectable/injectable.dart';

import '../../domain/repositories/announcements_repository.dart';
import 'package:flutter_common/core/entities/announcement.dart';

@prod
@LazySingleton(as: AnnouncementsRepository)
class AnnouncementsRepositoryImpl implements AnnouncementsRepository {
  final FirebaseDatasource firebaseDatasource;

  AnnouncementsRepositoryImpl(this.firebaseDatasource);

  @override
  Stream<Either<Failure, List<AnnouncementEntity>>> startAnnouncementsSubscription() async* {
    yield await getAnnouncements();
  }

  @override
  Future<Either<Failure, List<AnnouncementEntity>>> getAnnouncements() async {
    try {
      final result = await firebaseDatasource.supabaseClient
          .from('announcements')
          .select()
          .order('start_at', ascending: false)
          .limit(20);

      final now = DateTime.now();
      final filteredResult = (result as List).where((data) {
        final isActive = data['is_active'] as bool? ?? false;
        if (!isActive) return false;
        
        final startAt = data['start_at'] != null ? DateTime.tryParse(data['start_at'].toString()) : null;
        final endAt = data['end_at'] != null ? DateTime.tryParse(data['end_at'].toString()) : null;
        
        if (startAt != null && startAt.isAfter(now)) return false;
        if (endAt != null && endAt.isBefore(now)) return false;

        final target = data['target_audience']?.toString();
        if (target != null && target != 'all' && target != 'driver') return false;
        
        return true;
      }).toList();

      final announcements = filteredResult.map((data) {
        return AnnouncementEntity(
          id: data['id']?.toString() ?? '',
          title: data['title'] as String? ?? '',
          description: data['description'] as String? ?? '',
          url: data['url'] as String?,
        );
      }).toList();

      return Right(announcements);
    } catch (e) {
      return Left(Failure.server(message: e.toString()));
    }
  }
}
