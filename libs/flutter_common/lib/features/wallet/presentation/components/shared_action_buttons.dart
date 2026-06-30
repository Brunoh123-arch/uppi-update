import 'package:flutter/cupertino.dart';
import 'package:ionicons/ionicons.dart';
import 'package:flutter_common/core/color_palette/color_palette.dart';
import 'package:flutter_common/core/extensions/extensions.dart';

class SharedActionButtons extends StatelessWidget {
  final Future<void> Function() onRedeemGiftCard;
  final VoidCallback onAddCredit;
  final VoidCallback? onWithdraw;

  const SharedActionButtons({
    super.key,
    required this.onRedeemGiftCard,
    required this.onAddCredit,
    this.onWithdraw,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: ColorPalette.neutralVariant99,
        border: Border.all(
          color: ColorPalette.primary95,
        ),
        borderRadius: BorderRadius.circular(18),
        boxShadow: const [
          BoxShadow(
            color: Color(0x1464748B),
            blurRadius: 8,
            offset: Offset(2, 4),
            spreadRadius: 0,
          ),
        ],
      ),
      child: Container(
        decoration: BoxDecoration(
          border: Border.all(
            color: ColorPalette.primary95,
          ),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            Expanded(
              child: CupertinoButton(
                padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
                onPressed: onRedeemGiftCard,
                minimumSize: const Size(0, 0),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(
                      Ionicons.gift,
                      color: ColorPalette.primary80,
                    ),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Text(
                        context.t.redeemGiftCard,
                        style: context.labelLarge,
                        overflow: TextOverflow.ellipsis,
                        maxLines: 1,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            Container(
              width: 1,
              height: 32,
              color: ColorPalette.primary95,
            ),
            Expanded(
              child: CupertinoButton(
                padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
                onPressed: onAddCredit,
                minimumSize: const Size(0, 0),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(
                      Ionicons.add_circle,
                      color: ColorPalette.primary80,
                    ),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Text(
                        context.t.addCredit,
                        style: context.labelLarge,
                        overflow: TextOverflow.ellipsis,
                        maxLines: 1,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            if (onWithdraw != null) ...[
              Container(
                width: 1,
                height: 32,
                color: ColorPalette.primary95,
              ),
              Expanded(
                child: CupertinoButton(
                  padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
                  onPressed: onWithdraw,
                  minimumSize: const Size(0, 0),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(
                        Ionicons.cash,
                        color: ColorPalette.primary80,
                      ),
                      const SizedBox(width: 8),
                      Flexible(
                        child: Text(
                          "Retirada Pix",
                          style: context.labelLarge,
                          overflow: TextOverflow.ellipsis,
                          maxLines: 1,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
