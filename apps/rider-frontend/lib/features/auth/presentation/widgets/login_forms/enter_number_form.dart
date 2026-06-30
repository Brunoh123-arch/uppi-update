import 'package:flutter/gestures.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:flutter_common/features/lgpd/domain/lgpd_consent.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter/foundation.dart' show kIsWeb, kDebugMode, defaultTargetPlatform, TargetPlatform;
import 'package:flutter/material.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_common/core/color_palette/color_palette.dart';
import 'package:flutter_common/core/presentation/snackbar/snackbar.dart';
import 'package:flutter_common/features/country_code_dialog/country_code.dart';
import 'package:rider_flutter/config/locator/locator.dart';
import 'package:rider_flutter/core/extensions/extensions.dart';
import 'package:flutter_common/core/presentation/buttons/app_text_button.dart';
import 'package:rider_flutter/features/auth/presentation/blocs/login.dart';
import 'package:rider_flutter/features/auth/presentation/blocs/onboarding_cubit.dart';
import 'package:rider_flutter/core/entities/profile.dart';

class EnterNumberForm extends StatefulWidget {
  const EnterNumberForm({super.key});

  @override
  State<EnterNumberForm> createState() => _EnterNumberFormState();
}

class _EnterNumberFormState extends State<EnterNumberForm> {
  bool _googleLoading = false;
  final bool _phoneLoading = false;
  final _phoneController = TextEditingController();
  String _countryCode = '+55';

  @override
  void dispose() {
    _phoneController.dispose();
    super.dispose();
  }

