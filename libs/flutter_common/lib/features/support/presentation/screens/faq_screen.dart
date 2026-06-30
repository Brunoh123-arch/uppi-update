import 'package:flutter/material.dart';

class SharedFaqScreen extends StatelessWidget {
  const SharedFaqScreen({super.key});

  static const List<Map<String, String>> _faqs = [
    {
      'question': 'Como funciona o Uppi?',
      'answer':
          'O Uppi é um aplicativo que conecta passageiros a motoristas parceiros de forma justa, rápida e segura. Oferecemos taxas transparentes e melhor remuneração para os motoristas parceiros.',
    },
    {
      'question': 'Como posso me cadastrar como motorista?',
      'answer':
          'Para se cadastrar, basta baixar o aplicativo Uppi Motorista, enviar seus documentos (CNH com EAR, CRLV do veículo e comprovante de residência) e aguardar a análise de nossa equipe.',
    },
    {
      'question': 'Quais são as formas de pagamento aceitas?',
      'answer':
          'Aceitamos pagamentos via Cartão de Crédito cadastrado no app, Pix direto na corrida e saldo da Carteira Digital do aplicativo.',
    },
    {
      'question': 'O que fazer se eu esquecer um objeto no veículo?',
      'answer':
          'Você deve entrar em contato conosco enviando um ticket de suporte logo abaixo com os detalhes da corrida ou pelo nosso WhatsApp de atendimento. Ajudaremos a contatar o motorista.',
    },
    {
      'question': 'Como as taxas de corrida são calculadas?',
      'answer':
          'As taxas são calculadas com base na distância da viagem, tempo estimado de trajeto e demanda da região no momento da solicitação. O preço é mostrado antes de confirmar a viagem.',
    },
  ];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Perguntas Frequentes (FAQ)'),
        centerTitle: true,
      ),
      body: ListView.builder(
        padding: const EdgeInsets.all(16.0),
        itemCount: _faqs.length,
        itemBuilder: (context, index) {
          final faq = _faqs[index];
          return Card(
            margin: const EdgeInsets.only(bottom: 8.0),
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: BorderSide(color: cs.outline.withOpacity(0.15)),
            ),
            child: ExpansionTile(
              title: Text(
                faq['question']!,
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              childrenPadding: const EdgeInsets.all(16.0),
              expandedAlignment: Alignment.topLeft,
              children: [
                Text(
                  faq['answer']!,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: cs.onSurface.withOpacity(0.8),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
