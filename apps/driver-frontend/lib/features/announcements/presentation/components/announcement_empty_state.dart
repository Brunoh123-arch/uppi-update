import 'package:flutter/material.dart';
import 'package:flutter_common/features/announcements/presentation/components/announcement_empty_state.dart';
import 'package:uppi_motorista/core/extensions/extensions.dart';
import 'package:uppi_motorista/gen/assets.gen.dart';

class AnnouncementEmptyState extends StatelessWidget {
  const AnnouncementEmptyState({super.key});

  @override
  Widget build(BuildContext context) {
    return SharedAnnouncementEmptyState(
      imagePath: Assets.images.announcementEmpty.path,
      title: context.translate.noAnnouncements,
    );
  }
}
