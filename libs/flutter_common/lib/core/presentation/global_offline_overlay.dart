import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_common/core/blocs/connectivity_cubit.dart';

class GlobalOfflineOverlay extends StatelessWidget {
  final Widget child;

  const GlobalOfflineOverlay({
    super.key,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<ConnectivityCubit, ConnectivityState>(
      builder: (context, state) {
        if (state.isDisconnected) {
          final isDark = Theme.of(context).brightness == Brightness.dark;
          
          return Scaffold(
            backgroundColor: isDark ? const Color(0xFF121212) : Colors.white,
            body: SafeArea(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24.0),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Spacer(),
                    Container(
                      height: 160,
                      alignment: Alignment.center,
                      child: Icon(
                        Icons.wifi_off_rounded,
                        size: 100,
                        color: isDark ? const Color(0xFFE57373) : const Color(0xFFD32F2F),
                      ),
                    ),
                    const SizedBox(height: 32),
                    Text(
                      'Sem conexão com a internet',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontFamily: 'GeneralSans',
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                        color: isDark ? Colors.white : const Color(0xFF2E3E5C),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'Parece que você está offline. Por favor, verifique sua conexão de rede e tente novamente.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontFamily: 'Inter',
                        fontSize: 16,
                        color: isDark ? const Color(0xFFB0BEC5) : const Color(0xFF9FA5C0),
                        height: 1.5,
                      ),
                    ),
                    const Spacer(),
                    ElevatedButton(
                      onPressed: () {
                        context.read<ConnectivityCubit>().checkConnection();
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFFD32F2F),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        elevation: 0,
                      ),
                      child: const Text(
                        'Tentar Novamente',
                        style: TextStyle(
                          fontFamily: 'GeneralSans',
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),
                  ],
                ),
              ),
            ),
          );
        }
        return child;
      },
    );
  }
}
