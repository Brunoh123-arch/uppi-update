import 'package:uppi_motorista/features/auth/presentation/blocs/login.dart';
import 'package:uppi_motorista/features/auth/presentation/widgets/access_denied_form.dart';
import 'package:uppi_motorista/features/auth/presentation/widgets/login_forms/contact_details.dart';
import 'package:uppi_motorista/features/auth/presentation/widgets/login_forms/documents_form.dart';
import 'package:uppi_motorista/features/auth/presentation/widgets/login_forms/payout_information.dart';
import 'package:uppi_motorista/features/auth/presentation/widgets/login_forms/vehicle_details.dart';
import 'package:uppi_motorista/features/auth/presentation/widgets/verification_timeline.dart';
import 'package:flutter/material.dart';
import 'package:flutter_common/core/color_palette/color_palette.dart';

import 'login_forms/enter_number_form.dart';
import 'login_forms/enter_otp_form.dart';
import 'login_forms/enter_password_form.dart';
import 'login_forms/set_password_form.dart';

class LoginFormBuilder {
  final LoginState loginState;

  LoginFormBuilder({required this.loginState});

  Widget get header {
    return SizedBox();
  }

  Widget get footer {
    return loginState.loginPage.map(
      enterNumber: (enterNumber) => EnterNumberForm(state: loginState),
      enterOtp: (_) => EnterOtpForm(state: loginState),
      enterPassword: (_) => const EnterPasswordForm(),
      setPassword: (_) => const SetPasswordForm(),
      contactDetails: (_) => ContactDetails(state: loginState),
      vehicleDetails: (_) => VehicleDetails(state: loginState),
      payoutInformation: (_) => PayoutInformation(state: loginState),
      documents: (_) => DocumentsForm(state: loginState),
      accessDenied: (_) => const AccessDeniedForm(),
      success: (_) => const _SuccessWithTimeline(),
    );
  }
}

/// Success screen with celebration animation and verification timeline
class _SuccessWithTimeline extends StatefulWidget {
  const _SuccessWithTimeline();

  @override
  State<_SuccessWithTimeline> createState() => _SuccessWithTimelineState();
}

class _SuccessWithTimelineState extends State<_SuccessWithTimeline>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _fadeIn;
  late Animation<double> _slideUp;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );
    _fadeIn = CurvedAnimation(parent: _controller, curve: Curves.easeOut);
    _slideUp = Tween<double>(begin: 30, end: 0).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic),
    );
    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _fadeIn,
      child: AnimatedBuilder(
        animation: _slideUp,
        builder: (context, child) {
          return Transform.translate(
            offset: Offset(0, _slideUp.value),
            child: child,
          );
        },
        child: SingleChildScrollView(
          child: Column(
            children: [
              // Success Icon with glow
              Container(
                width: 100,
                height: 100,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: const LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [ColorPalette.primary50, ColorPalette.primary60],
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: ColorPalette.primary50.withOpacity(0.3),
                      blurRadius: 24,
                      spreadRadius: 4,
                    ),
                  ],
                ),
                child: const Icon(
                  Icons.check_rounded,
                  color: Colors.white,
                  size: 50,
                ),
              ),
              const SizedBox(height: 24),

              // Title
              Text(
                'Cadastro Enviado com Sucesso!',
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: ColorPalette.neutral20,
                  letterSpacing: -0.5,
                ),
              ),
              const SizedBox(height: 8),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Text(
                  'Aguarde enquanto analisamos seus documentos.\nIsso costuma levar menos de 24 horas.',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: ColorPalette.neutral50,
                    height: 1.5,
                  ),
                ),
              ),
              const SizedBox(height: 24),

              // Loading indicator
              const SizedBox(
                width: 28,
                height: 28,
                child: CircularProgressIndicator(
                  strokeWidth: 3,
                  valueColor: AlwaysStoppedAnimation<Color>(ColorPalette.primary50),
                ),
              ),
              const SizedBox(height: 36),

              // Verification Timeline
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 8),
                child: VerificationTimeline(completedSteps: 1),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

