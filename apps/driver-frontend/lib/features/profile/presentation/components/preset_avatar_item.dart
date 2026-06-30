import 'package:flutter/cupertino.dart';
import 'package:flutter_common/features/profile/presentation/components/preset_avatar_item.dart';

class PresetAvatarItem extends StatelessWidget {
  final int index;
  final Function(int) onPressed;
  final int? selectedIndex;

  const PresetAvatarItem({
    super.key,
    required this.index,
    required this.onPressed,
    required this.selectedIndex,
  });

  @override
  Widget build(BuildContext context) {
    return SharedPresetAvatarItem(
      index: index,
      onPressed: onPressed,
      selectedIndex: selectedIndex,
    );
  }
}
