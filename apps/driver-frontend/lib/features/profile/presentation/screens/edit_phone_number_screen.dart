import 'dart:async';
import 'package:auto_route/auto_route.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter_common/core/color_palette/color_palette.dart';
import 'package:flutter_common/core/utils/friendly_error.dart';
import 'package:flutter_common/core/utils/uppi_haptics.dart';
import 'package:flutter_common/core/presentation/responsive_dialog/app_top_bar.dart';
import 'package:uppi_motorista/core/extensions/extensions.dart';

enum _PhoneEditStep { enterPhone, verifyOtp }

@RoutePage(name: 'DriverEditPhoneNumberRoute')
class EditPhoneNumberScreen extends StatefulWidget {
  const EditPhoneNumberScreen({super.key});

  @override
  State<EditPhoneNumberScreen> createState() => _EditPhoneNumberScreenState();
}

class _EditPhoneNumberScreenState extends State<EditPhoneNumberScreen>
    with TickerProviderStateMixin {
  _PhoneEditStep _step = _PhoneEditStep.enterPhone;

  final _phoneController = TextEditingController();
  final _otpController = TextEditingController();
  final _phoneFocus = FocusNode();
  final _otpFocus = FocusNode();

  bool _loading = false;
  String? _errorMessage;

  // Timer de reenvio
  Timer? _resendTimer;
  int _resendCooldown = 0;

  // Animação de transição de passo
  late AnimationController _slideController;
  late Animation<Offset> _slideAnimation;
  late Animation<double> _fadeAnimation;

  @override
  void initState() {
    super.initState();
    _slideController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );
    _slideAnimation = Tween<Offset>(
      begin: const Offset(0.15, 0),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _slideController, curve: Curves.easeOutCubic));
    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0)
        .animate(CurvedAnimation(parent: _slideController, curve: Curves.easeOut));
    _slideController.forward();
  }

  @override
  void dispose() {
    _phoneController.dispose();
    _otpController.dispose();
    _phoneFocus.dispose();
    _otpFocus.dispose();
    _resendTimer?.cancel();
    _slideController.dispose();
    super.dispose();
  }

  void _startResendTimer() {
    _resendCooldown = 60;
    _resendTimer?.cancel();
    _resendTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) { timer.cancel(); return; }
      setState(() {
        _resendCooldown--;
        if (_resendCooldown <= 0) timer.cancel();
      });
    });
  }

  Future<void> _sendOtp() async {
    final phone = _phoneController.text.trim();
    if (phone.isEmpty) {
      UppiHaptics.errorAlert();
      setState(() => _errorMessage = 'Digite o número de celular.');
      return;
    }

    setState(() { _loading = true; _errorMessage = null; });
    try {
      await Supabase.instance.client.auth.updateUser(
        UserAttributes(phone: phone),
      );

      UppiHaptics.mechanicalClick();

      // Animação de transição
      await _slideController.reverse();
      setState(() { _step = _PhoneEditStep.verifyOtp; });
      _slideController.forward();
      _startResendTimer();

      WidgetsBinding.instance.addPostFrameCallback((_) {
        _otpFocus.requestFocus();
      });
    } on AuthException catch (e) {
      UppiHaptics.errorAlert();
      setState(() => _errorMessage = _translateError(e.message));
    } catch (e) {
      UppiHaptics.errorAlert();
      setState(() => _errorMessage = 'Erro ao enviar SMS. Tente novamente.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _verifyOtp() async {
    final otp = _otpController.text.trim();
    if (otp.length < 6) {
      UppiHaptics.errorAlert();
      setState(() => _errorMessage = 'Digite o código de 6 dígitos.');
      return;
    }

    setState(() { _loading = true; _errorMessage = null; });
    try {
      await Supabase.instance.client.auth.verifyOTP(
        phone: _phoneController.text.trim(),
        token: otp,
        type: OtpType.phoneChange,
      );

      UppiHaptics.successWave();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Row(children: [
              Icon(Icons.check_circle_rounded, color: Colors.white),
              SizedBox(width: 12),
              Text('Número de celular atualizado com sucesso!',
                  style: TextStyle(color: Colors.white)),
            ]),
            backgroundColor: ColorPalette.primary40,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
        );
        context.router.maybePop();
      }
    } on AuthException catch (e) {
      UppiHaptics.errorAlert();
      setState(() => _errorMessage = _translateError(e.message));
    } catch (e) {
      UppiHaptics.errorAlert();
      setState(() => _errorMessage = 'Código inválido ou expirado.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  String _translateError(String error) {
    if (error.contains('Invalid') || error.contains('invalid')) return 'Código inválido ou expirado.';
    if (error.contains('rate limit') || error.contains('Too many')) return 'Muitas tentativas. Aguarde antes de tentar novamente.';
    if (error.contains('Phone number format')) return 'Formato inválido. Use +55 DDD + número.';
    return friendlyErrorMessage(error);
  }

  Future<void> _goBack() async {
    if (_step == _PhoneEditStep.verifyOtp) {
      await _slideController.reverse();
      setState(() {
        _step = _PhoneEditStep.enterPhone;
        _otpController.clear();
        _errorMessage = null;
        _resendTimer?.cancel();
        _resendCooldown = 0;
      });
      _slideController.forward();
    } else {
      context.router.maybePop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Scaffold(
      backgroundColor: colorScheme.surface,
      body: SafeArea(
        child: Column(
          children: [
            // ── AppBar ──
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 8, 16, 0),
              child: Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.arrow_back_ios_new_rounded),
                    onPressed: _loading ? null : _goBack,
                    color: colorScheme.onSurface,
                  ),
                  Expanded(
                    child: AppTopBar(title: context.translate.mobileNumber),
                  ),
                ],
              ),
            ),

            // ── Indicador de progresso (2 etapas) ──
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 20, 24, 0),
              child: Row(
                children: List.generate(2, (index) {
                  final isActive = index <= _step.index;
                  return Expanded(
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 300),
                      height: 4,
                      margin: EdgeInsets.only(right: index < 1 ? 8 : 0),
                      decoration: BoxDecoration(
                        color: isActive
                            ? colorScheme.primary
                            : colorScheme.onSurface.withOpacity(0.12),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  );
                }),
              ),
            ),

            Expanded(
              child: AnimatedBuilder(
                animation: _slideController,
                builder: (context, child) => FadeTransition(
                  opacity: _fadeAnimation,
                  child: SlideTransition(position: _slideAnimation, child: child),
                ),
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(24, 40, 24, 24),
                  child: _step == _PhoneEditStep.enterPhone
                      ? _buildEnterPhoneStep(colorScheme)
                      : _buildVerifyOtpStep(colorScheme),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEnterPhoneStep(ColorScheme colorScheme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 64, height: 64,
          decoration: BoxDecoration(
            color: colorScheme.primary.withOpacity(0.1),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Icon(Icons.phone_android_rounded, color: colorScheme.primary, size: 32),
        ),
        const SizedBox(height: 24),
        Text(
          'Novo número de celular',
          style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        Text(
          'Informe o novo número para sua conta de motorista. Um código SMS será enviado para confirmar.',
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
            color: colorScheme.onSurface.withOpacity(0.6),
          ),
        ),
        const SizedBox(height: 40),
        Text(
          'NÚMERO DE CELULAR',
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
            color: colorScheme.onSurface.withOpacity(0.5),
            fontWeight: FontWeight.bold,
            letterSpacing: 1.2,
          ),
        ),
        const SizedBox(height: 8),
        TextFormField(
          controller: _phoneController,
          focusNode: _phoneFocus,
          keyboardType: TextInputType.phone,
          inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[+\d]'))],
          autofocus: true,
          onFieldSubmitted: (_) => _loading ? null : _sendOtp(),
          style: Theme.of(context).textTheme.titleMedium,
          decoration: InputDecoration(
            hintText: '+55 11 99999-0000',
            prefixIcon: Icon(Icons.phone_rounded, color: colorScheme.primary),
            filled: true,
            fillColor: colorScheme.onSurface.withOpacity(0.05),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: colorScheme.outline),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: colorScheme.primary, width: 2),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: colorScheme.outline.withOpacity(0.4)),
            ),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'Use o formato internacional: +55 11 99999-0000',
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: colorScheme.onSurface.withOpacity(0.4),
          ),
        ),
        if (_errorMessage != null) ...[
          const SizedBox(height: 16),
          _buildErrorBox(colorScheme),
        ],
        const SizedBox(height: 40),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            onPressed: _loading ? null : _sendOtp,
            style: ElevatedButton.styleFrom(
              backgroundColor: colorScheme.primary,
              foregroundColor: colorScheme.onPrimary,
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              elevation: 0,
            ),
            child: _loading
                ? SizedBox(
                    height: 20, width: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.5,
                      valueColor: AlwaysStoppedAnimation<Color>(colorScheme.onPrimary),
                    ),
                  )
                : const Text('Enviar Código SMS',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          ),
        ),
      ],
    );
  }

  Widget _buildVerifyOtpStep(ColorScheme colorScheme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 64, height: 64,
          decoration: BoxDecoration(
            color: colorScheme.tertiary.withOpacity(0.1),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Icon(Icons.sms_rounded, color: colorScheme.tertiary, size: 32),
        ),
        const SizedBox(height: 24),
        Text(
          'Verificar código SMS',
          style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        RichText(
          text: TextSpan(
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: colorScheme.onSurface.withOpacity(0.6),
            ),
            children: [
              const TextSpan(text: 'Enviamos um código de 6 dígitos para '),
              TextSpan(
                text: _phoneController.text.trim(),
                style: TextStyle(color: colorScheme.primary, fontWeight: FontWeight.bold),
              ),
            ],
          ),
        ),
        const SizedBox(height: 40),
        Text(
          'CÓDIGO DE VERIFICAÇÃO',
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
            color: colorScheme.onSurface.withOpacity(0.5),
            fontWeight: FontWeight.bold,
            letterSpacing: 1.2,
          ),
        ),
        const SizedBox(height: 12),
        TextFormField(
          controller: _otpController,
          focusNode: _otpFocus,
          keyboardType: TextInputType.number,
          inputFormatters: [
            FilteringTextInputFormatter.digitsOnly,
            LengthLimitingTextInputFormatter(6),
          ],
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.headlineMedium?.copyWith(
            fontWeight: FontWeight.bold,
            letterSpacing: 12,
          ),
          onChanged: (v) {
            if (v.length == 6 && !_loading) _verifyOtp();
          },
          decoration: InputDecoration(
            hintText: '• • • • • •',
            hintStyle: TextStyle(
              letterSpacing: 12,
              color: colorScheme.onSurface.withOpacity(0.3),
              fontSize: 28,
            ),
            filled: true,
            fillColor: colorScheme.onSurface.withOpacity(0.05),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: colorScheme.outline),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: colorScheme.primary, width: 2),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: colorScheme.outline.withOpacity(0.4)),
            ),
            contentPadding: const EdgeInsets.symmetric(vertical: 20, horizontal: 16),
          ),
        ),
        if (_errorMessage != null) ...[
          const SizedBox(height: 16),
          _buildErrorBox(colorScheme),
        ],
        const SizedBox(height: 32),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            onPressed: _loading ? null : _verifyOtp,
            style: ElevatedButton.styleFrom(
              backgroundColor: colorScheme.primary,
              foregroundColor: colorScheme.onPrimary,
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              elevation: 0,
            ),
            child: _loading
                ? SizedBox(
                    height: 20, width: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.5,
                      valueColor: AlwaysStoppedAnimation<Color>(colorScheme.onPrimary),
                    ),
                  )
                : const Text('Verificar Código',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          ),
        ),
        const SizedBox(height: 20),
        Center(
          child: _resendCooldown > 0
              ? Text(
                  'Reenviar código em ${_resendCooldown}s',
                  style: TextStyle(
                    color: colorScheme.onSurface.withOpacity(0.4),
                    fontSize: 14,
                  ),
                )
              : TextButton.icon(
                  onPressed: _loading ? null : _sendOtp,
                  icon: const Icon(Icons.refresh_rounded, size: 18),
                  label: const Text('Reenviar código SMS'),
                  style: TextButton.styleFrom(foregroundColor: colorScheme.primary),
                ),
        ),
      ],
    );
  }

  Widget _buildErrorBox(ColorScheme colorScheme) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colorScheme.error.withOpacity(0.1),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: colorScheme.error.withOpacity(0.3)),
      ),
      child: Row(
        children: [
          Icon(Icons.error_outline_rounded, color: colorScheme.error, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Text(_errorMessage!,
                style: TextStyle(color: colorScheme.error, fontSize: 13)),
          ),
        ],
      ),
    );
  }
}
