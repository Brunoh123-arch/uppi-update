import 'package:uppi_motorista/config/locator/locator.dart';
import 'package:uppi_motorista/core/extensions/extensions.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:ionicons/ionicons.dart';
import 'package:flutter_common/core/color_palette/color_palette.dart';
import 'package:flutter_common/core/presentation/buttons/app_primary_button.dart';

import '../../blocs/login.dart';

class SetPasswordForm extends StatefulWidget {
  const SetPasswordForm({super.key});

  @override
  State<SetPasswordForm> createState() => _SetPasswordFormState();
}

class _SetPasswordFormState extends State<SetPasswordForm> {
  bool showPassword = false;

  @override
  Widget build(BuildContext context) {
    final loginBloc = locator<LoginBloc>();
    return BlocBuilder<LoginBloc, LoginState>(
      builder: (context, state) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // ── Header ──
                    Container(
                      margin: const EdgeInsets.only(bottom: 24),
                      alignment: Alignment.center,
                      child: Container(
                        padding: const EdgeInsets.all(20),
                        decoration: BoxDecoration(
                          color: context.colorScheme.primary.withOpacity(0.08),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          Icons.lock_outline_rounded,
                          size: 48,
                          color: context.colorScheme.primary,
                        ),
                      ),
                    ),
                    Center(
                      child: Text(
                        'Criar Senha',
                        style: context.titleLarge?.copyWith(
                          fontWeight: FontWeight.w800,
                          fontSize: 26,
                          letterSpacing: -0.5,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Center(
                      child: Text(
                        'Crie uma senha segura para proteger sua conta de motorista.',
                        style: context.bodyMedium?.copyWith(
                          color: context.theme.colorScheme.onSurfaceVariant
                              .withOpacity(0.7),
                          height: 1.5,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),
                    const SizedBox(height: 28),

                    // ── Password Field ──
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.surface,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: Theme.of(
                            context,
                          ).colorScheme.outlineVariant.withOpacity(0.3),
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.03),
                            blurRadius: 12,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: TextField(
                        onChanged: loginBloc.onNewPasswordChanged,
                        obscureText: !showPassword,
                        decoration: InputDecoration(
                          labelText: context.translate.password,
                          hintText: '••••••••',
                          prefixIcon: const Icon(Icons.lock_outline_rounded),
                          suffixIcon: CupertinoButton(
                            onPressed: () =>
                                setState(() => showPassword = !showPassword),
                            child: Icon(
                              showPassword ? Ionicons.eye_off : Ionicons.eye,
                              color: context
                                  .theme
                                  .inputDecorationTheme
                                  .suffixIconColor,
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),

                    // ── Password Requirements ──
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: context.theme.colorScheme.surfaceContainerHighest
                            .withOpacity(0.3),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Requisitos da senha',
                            style: context.titleSmall?.copyWith(
                              fontWeight: FontWeight.w700,
                              color: context.theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                          const SizedBox(height: 12),
                          _PasswordRule(
                            isValid: state.codeLengthIsSafe,
                            text: context.translate.passwordRuleLength,
                          ),
                          const SizedBox(height: 8),
                          _PasswordRule(
                            isValid: state.hasAtLeastTwoChecks,
                            text: context.translate.passwordRuleDescription,
                          ),
                          Padding(
                            padding: const EdgeInsets.only(left: 32, top: 6),
                            child: Text(
                              "\u2022 ${context.translate.passwordRuleUpperCase}\n\u2022 ${context.translate.passwordRuleLowerCase}\n\u2022 ${context.translate.passwordRuleNumber}\n\u2022 ${context.translate.passwordRuleSpecialCharacter}",
                              style: context.bodySmall?.copyWith(
                                color: context
                                    .theme
                                    .colorScheme
                                    .onSurfaceVariant
                                    .withOpacity(0.7),
                                height: 1.6,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            AppPrimaryButton(
              onPressed: (!state.hasAtLeastTwoChecks)
                  ? null
                  : loginBloc.onNewPasswordSubmitted,
              child: Text(context.translate.actionContinue),
            ),
          ],
        );
      },
    );
  }
}

// ─── Password Rule Widget ─────────────────────────────────────────────────────

class _PasswordRule extends StatelessWidget {
  final bool isValid;
  final String text;

  const _PasswordRule({required this.isValid, required this.text});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 250),
          child: Icon(
            isValid ? Icons.check_circle_rounded : Icons.cancel_rounded,
            key: ValueKey(isValid),
            size: 22,
            color: isValid
                ? ColorPalette.semanticgreen60
                : ColorPalette.error50,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            text,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      ],
    );
  }
}
