import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'package:rider_flutter/config/locator/locator.dart';
import 'package:rider_flutter/core/extensions/extensions.dart';
import 'package:flutter_common/core/presentation/buttons/app_primary_button.dart';
import 'package:flutter_common/core/presentation/buttons/app_text_button.dart';
import 'package:flutter_common/core/presentation/otp_textfield.dart';
import 'package:rider_flutter/features/auth/presentation/blocs/login.dart';

class EnterOtpForm extends StatefulWidget {
  const EnterOtpForm({super.key});

  @override
  State<EnterOtpForm> createState() => _EnterOtpFormState();
}

class _EnterOtpFormState extends State<EnterOtpForm> {
  String code = "";

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<LoginBloc, LoginState>(
      builder: (context, state) => state.loginPage.maybeMap(
        orElse: () => const SizedBox(),
        enterOtp: (enterOtp) => Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
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
                  Icons.message_rounded,
                  size: 48,
                  color: context.colorScheme.primary,
                ),
              ),
            ),
            Text(
              context.translate.enterCode,
              style: context.titleLarge?.copyWith(
                fontWeight: FontWeight.w800,
                fontSize: 28,
                letterSpacing: -0.5,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
            Text(
              context.translate.sendOtpDescription,
              style: context.bodyMedium?.copyWith(
                color:
                    context.theme.colorScheme.onSurfaceVariant.withOpacity(0.8),
                height: 1.5,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 32),
            Center(
                child: OtpTextField(
              length: 6,
              onChanged: (p0) {
                setState(() {
                  code = p0;
                });
              },
            )),
            const SizedBox(
              height: 32,
            ),
            StreamBuilder(
              stream: Stream.periodic(const Duration(seconds: 1)),
              builder: (context, snapShot) {
                return state.canResendOtp
                    ? AppTextButton(
                        isDisabled: enterOtp.state.isLoading,
                        text: context.translate.resendOtp,
                        onPressed: () =>
                            locator<LoginBloc>().onCodeResendRequested(),
                      )
                    : Text(
                        context.translate.resendOtpIn(state.resendOtpIn),
                        style: context.bodyMedium?.copyWith(
                          color: context.theme.colorScheme.onSurfaceVariant,
                        ),
                        textAlign: TextAlign.center,
                      );
              },
            ),
            const Spacer(),
            AppPrimaryButton(
              isDisabled: enterOtp.state.isLoading || code.length < 6,
              onPressed: () {
                locator<LoginBloc>().onOtpVerificationRequested(code);
              },
              child: Text(
                context.translate.actionContinue,
              ),
            )
          ],
        ),
      ),
    );
  }
}
