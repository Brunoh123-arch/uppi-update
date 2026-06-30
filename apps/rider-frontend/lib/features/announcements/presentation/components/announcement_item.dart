import 'package:flutter/cupertino.dart';
import 'package:flutter_common/features/announcements/presentation/components/announcement_item.dart';
import 'package:flutter_common/core/entities/announcement.dart';
import 'package:url_launcher/url_launcher_string.dart';

class AnnouncementItem extends StatelessWidget {
  final AnnouncementEntity entity;

  const AnnouncementItem({
    super.key,
    required this.entity,
  });

  @override
  Widget build(BuildContext context) {
    return SharedAnnouncementItem(
      title: entity.title,
      description: entity.description,
      url: entity.url,
      onPressed: entity.url == null
          ? null
          : () {
              launchUrlString(entity.url!);
            },
    );
  }
}
