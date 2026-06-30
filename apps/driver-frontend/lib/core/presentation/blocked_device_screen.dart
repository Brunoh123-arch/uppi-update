import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:ionicons/ionicons.dart';

class BlockedDeviceScreen extends StatelessWidget {
  final String threatType;

  const BlockedDeviceScreen({
    super.key,
    required this.threatType,
  });

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false, // Impede que o usuário saia usando o botão voltar
      child: Scaffold(
        backgroundColor: const Color(0xFF0F0F11), // Fundo premium escuro
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 32.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                const Spacer(),
                // Escudo de Alerta Premium com Sombra
                Container(
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1E1E24),
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: const Color(0xFFFF5252).withOpacity(0.15),
                      width: 2,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFFFF5252).withOpacity(0.1),
                        blurRadius: 32,
                        spreadRadius: 8,
                      ),
                    ],
                  ),
                  child: const Icon(
                    Ionicons.shield,
                    size: 80,
                    color: Color(0xFFFF5252), // Vermelho de segurança
                  ),
                ),
                const SizedBox(height: 40),
                // Título de Bloqueio
                const Text(
                  'Acesso Bloqueado',
                  style: TextStyle(
                    fontFamily: 'GeneralSans',
                    fontSize: 28,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                    letterSpacing: -0.5,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 16),
                // Texto Explicativo de Segurança
                Text(
                  threatType == 'root_jailbreak'
                      ? 'Detectamos que este dispositivo possui permissões de administrador ativas (Root/Jailbreak). Por questões de segurança e integridade do app Uppi, o acesso foi bloqueado.'
                      : 'Detectamos que o aplicativo está rodando em um Emulador ou ambiente virtualizado. Para usar o Uppi Motorista, você deve usar um smartphone físico homologado.',
                  style: TextStyle(
                    fontFamily: 'Inter',
                    fontSize: 15,
                    fontWeight: FontWeight.w400,
                    color: Colors.white.withOpacity(0.65),
                    height: 1.6,
                  ),
                  textAlign: TextAlign.center,
                ),
                const Spacer(),
                // Box Informativa de Código de Segurança
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                  decoration: BoxDecoration(
                    color: const Color(0xFF16161A),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: Colors.white.withOpacity(0.06),
                      width: 1,
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Ionicons.information_circle_outline,
                        color: Colors.white.withOpacity(0.4),
                        size: 20,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          'ID de Segurança: UPP-SHIELD-${threatType == 'root_jailbreak' ? '01' : '02'}',
                          style: TextStyle(
                            fontFamily: 'Inter',
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                            color: Colors.white.withOpacity(0.4),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),
                // Botão para Encerrar o App
                SizedBox(
                  width: double.infinity,
                  height: 56,
                  child: ElevatedButton(
                    onPressed: () {
                      SystemNavigator.pop();
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.white,
                      foregroundColor: Colors.black,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                      elevation: 0,
                    ),
                    child: const Text(
                      'Fechar Aplicativo',
                      style: TextStyle(
                        fontFamily: 'GeneralSans',
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