  void _showPhoneBottomSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: context.theme.colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModalState) => Padding(
          padding: EdgeInsets.only(
            left: 24,
            right: 24,
            top: 24,
            bottom: MediaQuery.of(ctx).viewInsets.bottom + 32,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Handle
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 24),
                  decoration: BoxDecoration(
                    color: context.theme.colorScheme.onSurfaceVariant.withOpacity(0.3),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              Text(
                'Continuar com Telefone',
                style: context.titleLarge?.copyWith(fontWeight: FontWeight.w700),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              // Código de país + campo telefone
              Row(
                children: [
                  GestureDetector(
                    onTap: () async {
                      final picked = await showDialog<CountryCode>(
                        context: ctx,
                        builder: (_) => const AppCountryCodeListDialog(),
                      );
                      if (picked != null) {
                        setModalState(() => _countryCode = '+${picked.e164CC}');
                        setState(() => _countryCode = '+${picked.e164CC}');
                      }
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                      decoration: BoxDecoration(
                        border: Border.all(
                          color: context.theme.colorScheme.onSurfaceVariant.withOpacity(0.3),
                        ),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        children: [
                          Text(_countryCode, style: context.bodyMedium?.copyWith(fontWeight: FontWeight.w600)),
                          const SizedBox(width: 4),
                          const Icon(Icons.arrow_drop_down, size: 18),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextField(
                      controller: _phoneController,
                      keyboardType: TextInputType.phone,
                      autofocus: true,
                      decoration: InputDecoration(
                        hintText: 'Número de telefone',
                        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(color: context.theme.colorScheme.onSurfaceVariant.withOpacity(0.3)),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(color: context.colorScheme.primary),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              SizedBox(
                height: 52,
                child: ElevatedButton(
                  onPressed: _phoneLoading ? null : () {
                    final phone = _phoneController.text.trim();
                    if (phone.isEmpty) return;
                    Navigator.pop(ctx);
                    locator<LoginBloc>().onNumberVerificationRequested(
                      mobileNumber: phone,
                      countryCode: _countryCode,
                    );
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: context.colorScheme.primary,
                    foregroundColor: context.colorScheme.onPrimary,
                    elevation: 0,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  child: _phoneLoading
                    ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Text('Enviar Código', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _handleGoogleSignIn() async {
    setState(() => _googleLoading = true);
    try {
      if (kIsWeb) {
        await Supabase.instance.client.auth.signInWithOAuth(
          OAuthProvider.google,
          redirectTo: Uri.base.origin,
        );
      } else {
        const webClientId = '408478040204-2goc9kfqm9sadcci2ue5gkculo21tiif.apps.googleusercontent.com';
        
        final googleSignIn = GoogleSignIn.instance;
        await googleSignIn.initialize(serverClientId: webClientId);
        
        final googleUser = await googleSignIn.authenticate();

        final googleAuth = googleUser.authentication;
        final idToken = googleAuth.idToken;

        if (idToken == null) {
          throw 'Credenciais não encontradas.';
        }

        final authResponse = await Supabase.instance.client.auth.signInWithIdToken(
          provider: OAuthProvider.google,
          idToken: idToken,
        );

        final user = authResponse.user;
        if (user != null && mounted) {
          final fullName = user.userMetadata?['full_name'] as String? ?? googleUser.displayName ?? '';
          
          // UPPI BRASIL: Garante a criação/sincronização do perfil no banco de dados Supabase.
          try {
            await Supabase.instance.client.functions.invoke(
              'sync-profile',
              body: {
                'full_name': fullName,
                'email': user.email ?? googleUser.email ?? '',
                'gender': 'unknown',
              },
            );
          } catch (e) {
            debugPrint('[GoogleSignIn] Erro ao sincronizar perfil: $e');
          }

          final parts = fullName.split(' ');
          final firstName = parts.first;
          final lastName = parts.length > 1 ? parts.skip(1).join(' ') : '';
          
          locator<LoginBloc>().onGoogleSignInSuccess(
            ProfileEntity(
              firstName: firstName,
              lastName: lastName,
              countryCode: null,
              email: user.email ?? googleUser.email ?? '',
              gender: null,
              profileImage: null,
              presetProfileImage: null,
              number: '',
              idNumber: null,
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        context.showSnackBar(message: e.toString());
      }
    } finally {
      if (mounted) setState(() => _googleLoading = false);
    }
  }

  Future<void> _handleAppleSignIn() async {
    setState(() => _googleLoading = true);
    try {
      if (kIsWeb) {
        await Supabase.instance.client.auth.signInWithOAuth(
          OAuthProvider.apple,
          redirectTo: Uri.base.origin,
        );
      } else {
        await Supabase.instance.client.auth.signInWithOAuth(
          OAuthProvider.apple,
        );
        final session = Supabase.instance.client.auth.currentSession;
        final user = session?.user;
        if (user != null && mounted) {
          final fullName = user.userMetadata?['full_name'] as String? ?? '';
          final parts = fullName.split(' ');
          final firstName = parts.first;
          final lastName = parts.length > 1 ? parts.skip(1).join(' ') : '';
          
          locator<LoginBloc>().onGoogleSignInSuccess(
            ProfileEntity(
              firstName: firstName.isNotEmpty ? firstName : 'Passageiro',
              lastName: lastName,
              countryCode: null,
              email: user.email ?? '',
              gender: null,
              profileImage: null,
              presetProfileImage: null,
              number: '',
              idNumber: null,
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        context.showErrorSnackBar(e, fallback: 'Não foi possível entrar com a Apple. Tente novamente.');
      }
    } finally {
      if (mounted) setState(() => _googleLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return BlocConsumer<LoginBloc, LoginState>(
      listener: (context, state) {
        state.loginPage.mapOrNull(enterNumber: (enterNumber) {
          enterNumber.state.mapOrNull(error: (error) {
            context.showErrorSnackBar(error.errorMessage);
          });
        });
      },
      builder: (context, state) => state.loginPage.maybeMap(
        orElse: () => const SizedBox(),
        enterNumber: (enterNumber) => Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            // Ícone Original
            Center(
              child: Container(
                margin: const EdgeInsets.only(bottom: 24),
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: context.colorScheme.primary.withOpacity(0.08),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.mobile_friendly_rounded,
                  size: 48,
                  color: context.colorScheme.primary,
                ),
              ),
            ),
            
            // Título Original
            Text(
              context.translate.signInSignUp,
              style: context.titleLarge?.copyWith(
                fontWeight: FontWeight.w800,
                fontSize: 28,
                letterSpacing: -0.5,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
            
            // Subtítulo Original
            Text(
              context.translate.onboardingDescription,
              style: context.bodyMedium?.copyWith(
                color: context.theme.colorScheme.onSurfaceVariant.withOpacity(0.8),
                height: 1.5,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 32),
            
            // OU Divider (separador entre Google e Telefone)
            Row(
              children: [
                Expanded(child: Divider(color: context.theme.colorScheme.onSurfaceVariant.withOpacity(0.2))),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Text(
                    "ou",
                    style: context.bodySmall?.copyWith(color: context.theme.colorScheme.onSurfaceVariant),
                  ),
                ),
                Expanded(child: Divider(color: context.theme.colorScheme.onSurfaceVariant.withOpacity(0.2))),
              ],
            ),
            const SizedBox(height: 24),
            
            // Botão Original do Google / Apple no iOS
            if (defaultTargetPlatform == TargetPlatform.iOS)
              _SocialLoginButton(
                onPressed: _googleLoading ? null : _handleAppleSignIn,
                backgroundColor: Colors.black,
                borderColor: Colors.transparent,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.05),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ],
                icon: _googleLoading
                    ? const SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                      )
                    : const Icon(Icons.apple, color: Colors.white, size: 24),
                label: _googleLoading ? 'Entrando...' : 'Continuar com Apple',
                labelColor: Colors.white,
              )
            else
              _SocialLoginButton(
                onPressed: _googleLoading ? null : _handleGoogleSignIn,
                backgroundColor: Colors.white,
                borderColor: Colors.transparent,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.05),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ],
                icon: _googleLoading
                    ? const SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : _GoogleIcon(),
                label: _googleLoading ? 'Entrando...' : 'Continuar com Google',
                labelColor: ColorPalette.neutral20,
              ),
            const SizedBox(height: 12),
            
            // Botão de Telefone — abre bottom sheet para inserir número
            _SocialLoginButton(
              onPressed: () => _showPhoneBottomSheet(context),
              backgroundColor: Colors.white,
              borderColor: Colors.transparent,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.05),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ],
              icon: Icon(Icons.phone_outlined, color: ColorPalette.neutral20, size: 22),
              label: 'Continuar com Telefone',
              labelColor: ColorPalette.neutral20,
            ),
            const SizedBox(height: 16),
            
            // Termos e Privacidade (Botão Profissional)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: RichText(
                textAlign: TextAlign.center,
                text: TextSpan(
                  style: TextStyle(
                    color: context.theme.colorScheme.onSurfaceVariant.withOpacity(0.8),
                    height: 1.4,
                    fontSize: 12,
                  ),
                  children: [
                    const TextSpan(
                      text: 'Ao continuar, você concorda com nossos ',
                    ),
                    TextSpan(
                      text: 'Termos de Uso',
                      style: TextStyle(
                        color: context.colorScheme.primary,
                        fontWeight: FontWeight.w600,
                        decoration: TextDecoration.underline,
                      ),
                      recognizer: TapGestureRecognizer()
                        ..onTap = () async {
                          final uri = Uri.parse(LgpdConsent.termsOfServiceUrl);
                          if (await canLaunchUrl(uri)) {
                            await launchUrl(uri, mode: LaunchMode.externalApplication);
                          }
                        },
                    ),
                    const TextSpan(text: ' e '),
                    TextSpan(
                      text: 'Política de Privacidade',
                      style: TextStyle(
                        color: context.colorScheme.primary,
                        fontWeight: FontWeight.w600,
                        decoration: TextDecoration.underline,
                      ),
                      recognizer: TapGestureRecognizer()
                        ..onTap = () async {
                          final uri = Uri.parse(LgpdConsent.privacyPolicyUrl);
                          if (await canLaunchUrl(uri)) {
                            await launchUrl(uri, mode: LaunchMode.externalApplication);
                          }
                        },
                    ),
                    const TextSpan(text: '.'),
                  ],
                ),
              ),
            ),
                          const SizedBox(height: 12),
             
             // Botão Pular Original
            AppTextButton(
              text: context.translate.skipForNow,
              onPressed: () {
                locator<OnboardingCubit>().skip();
                locator<LoginBloc>().onVerificationSkipped();
              },
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Social Login Button ─────────────────────────────────────────────────────

class _SocialLoginButton extends StatelessWidget {
  final VoidCallback? onPressed;
  final Color backgroundColor;
  final Color borderColor;
  final List<BoxShadow>? boxShadow;
  final Widget icon;
  final String label;
  final Color labelColor;

  const _SocialLoginButton({
    required this.onPressed,
    required this.backgroundColor,
    required this.borderColor,
    this.boxShadow,
    required this.icon,
    required this.label,
    required this.labelColor,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      height: 56,
      decoration: BoxDecoration(
        boxShadow: boxShadow,
        borderRadius: BorderRadius.circular(16),
      ),
      child: OutlinedButton(
        onPressed: onPressed,
        style: OutlinedButton.styleFrom(
          backgroundColor: backgroundColor,
          side: BorderSide(color: borderColor, width: 1),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 16),
          elevation: 0,
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            icon,
            const SizedBox(width: 14),
            Text(
              label,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: labelColor,
                letterSpacing: -0.3,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Google "G" Icon (Official Colors) ───────────────────────────────────────

class _GoogleIcon extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 22,
      height: 22,
      child: CustomPaint(
        painter: _GoogleLogoPainter(),
      ),
    );
  }
}

class _GoogleLogoPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final double w = size.width;
    final double h = size.height;
    final double cx = w / 2;
    final double cy = h / 2;
    final double r = w * 0.45;

    // Blue arc (top-right)
    final bluePaint = Paint()
      ..color = const Color(0xFF4285F4)
      ..style = PaintingStyle.stroke
      ..strokeWidth = w * 0.18
      ..strokeCap = StrokeCap.butt;
    canvas.drawArc(
      Rect.fromCircle(center: Offset(cx, cy), radius: r),
      -0.6,
      1.8,
      false,
      bluePaint,
    );

    // Green arc (bottom-right)
    final greenPaint = Paint()
      ..color = const Color(0xFF34A853)
      ..style = PaintingStyle.stroke
      ..strokeWidth = w * 0.18
      ..strokeCap = StrokeCap.butt;
    canvas.drawArc(
      Rect.fromCircle(center: Offset(cx, cy), radius: r),
      1.2,
      1.2,
      false,
      greenPaint,
    );

    // Yellow arc (bottom-left)
    final yellowPaint = Paint()
      ..color = const Color(0xFFFBBC05)
      ..style = PaintingStyle.stroke
      ..strokeWidth = w * 0.18
      ..strokeCap = StrokeCap.butt;
    canvas.drawArc(
      Rect.fromCircle(center: Offset(cx, cy), radius: r),
      2.4,
      1.0,
      false,
      yellowPaint,
    );

    // Red arc (top-left)
    final redPaint = Paint()
      ..color = const Color(0xFFEA4335)
      ..style = PaintingStyle.stroke
      ..strokeWidth = w * 0.18
      ..strokeCap = StrokeCap.butt;
    canvas.drawArc(
      Rect.fromCircle(center: Offset(cx, cy), radius: r),
      3.4,
      1.6,
      false,
      redPaint,
    );

    // Horizontal bar of the "G"
    final barPaint = Paint()
      ..color = const Color(0xFF4285F4)
      ..style = PaintingStyle.fill;
    canvas.drawRect(
      Rect.fromLTWH(cx, cy - w * 0.08, r + w * 0.05, w * 0.16),
      barPaint,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
