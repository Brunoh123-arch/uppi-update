import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:ionicons/ionicons.dart';
import 'package:share_plus/share_plus.dart';
import 'package:flutter_common/core/color_palette/color_palette.dart';
import 'package:flutter_common/core/presentation/buttons/app_list_button.dart';
import 'package:flutter_common/core/utils/friendly_error.dart';
import 'package:url_launcher/url_launcher.dart';

/// Botão de compartilhar viagem em tempo real — padrão Uppi AppListButton
class ShareTripButton extends StatefulWidget {
  final String orderId;

  const ShareTripButton({super.key, required this.orderId});

  @override
  State<ShareTripButton> createState() => _ShareTripButtonState();
}

class _ShareTripButtonState extends State<ShareTripButton> {
  bool isLoading = false;

  Future<void> _generateAndShare() async {
    setState(() => isLoading = true);

    try {
      final currentUserId = Supabase.instance.client.auth.currentUser?.id ?? '';
      final String token = await Supabase.instance.client.rpc(
        'rpc_get_or_create_ride_share_token',
        params: {
          'p_ride_id': widget.orderId,
          'p_user_id': currentUserId,
        },
      );

      final url = 'https://uppibrazil.web.app/acompanhar/$token';

      await Share.share(
        '🚗 Acompanhe minha viagem pelo Uppi em tempo real:\n$url',
        subject: 'Acompanhe minha viagem - Uppi',
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(friendlyErrorMessage(e, fallback: 'Não foi possível gerar o link.')),
            backgroundColor: ColorPalette.error40,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AppListButton(
      icon: Ionicons.location,
      iconColor: ColorPalette.primary40,
      title: 'Compartilhar viagem ao vivo',
      subtitle: 'Envie o link para alguém acompanhar em tempo real',
      onPressed: isLoading ? null : _generateAndShare,
    );
  }
}

/// Botão de compartilhar viagem em tempo real via WhatsApp — padrão Uppi AppListButton
class ShareTripWhatsAppButton extends StatefulWidget {
  final String orderId;

  const ShareTripWhatsAppButton({super.key, required this.orderId});

  @override
  State<ShareTripWhatsAppButton> createState() => _ShareTripWhatsAppButtonState();
}

class _ShareTripWhatsAppButtonState extends State<ShareTripWhatsAppButton> {
  bool isLoading = false;

  Future<void> _generateAndShareWhatsApp() async {
    setState(() => isLoading = true);

    try {
      final currentUserId = Supabase.instance.client.auth.currentUser?.id ?? '';
      final String token = await Supabase.instance.client.rpc(
        'rpc_get_or_create_ride_share_token',
        params: {
          'p_ride_id': widget.orderId,
          'p_user_id': currentUserId,
        },
      );

      final url = 'https://uppibrazil.web.app/acompanhar/$token';
      
      final msg = '🚗 Acompanhe minha viagem pelo Uppi em tempo real:\n$url';
      final whatsappUrl = Uri.parse("https://api.whatsapp.com/send?text=${Uri.encodeComponent(msg)}");
      
      await launchUrl(whatsappUrl, mode: LaunchMode.externalApplication);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(friendlyErrorMessage(e, fallback: 'Não foi possível gerar o link do WhatsApp.')),
            backgroundColor: ColorPalette.error40,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AppListButton(
      icon: Ionicons.logo_whatsapp,
      iconColor: const Color(0xFF25D366), // Verde clássico e premium do WhatsApp
      title: 'Compartilhar no WhatsApp',
      subtitle: 'Envie direto para um contato no seu WhatsApp',
      onPressed: isLoading ? null : _generateAndShareWhatsApp,
    );
  }
}
