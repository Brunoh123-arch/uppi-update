import 'package:flutter/material.dart';
import 'package:flutter_common/core/presentation/empty_list_state.dart';

class SharedAnnouncementEmptyState extends StatelessWidget {
  final String imagePath;
  final String title;

  const SharedAnnouncementEmptyState({
    super.key,
    required this.imagePath,
    required this.title,
  });

  @override
  Widget build(BuildContext context) {
    return EmptyListState(
      imagePath: imagePath,
      title: title,
    );
  }
}
