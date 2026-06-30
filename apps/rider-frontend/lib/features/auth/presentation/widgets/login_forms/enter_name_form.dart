import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_common/core/enums/gender.dart';
import 'package:flutter_common/core/presentation/buttons/app_primary_button.dart';
import 'package:flutter_common/core/presentation/rounded_checkbox.dart';
import 'package:rider_flutter/config/locator/locator.dart';
import 'package:rider_flutter/core/extensions/extensions.dart';
import 'package:rider_flutter/features/auth/presentation/blocs/login.dart';
import 'package:flutter_common/core/utils/cpf_input_formatter.dart';

class EnterNameForm extends StatefulWidget {
  const EnterNameForm({super.key});

  @override
  State<EnterNameForm> createState() => _EnterNameFormState();
}

class _EnterNameFormState extends State<EnterNameForm> {
  final formKey = GlobalKey<FormState>();
  Gender? gender;
  String firstName = '';
  String lastName = '';
  String email = '';
  String idNumber = '';

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<LoginBloc, LoginState>(
      builder: (context, state) => state.loginPage.maybeMap(
        orElse: () => const SizedBox(),
        enterName: (enterName) => Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: SingleChildScrollView(
                child: Form(
                  key: formKey,
                  child: Column(
                    children: [
                      Text(
                        context.translate.nameHint,
                        style: context.titleLarge,
                      ),
                      const SizedBox(
                        height: 24,
                      ),
                      TextFormField(
                        initialValue: firstName,
                        validator: (value) => value?.isEmpty == true
                            ? context.translate.fieldIsRequired
                            : null,
                        onSaved: (newValue) => firstName = newValue ?? '',
                        decoration: InputDecoration(
                          hintText: context.translate.firstName,
                        ),
                      ),
                      const SizedBox(
                        height: 16,
                      ),
                      TextFormField(
                        initialValue: lastName,
                        validator: (value) => value?.isEmpty == true
                            ? context.translate.fieldIsRequired
                            : null,
                        onSaved: (newValue) => lastName = newValue ?? '',
                        decoration: InputDecoration(
                          hintText: context.translate.lastName,
                        ),
                      ),
                      const SizedBox(
                        height: 16,
                      ),
                      TextFormField(
                        initialValue: idNumber,
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
                        onSaved: (newValue) => idNumber = newValue ?? '',
                        decoration: const InputDecoration(
                          hintText: 'CPF (obrigatório)',
                        ),
                      ),
                      const SizedBox(
                        height: 16,
                      ),
                      TextFormField(
                        initialValue: email,
                        onSaved: (newValue) => email = newValue ?? '',
                        decoration: InputDecoration(
                          hintText: context.translate.email,
                        ),
                      ),
                      const SizedBox(
                        height: 16,
                      ),
                      FormField<Gender>(
                        initialValue: gender,
                        onSaved: (newValue) => gender = newValue,
                        builder: (state) {
                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                context.translate.gender,
                                style: context.titleSmall,
                              ),
                              const SizedBox(
                                height: 8,
                              ),
                              Row(
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
                                            const SizedBox(
                                              width: 4,
                                            ),
                                            Text(
                                              e.title(context),
                                              style: context.bodyLarge,
                                            ),
                                            const SizedBox(
                                              width: 8,
                                            ),
                                          ],
                                        ),
                                      ),
                                    )
                                    .toList(),
                              )
                            ],
                          );
                        },
                      ),
                    ],
                  ),
                ),
              ),
            ),
            AppPrimaryButton(
              isDisabled: enterName.state.isLoading,
              onPressed: () {
                if (formKey.currentState?.validate() == false) return;
                formKey.currentState?.save();
                locator<LoginBloc>().onProfileDataSubmitted(
                  firstName: firstName,
                  lastName: lastName,
                  email: email,
                  gender: gender,
                  idNumber: idNumber,
                );
              },
              child: Text(context.translate.saveChanges),
            )
          ],
        ),
      ),
    );
  }
}
