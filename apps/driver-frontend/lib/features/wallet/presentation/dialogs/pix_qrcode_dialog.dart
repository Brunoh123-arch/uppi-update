import 'dart:async';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;

import 'package:auto_route/auto_route.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_common/core/color_palette/color_palette.dart';
import 'package:uppi_motorista/config/locator/locator.dart';
import 'package:uppi_motorista/core/datasources/firebase_datasource.dart';

/// Tela de pagamento PIX via Paradise Pags
/// Gera QR Code PIX para recarga de wallet do motorista
class PixQrCodeDialog extends StatefulWidget {
  final double amount;
  final String currency;

  const PixQrCodeDialog({
    super.key,
    required this.amount,
    required this.currency,
  });

  @override
  State<PixQrCodeDialog> createState() => _PixQrCodeDialogState();
}

class _PixQrCodeDialogState extends State<PixQrCodeDialog>
    with SingleTickerProviderStateMixin {
  // Stages
  bool _isLoadingQr = false;
  bool _isCheckingStatus = false;
  bool _qrGenerated = false;
  bool _paymentApproved = false;
  String? _errorMessage;

  // PIX data
  String _qrCode = '';
  Uint8List? _qrCodeImage;
  String _reference = '';
  String? _expiresAt;
  StreamSubscription? _pixSubscription;

  // Form data (CPF)
  final _formKey = GlobalKey<FormState>();
  final _cpfController = TextEditingController();
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _phoneController = TextEditingController();

  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat(reverse: true);
    _pulseAnimation = Tween<double>(begin: 0.95, end: 1.05).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    // Pre-fill data from Firebase profile
    _prefillUserData();
  }

  @override
  void dispose() {
    _pixSubscription?.cancel();
    _pulseController.dispose();
    _cpfController.dispose();
    _nameController.dispose();
    _emailController.dispose();
    _phoneController.dispose();
    super.dispose();
  }

  void _prefillUserData() async {
    try {
      final ds = locator<FirebaseDatasource>();
      final uid = ds.uid;
      if (uid == null) return;

      final data = await ds.supabaseClient
          .from('profiles')
          .select()
          .eq('id', uid)
          .maybeSingle();
      if (data != null) {
        final fullName = data['full_name'] as String? ?? '';
        _nameController.text = fullName;
        _emailController.text = data['email'] as String? ?? '';
        _phoneController.text = data['phone'] as String? ?? '';
        _cpfController.text =
            data['id_number'] as String? ??
            data['certificate_number'] as String? ??
            '';
        if (mounted) setState(() {});
      }
    } catch (_) {}
  }

  Future<void> _generatePixQrCode() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isLoadingQr = true;
      _errorMessage = null;
    });

    try {
      final idToken = Supabase.instance.client.auth.currentSession?.accessToken;
      if (idToken == null) throw Exception("Could not get auth token");

      final payload = jsonEncode({
        'data': {
          'amount': widget.amount,
          'customerName': _nameController.text.trim(),
          'customerEmail': _emailController.text.trim(),
          'customerDocument': _cpfController.text.replaceAll(RegExp(r'\D'), ''),
          'customerPhone': _phoneController.text.replaceAll(RegExp(r'\D'), ''),
          'accountType': 'drivers',
        },
      });

      final response = await http.post(
        Uri.parse('${dotenv.env['SUPABASE_URL']}/functions/v1/create-pix-payment'),
        headers: {
          'Authorization': 'Bearer $idToken',
          'Content-Type': 'application/json',
        },
        body: payload,
      );
      final responseJson = jsonDecode(response.body);
      final data = responseJson['result'] as Map<String, dynamic>? ?? {};

      if (data['success'] == true) {
        setState(() {
          _qrGenerated = true;
          _qrCode = data['qrCode'] as String? ?? '';
          _reference = data['reference'] as String? ?? '';
          _expiresAt = data['expiresAt'] as String?;

          // Decode base64 QR image
          final qrBase64 = data['qrCodeBase64'] as String? ?? '';
          if (qrBase64.isNotEmpty) {
            final base64Str = qrBase64.contains(',')
                ? qrBase64.split(',').last
                : qrBase64;
            _qrCodeImage = base64Decode(base64Str);
          }
        });

        // Start listening for status
        _startListeningPaymentStatus();
      } else {
        setState(() {
          _errorMessage = 'Erro ao gerar PIX. Tente novamente.';
        });
      }
    } catch (e) {
      setState(() {
        _errorMessage = 'Erro inesperado: $e';
      });
    } finally {
      setState(() {
        _isLoadingQr = false;
      });
    }
  }

  void _startListeningPaymentStatus() {
    setState(() => _isCheckingStatus = true);
    _pixSubscription = Supabase.instance.client
        .from('pix_payments')
        .stream(primaryKey: ['id'])
        .eq('mp_payment_id', _reference)
        .listen((events) {
          if (events.isNotEmpty) {
            final record = events.first;
            final status = record['status']?.toString();
            if (status == 'approved') {
              _pixSubscription?.cancel();
              if (mounted) {
                setState(() {
                  _paymentApproved = true;
                  _isCheckingStatus = false;
                });
                Future.delayed(const Duration(seconds: 2), () {
                  if (mounted) {
                    context.router.maybePop(true);
                  }
                });
              }
            } else if (status == 'failed' || status == 'refunded') {
              _pixSubscription?.cancel();
              if (mounted) {
                setState(() {
                  _errorMessage = 'Pagamento não aprovado. Tente novamente.';
                  _isCheckingStatus = false;
                });
              }
            }
          }
        }, onError: (e) {
          debugPrint('Erro na escuta Pix: $e');
        });
  }

  void _copyPixCode() {
    if (_qrCode.isEmpty) return;
    Clipboard.setData(ClipboardData(text: _qrCode));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Row(
          children: [
            Icon(Icons.check_circle, color: Colors.white, size: 20),
            SizedBox(width: 8),
            Text('Código PIX copiado!'),
          ],
        ),
        backgroundColor: ColorPalette.semanticgreen50,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      child: Container(
        constraints: const BoxConstraints(maxWidth: 420),
        decoration: BoxDecoration(
          color: ColorPalette.neutral100,
          borderRadius: BorderRadius.circular(24),
          boxShadow: [
            BoxShadow(
              color: ColorPalette.primary40.withOpacity(0.15),
              blurRadius: 32,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildHeader(),
              if (_paymentApproved)
                _buildSuccessView()
              else if (_qrGenerated)
                _buildQrCodeView()
              else
                _buildFormView(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.fromLTRB(24, 20, 16, 16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [ColorPalette.primary40, ColorPalette.primary50],
        ),
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(24),
          topRight: Radius.circular(24),
        ),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.2),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(Icons.pix, color: Colors.white, size: 24),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Pagamento PIX',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'R\$ ${widget.amount.toStringAsFixed(2).replaceAll('.', ',')}',
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.9),
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            onPressed: () => context.router.maybePop(false),
            icon: const Icon(Icons.close, color: Colors.white),
          ),
        ],
      ),
    );
  }

  Widget _buildFormView() {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Confirme seus dados para gerar o PIX',
              style: TextStyle(color: ColorPalette.neutral40, fontSize: 14),
            ),
            const SizedBox(height: 20),
            _buildTextField(
              controller: _nameController,
              label: 'Nome completo',
              icon: Icons.person_outline,
              validator: (v) =>
                  (v == null || v.trim().isEmpty) ? 'Informe seu nome' : null,
            ),
            const SizedBox(height: 12),
            _buildTextField(
              controller: _emailController,
              label: 'E-mail',
              icon: Icons.email_outlined,
              keyboardType: TextInputType.emailAddress,
              validator: (v) =>
                  (v == null || !v.contains('@')) ? 'E-mail inválido' : null,
            ),
            const SizedBox(height: 12),
            _buildTextField(
              controller: _cpfController,
              label: 'CPF',
              icon: Icons.badge_outlined,
              keyboardType: TextInputType.number,
              inputFormatters: [
                FilteringTextInputFormatter.digitsOnly,
                LengthLimitingTextInputFormatter(11),
              ],
              validator: (v) =>
                  (v == null || v.replaceAll(RegExp(r'\D'), '').length != 11)
                  ? 'CPF inválido (11 dígitos)'
                  : null,
            ),
            const SizedBox(height: 12),
            _buildTextField(
              controller: _phoneController,
              label: 'Telefone (com DDD)',
              icon: Icons.phone_outlined,
              keyboardType: TextInputType.phone,
              inputFormatters: [
                FilteringTextInputFormatter.digitsOnly,
                LengthLimitingTextInputFormatter(11),
              ],
              validator: (v) =>
                  (v == null || v.replaceAll(RegExp(r'\D'), '').length < 10)
                  ? 'Telefone inválido'
                  : null,
            ),
            if (_errorMessage != null) ...[
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  color: ColorPalette.error95,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: ColorPalette.error60.withOpacity(0.3),
                  ),
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.error_outline,
                      color: ColorPalette.error40,
                      size: 20,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _errorMessage!,
                        style: const TextStyle(
                          color: ColorPalette.error40,
                          fontSize: 13,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 24),
            SizedBox(
              height: 52,
              child: ElevatedButton(
                onPressed: _isLoadingQr ? null : _generatePixQrCode,
                style: ElevatedButton.styleFrom(
                  backgroundColor: ColorPalette.primary40,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                  elevation: 0,
                ),
                child: _isLoadingQr
                    ? const SizedBox(
                        height: 22,
                        width: 22,
                        child: CircularProgressIndicator(
                          color: Colors.white,
                          strokeWidth: 2.5,
                        ),
                      )
                    : const Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.qr_code_2, size: 22),
                          SizedBox(width: 8),
                          Text(
                            'Gerar QR Code PIX',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    TextInputType? keyboardType,
    List<TextInputFormatter>? inputFormatters,
    String? Function(String?)? validator,
  }) {
    return TextFormField(
      controller: controller,
      keyboardType: keyboardType,
      inputFormatters: inputFormatters,
      validator: validator,
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: Icon(icon, color: ColorPalette.neutral60, size: 20),
        filled: true,
        fillColor: ColorPalette.neutral95,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(
            color: ColorPalette.primary50,
            width: 1.5,
          ),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: ColorPalette.error40, width: 1),
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 14,
        ),
      ),
    );
  }

  Widget _buildQrCodeView() {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        children: [
          // QR Code Image
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: ColorPalette.primary95, width: 2),
              boxShadow: [
                BoxShadow(
                  color: ColorPalette.primary40.withOpacity(0.08),
                  blurRadius: 16,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: _qrCodeImage != null
                ? Image.memory(
                    _qrCodeImage!,
                    width: 220,
                    height: 220,
                    fit: BoxFit.contain,
                  )
                : const SizedBox(
                    width: 220,
                    height: 220,
                    child: Center(
                      child: Icon(
                        Icons.qr_code_2,
                        size: 120,
                        color: ColorPalette.neutral80,
                      ),
                    ),
                  ),
          ),

          const SizedBox(height: 16),

          // Status indicator
          AnimatedBuilder(
            animation: _pulseAnimation,
            builder: (context, child) {
              return Transform.scale(
                scale: _isCheckingStatus ? _pulseAnimation.value : 1.0,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    color: ColorPalette.secondary99,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: ColorPalette.secondary70,
                      width: 1,
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: ColorPalette.secondary50,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'Aguardando pagamento...',
                        style: TextStyle(
                          color: ColorPalette.secondary40,
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),

          const SizedBox(height: 20),

          // Copy PIX code button
          if (_qrCode.isNotEmpty)
            SizedBox(
              width: double.infinity,
              height: 48,
              child: OutlinedButton.icon(
                onPressed: _copyPixCode,
                icon: const Icon(Icons.copy, size: 18),
                label: const Text(
                  'Copiar código PIX',
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
                style: OutlinedButton.styleFrom(
                  foregroundColor: ColorPalette.primary40,
                  side: const BorderSide(color: ColorPalette.primary80),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ),

          const SizedBox(height: 12),

          // Instructions
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: ColorPalette.neutral95,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              children: [
                _buildInstruction('1', 'Abra o app do seu banco'),
                const SizedBox(height: 8),
                _buildInstruction('2', 'Escolha pagar via PIX'),
                const SizedBox(height: 8),
                _buildInstruction(
                  '3',
                  'Escaneie o QR Code ou cole o código copiado',
                ),
                const SizedBox(height: 8),
                _buildInstruction(
                  '4',
                  'Confirme o pagamento. O saldo atualiza na hora!',
                ),
              ],
            ),
          ),

          if (_expiresAt != null) ...[
            const SizedBox(height: 12),
            Text(
              'Expira em: $_expiresAt',
              style: TextStyle(color: ColorPalette.neutral60, fontSize: 12),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildInstruction(String number, String text) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 22,
          height: 22,
          decoration: BoxDecoration(
            color: ColorPalette.primary40,
            shape: BoxShape.circle,
          ),
          child: Center(
            child: Text(
              number,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            text,
            style: TextStyle(
              color: ColorPalette.neutral40,
              fontSize: 13,
              height: 1.3,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildSuccessView() {
    return Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        children: [
          ScaleTransition(
            scale: _pulseAnimation,
            child: Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                color: ColorPalette.semanticgreen60,
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: ColorPalette.semanticgreen50.withOpacity(0.3),
                    blurRadius: 24,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: const Icon(
                Icons.check_rounded,
                color: Colors.white,
                size: 48,
              ),
            ),
          ),
          const SizedBox(height: 20),
          const Text(
            'Pagamento Confirmado!',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w700,
              color: ColorPalette.neutral20,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'R\$ ${widget.amount.toStringAsFixed(2).replaceAll('.', ',')} adicionado à sua carteira',
            style: TextStyle(fontSize: 14, color: ColorPalette.neutral50),
          ),
          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            height: 48,
            child: ElevatedButton(
              onPressed: () => context.router.maybePop(true),
              style: ElevatedButton.styleFrom(
                backgroundColor: ColorPalette.semanticgreen60,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
                elevation: 0,
              ),
              child: const Text(
                'Fechar',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
              ),
            ),
          ),
        ],
      ),
    );
  }
}


