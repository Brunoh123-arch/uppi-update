import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_common/core/color_palette/color_palette.dart';
import 'package:flutter_common/core/utils/friendly_error.dart';
import 'package:flutter_common/core/presentation/buttons/app_back_button.dart';
import 'package:rider_flutter/config/locator/locator.dart';
import 'package:rider_flutter/core/presentation/app_generic_map.dart';
import 'package:generic_map/generic_map.dart';
import 'package:flutter_common/config/constants.dart';
import 'package:flutter_common/core/entities/place.dart';
import 'package:rider_flutter/features/auth/presentation/blocs/onboarding_cubit.dart';
import 'package:rider_flutter/features/auth/presentation/widgets/login_form_builder.dart';

import '../blocs/login.dart';

class AuthScreenMobile extends StatelessWidget {
  const AuthScreenMobile({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: ColorPalette.neutralVariant99,
      body: Stack(
        children: [
          // 1. App Preview (Background Map)
          Positioned.fill(
            child: IgnorePointer(
              child: AppGenericMap(
                mode: MapViewMode.static,
                initialLocation: Constants.defaultLocation.toGenericMapPlace,
              ),
            ),
          ),
          
          // 2. Dark Overlay (Removido conforme pedido)
          // 3. Back Button (if needed)
          Positioned(
            top: MediaQuery.of(context).padding.top + 16,
            left: 16,
            child: BlocBuilder<LoginBloc, LoginState>(
              builder: (context, state) {
                if (state.loginPage is EnterNumber) {
                  return const SizedBox(); // Hide back button on main auth screen
                }
                return AppBackButton(
                  onPressed: () {
                    switch (state.loginPage) {
                      case EnterNumber():
                        locator<OnboardingCubit>().previousPage();
                        break;
                      default:
                        locator<LoginBloc>().onBackButtonPressed();
                    }
                  },
                );
              },
            ),
          ),

          // 4. Bottom Sheet UI
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.of(context).size.height * 0.9, // limite de 90% da tela para não cobrir tudo
              ),
              child: Container(
                width: double.infinity,
                decoration: const BoxDecoration(
                  color: ColorPalette.neutralVariant99,
                  borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black12,
                      blurRadius: 20,
                      offset: Offset(0, -5),
                    ),
                  ],
                ),
                child: SafeArea(
                  top: false,
                  child: BlocListener<LoginBloc, LoginState>(
                    listener: (context, state) {
                      state.loginPage.state.maybeMap(
                        error: (err) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(friendlyErrorMessage(err.errorMessage)),
                              backgroundColor: Colors.red,
                            ),
                          );
                        },
                        orElse: () {},
                      );
                    },
                    child: SingleChildScrollView(
                      physics: const ClampingScrollPhysics(),
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(24, 32, 24, 16),
                        child: AnimatedSwitcher(
                          duration: const Duration(milliseconds: 300),
                          child: BlocBuilder<LoginBloc, LoginState>(
                            builder: (context, state) {
                              return LoginFormBuilder(loginPage: state.loginPage).footer;
                            },
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
