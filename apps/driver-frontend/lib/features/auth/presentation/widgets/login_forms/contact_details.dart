import 'package:uppi_motorista/config/locator/locator.dart';
import 'package:uppi_motorista/core/extensions/extensions.dart';
import 'package:uppi_motorista/features/auth/presentation/blocs/login.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_common/core/enums/gender.dart';
import 'package:flutter_common/core/presentation/buttons/app_primary_button.dart';
import 'package:flutter_common/core/presentation/rounded_checkbox.dart';
import 'package:flutter_common/core/utils/cpf_input_formatter.dart';

class ContactDetails extends StatefulWidget {
  final LoginState state;

  const ContactDetails({super.key, required this.state});

  @override
  State<ContactDetails> createState() => _ContactDetailsState();
}

class _ContactDetailsState extends State<ContactDetails> {
  final formKey = GlobalKey<FormState>();

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
                  FormField<Gender>(
                    initialValue: widget.state.profileFullEntity?.gender,
                    onSaved: (newValue) {
                      if (newValue != null) loginBloc.onGenderChanged(newValue);
                    },
                    builder: (state) {
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            context.translate.gender,
                            style: context.titleSmall,
                          ),
                          const SizedBox(height: 4),
                          Wrap(
                            spacing: 12,
                            runSpacing: 8,
                            children: Gender.values
                                .map(
                                  (e) => CupertinoButton(
                                    onPressed: () => state.didChange(e),
                                    padding: const EdgeInsets.all(0),
                                    minimumSize: Size(0, 0),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        RoundedCheckbox(
                                          isSelected: state.value == e,
                                        ),
                                        const SizedBox(width: 4),
                                        Text(
                                          e.title(context),
                                          style: context.bodyLarge,
                                        ),
                                      ],
                                    ),
                                  ),
                                )
                                .toList(),
                          ),
                        ],
                      );
                    },
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    initialValue: widget.state.profileFullEntity?.firstName,
                    validator: (value) => value?.isEmpty == true
                        ? context.translate.fieldIsRequired
                        : null,
                    onSaved: loginBloc.onFirstNameChanged,
                    decoration: InputDecoration(
                      hintText: context.translate.firstName,
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    initialValue: widget.state.profileFullEntity?.lastName,
                    validator: (value) => value?.isEmpty == true
                        ? context.translate.fieldIsRequired
                        : null,
                    onSaved: loginBloc.onLastNameChanged,
                    decoration: InputDecoration(
                      hintText: context.translate.lastName,
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    initialValue: widget.state.profileFullEntity?.certificateNumber,
                    keyboardType: TextInputType.number,
                    inputFormatters: [CpfInputFormatter()],
                    validator: (value) {
                      if (value == null || value.isEmpty) {
                        return context.translate.fieldIsRequired;
                      }
                      if (value.length < 14) {
                        return 'CPF incompleto';
                      }
                      return null;
                    },
                    onSaved: loginBloc.onCertificateNumberChanged,
                    decoration: const InputDecoration(
                      hintText: 'CPF (obrigatório)',
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    initialValue: widget.state.profileFullEntity?.mobileNumber,
                    keyboardType: TextInputType.phone,
                    validator: (value) {
                      if (value == null || value.trim().isEmpty) {
                        return context.translate.fieldIsRequired;
                      }
                      final digitsOnly = value.replaceAll(RegExp(r'[^0-9]'), '');
                      if (digitsOnly.length < 10) {
                        return 'Telefone com DDD inválido';
                      }
                      return null;
                    },
                    onSaved: loginBloc.onMobileNumberChanged,
                    decoration: InputDecoration(
                      hintText: '${context.translate.mobileNumber} (obrigatório)',
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    initialValue: widget.state.profileFullEntity?.email,
                    validator: (value) {
                      if (value == null || value.trim().isEmpty) {
                        return context.translate.fieldIsRequired;
                      }
                      final emailRegExp = RegExp(r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$');
                      if (!emailRegExp.hasMatch(value.trim())) {
                        return 'E-mail inválido';
                      }
                      return null;
                    },
                    onSaved: loginBloc.onEmailChanged,
                    decoration: InputDecoration(
                      hintText: "${context.translate.email} (obrigatório)",
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    initialValue: widget.state.profileFullEntity?.address,
                    validator: (value) => value == null || value.trim().isEmpty
                        ? context.translate.fieldIsRequired
                        : null,
                    onSaved: loginBloc.onAddressChanged,
                    decoration: InputDecoration(
                      hintText: "${context.translate.address} (obrigatório)",
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
              loginBloc.onConfirmContactDetailsPressed();
            }
          },
          child: Text(context.translate.confirm),
        ),
      ],
    );
  }
}
