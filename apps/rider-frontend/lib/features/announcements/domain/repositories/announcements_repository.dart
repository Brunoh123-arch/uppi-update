import 'package:dartz/dartz.dart';
import 'package:rider_flutter/core/error/failure.dart';

import 'package:flutter_common/core/entities/announcement.dart';

abstract class AnnouncementsRepository {
  Future<Either<Failure, List<AnnouncementEntity>>> getAnnouncements();

  Stream<Either<Failure, List<AnnouncementEntity>>> startAnnouncementsSubscription();
}
