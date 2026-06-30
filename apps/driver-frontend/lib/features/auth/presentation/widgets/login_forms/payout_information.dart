import 'package:uppi_motorista/config/locator/locator.dart';
import 'package:uppi_motorista/core/extensions/extensions.dart';
import 'package:uppi_motorista/features/auth/presentation/blocs/login.dart';
import 'package:flutter/material.dart';
import 'package:flutter_common/core/presentation/buttons/app_primary_button.dart';

class PayoutInformation extends StatefulWidget {
  final LoginState state;

  const PayoutInformation({super.key, required this.state});

  @override
  State<PayoutInformation> createState() => _PayoutInformationState();
}

class _PayoutInformationState extends State<PayoutInformation> {
  final GlobalKey<FormState> formKey = GlobalKey();

  @override
  Widget build(BuildContext context) {
    final loginBloc = locator<LoginBloc>();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: SingleChildScrollView(
            child: Form(
              key: formKey,
              child: Column(
                children: [
                  TextFormField(
                    initialValue: widget.state.profileFullEntity?.bankName,
                    onSaved: loginBloc.onBankNameChanged,
                    decoration: InputDecoration(
                      hintText: context.translate.bankName,
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    initialValue: widget.state.profileFullEntity?.bankRoutingNumber,
                    onSaved: loginBloc.onBankRoutingNumberChanged,
                    decoration: InputDecoration(
                      hintText: context.translate.bankRoutingNumber,
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    initialValue: widget.state.profileFullEntity?.bankAccountNumber,
                    onSaved: loginBloc.onBankAccountNumberChanged,
                    decoration: InputDecoration(
                      hintText: context.translate.bankAccountNumber,
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    initialValue: widget.state.profileFullEntity?.bankSwiftCode,
                    onSaved: loginBloc.onBankSwiftCodeChanged,
                    decoration: InputDecoration(
                      hintText: context.translate.bankSwift,
                    ),
                  ),
                  const SizedBox(height: 16),
                ],
              ),
            ),
          ),
        ),
        AppPrimaryButton(
          onPressed: () {
            if (formKey.currentState?.validate() == true) {
              formKey.currentState?.save();
              loginBloc.onConfirmPayoutInformationPressed();
            }
          },
          child: Text(context.translate.confirm),
        ),
      ],
    );
  }

  Widget actionButtons(BuildContext context) {
    return AppPrimaryButton(
      onPressed: () {},
      child: Text(context.translate.actionContinue),
    );
  }
}
