import 'dart:async';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter_common/core/color_palette/color_palette.dart';
import 'package:flutter_common/core/extensions/extensions.dart';

class WalletCoupons extends StatefulWidget {
  const WalletCoupons({super.key});

  @override
  State<WalletCoupons> createState() => _WalletCouponsState();
}

class _WalletCouponsState extends State<WalletCoupons> {
  List<Map<String, dynamic>> _coupons = [];
  bool _isLoading = true;
  RealtimeChannel? _couponsChannel;

  @override
  void initState() {
    super.initState();
    _fetchCoupons();
    _startCouponsListener();
  }

  Future<void> _fetchCoupons() async {
    try {
      final supabase = Supabase.instance.client;
      final result = await supabase
          .from('coupons')
          .select()
          .eq('is_active', true)
          .limit(10);
      if (mounted) {
        setState(() {
          _coupons = List<Map<String, dynamic>>.from(result);
          _isLoading = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  void _startCouponsListener() {
    _couponsChannel = Supabase.instance.client
        .channel('wallet_coupons_changes')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'coupons',
          callback: (payload) {
            _fetchCoupons();
          },
        );
    try {
      _couponsChannel!.subscribe();
    } catch (_) {}
  }

  @override
  void dispose() {
    if (_couponsChannel != null) {
      try {
        Supabase.instance.client.removeChannel(_couponsChannel!);
      } catch (_) {}
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Padding(
        padding: EdgeInsets.all(16.0),
        child: Center(child: CircularProgressIndicator.adaptive()),
      );
    }

    if (_coupons.isEmpty) {
      return const SizedBox.shrink();
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Cupons de Desconto Disponíveis',
            style: context.titleMedium?.copyWith(
              fontWeight: FontWeight.bold,
              color: ColorPalette.neutralVariant30,
            ),
          ),
          const SizedBox(height: 8),
          ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: _coupons.length,
            separatorBuilder: (_, __) => const SizedBox(height: 10),
            itemBuilder: (context, index) {
              final coupon = _coupons[index];
              final code = coupon['code']?.toString() ?? '';
              final discount = (coupon['discount'] as num?)?.toDouble() ?? 0.0;
              final isFixed = coupon['discount_type']?.toString() == 'fixed';

              return Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: ColorPalette.primary99, // Fundo no azul original ultra suave
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: ColorPalette.primary80, // Borda no azul original suave
                    width: 1,
                  ),
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.local_offer_rounded,
                      color: ColorPalette.primary40, // Ícone no azul original
                      size: 24,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            code,
                            style: context.titleSmall?.copyWith(
                              fontWeight: FontWeight.bold,
                              color: ColorPalette.primary30, // Texto principal no azul escuro
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            isFixed
                                ? 'Ganhe R\$ ${discount.toStringAsFixed(2)} de desconto fixo na sua viagem!'
                                : 'Ganhe ${discount.toInt()}% de desconto na sua próxima viagem!',
                            style: context.bodyMedium?.copyWith(
                              color: ColorPalette.primary40, // Texto secundário no azul original médio
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}
