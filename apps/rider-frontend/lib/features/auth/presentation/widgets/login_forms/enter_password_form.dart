import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_common/core/presentation/buttons/app_primary_button.dart';
import 'package:ionicons/ionicons.dart';
import 'package:rider_flutter/config/locator/locator.dart';
import 'package:rider_flutter/core/extensions/extensions.dart';
import 'package:rider_flutter/features/auth/presentation/blocs/login.dart';

class EnterPasswordForm extends StatelessWidget {
  const EnterPasswordForm({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<LoginBloc, LoginState>(
      builder: (context, state) => state.loginPage.maybeMap(
        orElse: () => const SizedBox(),
        enterPassword: (enterPassword) => Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: SingleChildScrollView(
                child: Column(
                  children: [
                    Container(
                      margin: const EdgeInsets.only(bottom: 24, top: 16),
                      alignment: Alignment.center,
                      child: Container(
                        padding: const EdgeInsets.all(20),
                        decoration: BoxDecoration(
                          color: context.colorScheme.primary.withOpacity(0.08),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          Ionicons.lock_closed,
                          size: 48,
                          color: context.colorScheme.primary,
                        ),
                      ),
                    ),
                    Text(
                      context.translate.useOtpInstead,
                      style: context.titleLarge?.copyWith(
                        fontWeight: FontWeight.w800,
                        fontSize: 28,
                        letterSpacing: -0.5,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      "Para sua segurança, a autenticação é realizada exclusivamente através de código temporário enviado por SMS.",
                      style: context.bodyMedium?.copyWith(
                        color: context.theme.colorScheme.onSurfaceVariant
                            .withOpacity(0.8),
                        height: 1.5,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 32),
                    if (state.loginPage.state.mapOrNull(error: (value) => value.errorMessage) != null)
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: context.theme.colorScheme.errorContainer.withOpacity(0.2),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          state.loginPage.state.mapOrNull(error: (value) => value.errorMessage)!,
                          style: context.bodyMedium?.copyWith(
                            color: context.theme.colorScheme.error,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ),
                  ],
                ),
              ),
            ),
            AppPrimaryButton(
              isDisabled: enterPassword.state.isLoading,
              onPressed: locator<LoginBloc>().onCodeResendRequested,
              child: Text(context.translate.useOtpInstead),
            ),
          ],
        ),
      ),
    );
  }
}
