import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter/foundation.dart' show kIsWeb, kDebugMode, defaultTargetPlatform, TargetPlatform;
import 'package:flutter/material.dart';
import 'package:google_sign_in/google_sign_in.dart' as google_sign_in;
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter/gestures.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:flutter_common/core/color_palette/color_palette.dart';
import 'package:flutter_common/core/presentation/snackbar/snackbar.dart';
import 'package:flutter_common/features/lgpd/domain/lgpd_consent.dart';
import 'package:uppi_motorista/config/locator/locator.dart';
import 'package:uppi_motorista/core/extensions/extensions.dart';
import 'package:uppi_motorista/features/auth/presentation/blocs/login.dart';


class EnterNumberForm extends StatefulWidget {
  final LoginState state;

  const EnterNumberForm({super.key, required this.state});

  @override
  State<EnterNumberForm> createState() => _EnterNumberFormState();
}

class _EnterNumberFormState extends State<EnterNumberForm> {
  final GlobalKey<FormState> formKey = GlobalKey();
  bool _googleLoading = false;

  Future<void> _handleGoogleSignIn(bool isSignUp) async {
    setState(() => _googleLoading = true);
    try {
      if (kIsWeb) {
        await Supabase.instance.client.auth.signInWithOAuth(
          OAuthProvider.google,
          redirectTo: Uri.base.origin,
        );
      } else {
        const webClientId = '408478040204-2goc9kfqm9sadcci2ue5gkculo21tiif.apps.googleusercontent.com';
        
        final googleSignIn = google_sign_in.GoogleSignIn.instance;
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
          locator<LoginBloc>().onGoogleSignInSuccess(user.id, isSignUp: isSignUp);
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

  Future<void> _handleAppleSignIn(bool isSignUp) async {
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
          locator<LoginBloc>().onGoogleSignInSuccess(user.id, isSignUp: isSignUp);
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
    return BlocBuilder<LoginBloc, LoginState>(
      builder: (context, state) => state.loginPage.maybeMap(
        orElse: () => const SizedBox(),
        enterNumber: (enterNumber) => Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: SingleChildScrollView(
                child: Form(
                  key: formKey,
                  child: Column(
                    children: [
                      Container(
                        margin: const EdgeInsets.only(bottom: 24),
                        padding: const EdgeInsets.all(20),
                        decoration: BoxDecoration(
                          color: context.colorScheme.primary.withOpacity(0.08),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          Icons.drive_eta_rounded,
                          size: 48,
                          color: context.colorScheme.primary,
                        ),
                      ),
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
                      Text(
                        context.translate.onboardingDescription,
                        style: context.bodyMedium?.copyWith(
                          color: context.theme.colorScheme.onSurfaceVariant
                              .withOpacity(0.8),
                          height: 1.5,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 32),
                      // Divider "ou" removed since phone login is removed.
                      const SizedBox(height: 24),
                      // Botões Google
                      // Botões Google / Apple no iOS
                      if (defaultTargetPlatform == TargetPlatform.iOS) ...[
                        _SocialLoginButton(
                          onPressed: _googleLoading ? null : () => _handleAppleSignIn(false),
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
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                                  ),
                                )
                              : const Icon(Icons.apple, color: Colors.white, size: 24),
                          label: _googleLoading
                              ? 'Aguarde...'
                              : 'Entrar com Apple',
                          labelColor: Colors.white,
                        ),
                        const SizedBox(height: 16),
                        _SocialLoginButton(
                          onPressed: _googleLoading ? null : () => _handleAppleSignIn(true),
                          backgroundColor: context.colorScheme.primary,
                          borderColor: Colors.transparent,
                          boxShadow: [
                            BoxShadow(
                              color: context.colorScheme.primary.withOpacity(0.2),
                              blurRadius: 12,
                              offset: const Offset(0, 4),
                            ),
                          ],
                          icon: _googleLoading
                              ? const SizedBox(
                                  width: 22,
                                  height: 22,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                                  ),
                                )
                              : const Icon(Icons.apple, color: Colors.white, size: 24),
                          label: _googleLoading
                              ? 'Aguarde...'
                              : 'Cadastrar-se com Apple',
                          labelColor: Colors.white,
                        ),
                      ] else ...[
                        _SocialLoginButton(
                          onPressed: _googleLoading ? null : () => _handleGoogleSignIn(false),
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
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : _GoogleIcon(),
                          label: _googleLoading
                              ? 'Aguarde...'
                              : 'Entrar com Google',
                          labelColor: ColorPalette.neutral20,
                        ),
                        const SizedBox(height: 16),
                        _SocialLoginButton(
                          onPressed: _googleLoading ? null : () => _handleGoogleSignIn(true),
                          backgroundColor: context.colorScheme.primary,
                          borderColor: Colors.transparent,
                          boxShadow: [
                            BoxShadow(
                              color: context.colorScheme.primary.withOpacity(0.2),
                              blurRadius: 12,
                              offset: const Offset(0, 4),
                            ),
                          ],
                          icon: _googleLoading
                              ? const SizedBox(
                                  width: 22,
                                  height: 22,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                                  ),
                                )
                              : Container(
                                  decoration: const BoxDecoration(
                                    color: Colors.white,
                                    shape: BoxShape.circle,
                                  ),
                                  padding: const EdgeInsets.all(2),
                                  child: _GoogleIcon(),
                                ),
                          label: _googleLoading
                              ? 'Aguarde...'
                              : 'Cadastrar-se com Google',
                          labelColor: Colors.white,
                        ),
                      ],
                      const SizedBox(height: 32),
                      
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
                                            const SizedBox(height: 16),
                    ],
                  ),
                ),
              ),
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
      child: CustomPaint(painter: _GoogleLogoPainter()),
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
