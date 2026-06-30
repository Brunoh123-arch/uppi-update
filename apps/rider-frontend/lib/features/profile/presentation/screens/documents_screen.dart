import 'package:auto_route/auto_route.dart';
import 'package:flutter/material.dart';
import 'package:flutter_common/core/presentation/uppi_cached_image.dart';
import 'package:ionicons/ionicons.dart';
import 'package:rider_flutter/config/locator/locator.dart';
import 'package:rider_flutter/core/datasources/firebase_datasource.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:rider_flutter/core/extensions/extensions.dart';
import 'package:flutter_common/core/color_palette/color_palette.dart';
import 'package:flutter_common/core/presentation/responsive_dialog/app_top_bar.dart';
import 'package:rider_flutter/features/home/features/order_preview/presentation/dialogs/identity_verification_dialog.dart';
import 'package:flutter_common/core/presentation/buttons/app_primary_button.dart';

@RoutePage()
class DocumentsScreen extends StatefulWidget {
  const DocumentsScreen({super.key});

  @override
  State<DocumentsScreen> createState() => _DocumentsScreenState();
}

class _DocumentsScreenState extends State<DocumentsScreen> {
  bool _isLoading = true;
  String? _status;
  String? _selfieUrl;
  String? _rgUrl;

  @override
  void initState() {
    super.initState();
    _loadDocuments();
  }

  Future<void> _loadDocuments() async {
    try {
      final supabase = Supabase.instance.client;
      final uid =
          supabase.auth.currentUser?.id ?? locator<FirebaseDatasource>().uid;
      if (uid != null) {
        final profile = await supabase
            .from('profiles')
            .select('vehicle_details')
            .eq('id', uid)
            .maybeSingle();

        if (profile != null) {
          final meta = profile['vehicle_details'] as Map? ?? {};
          final idStatus = meta['identityVerificationStatus']?.toString();
          final docs = meta['identityDocs'] as Map?;

          setState(() {
            _status = idStatus;
            _selfieUrl = docs?['selfieUrl']?.toString();
            _rgUrl = docs?['rgUrl']?.toString();
          });
        }
      }
    } catch (e) {
      debugPrint('Error loading documents: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  String _getStatusText() {
    switch (_status) {
      case 'pending':
        return 'Em Análise';
      case 'approved':
        return 'Aprovado';
      case 'rejected':
        return 'Rejeitado (Reenviar)';
      default:
        return 'Conta não verificada';
    }
  }

  Color _getStatusColor() {
    switch (_status) {
      case 'pending':
        return Colors.orange;
      case 'approved':
        return Colors.green;
      case 'rejected':
        return Colors.red;
      default:
        return Colors.grey;
    }
  }

  @override
  Widget build(BuildContext context) {
    final showUploadButton =
        _status == null || _status == 'none' || _status == 'rejected';

    return Scaffold(
      backgroundColor: context.theme.scaffoldBackgroundColor,
      body: SafeArea(
        child: Padding(
          padding: EdgeInsets.symmetric(
            horizontal: context.responsive(16, xl: 24),
            vertical: context.responsive(16, xl: 24),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const AppTopBar(title: 'Meus Documentos'),
              const SizedBox(height: 24),
              Expanded(
                child: _isLoading
                    ? const Center(child: CircularProgressIndicator())
                    : SingleChildScrollView(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Text(
                              'Status da Verificação de Identidade',
                              style: context.bodyMedium?.copyWith(
                                color: ColorPalette.neutralVariant50,
                              ),
                            ),
                            const SizedBox(height: 24),
                            Container(
                              padding: const EdgeInsets.all(16),
                              decoration: BoxDecoration(
                                color: _getStatusColor().withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(color: _getStatusColor()),
                              ),
                              child: Row(
                                children: [
                                  Icon(
                                    Ionicons.information_circle,
                                    color: _getStatusColor(),
                                    size: 24,
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Text(
                                      'Status Atual: ${_getStatusText()}',
                                      style: context.bodyMedium?.copyWith(
                                        color: _getStatusColor(),
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  )
                                ],
                              ),
                            ),
                            const SizedBox(height: 32),
                            if (_selfieUrl != null || _rgUrl != null) ...[
                              Text(
                                'Documentos Enviados:',
                                style: context.titleMedium?.copyWith(
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const SizedBox(height: 16),
                              if (_selfieUrl != null) ...[
                                Text('Selfie:', style: context.bodyMedium),
                                const SizedBox(height: 8),
                                UppiCachedImage(
                                  imageUrl: _selfieUrl!,
                                  height: 200,
                                  width: double.infinity,
                                  fit: BoxFit.cover,
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                const SizedBox(height: 24),
                              ],
                              if (_rgUrl != null) ...[
                                Text('Identidade (RG/CNH):',
                                    style: context.bodyMedium),
                                const SizedBox(height: 8),
                                UppiCachedImage(
                                  imageUrl: _rgUrl!,
                                  height: 200,
                                  width: double.infinity,
                                  fit: BoxFit.cover,
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ],
                            ] else ...[
                              Center(
                                child: Padding(
                                  padding: const EdgeInsets.all(32.0),
                                  child: Text(
                                    'Você ainda não enviou documentos. O aplicativo solicitará automaticamente na sua primeira corrida.',
                                    textAlign: TextAlign.center,
                                    style: context.bodyMedium
                                        ?.copyWith(color: Colors.grey),
                                  ),
                                ),
                              )
                            ],
                            if (showUploadButton) ...[
                              const SizedBox(height: 32),
                              AppPrimaryButton(
                                onPressed: () {
                                  showDialog(
                                    context: context,
                                    useSafeArea: false,
                                    builder: (context) =>
                                        const IdentityVerificationDialog(),
                                  ).then((_) {
                                    setState(() => _isLoading = true);
                                    _loadDocuments();
                                  });
                                },
                                child: const Text('Enviar Documentos'),
                              ),
                            ]
                          ],
                        ),
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
