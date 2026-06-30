import 'package:flutter/material.dart';

class SharedLegalScreen extends StatelessWidget {
  const SharedLegalScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Documentos Legais'),
          centerTitle: true,
          bottom: TabBar(
            labelColor: cs.primary,
            unselectedLabelColor: cs.onSurface.withOpacity(0.6),
            indicatorColor: cs.primary,
            indicatorSize: TabBarIndicatorSize.tab,
            tabs: const [
              Tab(
                icon: Icon(Icons.article_outlined),
                text: 'Termos de Uso',
              ),
              Tab(
                icon: Icon(Icons.privacy_tip_outlined),
                text: 'Privacidade',
              ),
            ],
          ),
        ),
        body: const TabBarView(
          children: [
            _LegalTextContent(
              title: 'Termos de Uso do Uppi',
              lastUpdated: 'Última atualização: 26 de Maio de 2026',
              sections: [
                _LegalSection(
                  title: '1. Aceitação dos Termos de Uso',
                  content:
                      'Ao acessar, baixar ou utilizar a plataforma Uppi (seja o aplicativo de passageiro, motorista ou portal web), você concorda integralmente em cumprir e ser regido por estes Termos de Uso e por nossa Política de Privacidade. Caso não concorde com qualquer uma das disposições, você não deve utilizar nossos serviços.',
                ),
                _LegalSection(
                  title: '2. Natureza dos Serviços',
                  content:
                      'A Uppi opera exclusivamente como uma plataforma digital de intermediação tecnológica. Nós conectamos passageiros que necessitam de transporte privado a motoristas parceiros independentes devidamente cadastrados. A Uppi não presta serviços de transporte de passageiros direta ou indiretamente, não possui frota própria de veículos, nem mantém relação empregatícia com os motoristas parceiros.',
                ),
                _LegalSection(
                  title: '3. Cadastro e Segurança da Conta',
                  content:
                      'Para utilizar os recursos do aplicativo, é necessário criar uma conta fornecendo dados cadastrais reais, precisos e completos (como nome completo, telefone ativo, e-mail e CPF). Você é inteiramente responsável por manter o sigilo de suas credenciais de login e senha, bem como por qualquer atividade realizada em sua conta. Menores de 18 anos não são autorizados a criar contas independentes.',
                ),
                _LegalSection(
                  title: '4. Diretrizes de Conduta do Usuário',
                  content:
                      'Usuários e motoristas parceiros comprometem-se a interagir mutuamente com absoluto respeito, cortesia e segurança. Comportamentos inadequados que envolvam agressões verbais ou físicas, atitudes discriminatórias de qualquer espécie (raça, gênero, orientação sexual, religião, etc.), assédio ou qualquer tentativa de fraude resultarão na suspensão imediata e definitiva da conta infratora, sem prejuízo das medidas judiciais cabíveis.',
                ),
                _LegalSection(
                  title: '5. Preços, Taxas e Formas de Pagamento',
                  content:
                      'O valor estimado das viagens é calculado pelo nosso algoritmo com base em parâmetros como distância, tempo previsto do trajeto, trânsito e demanda na região. O passageiro aceita o valor exibido no aplicativo ao confirmar a viagem. As formas de pagamento válidas incluem cartões de crédito cadastrados, Pix direto no aplicativo e saldo de carteira digital. As tarifas pagas não são reembolsáveis após o início da prestação do serviço, exceto se houver erro sistêmico comprovado.',
                ),
                _LegalSection(
                  title: '6. Limitação de Responsabilidade',
                  content:
                      'A Uppi não se responsabiliza por prejuízos decorrentes de atos de terceiros, força maior, problemas de conexão à internet do dispositivo móvel do usuário ou condutas inadequadas praticadas por motoristas ou passageiros durante a viagem. Em toda a extensão permitida por lei, a responsabilidade total da Uppi por quaisquer sinistros limita-se aos valores intermediados na corrida em questão.',
                ),
              ],
            ),
            _LegalTextContent(
              title: 'Diretrizes de Privacidade e LGPD',
              lastUpdated: 'Última atualização: 26 de Maio de 2026',
              sections: [
                _LegalSection(
                  title: '1. Controle e Coleta de Informações',
                  content:
                      'Uppi Mobilidade Ltda. atua como controladora dos seus dados pessoais. Nós coletamos informações estritamente necessárias para a prestação dos nossos serviços, incluindo: dados cadastrais (nome, telefone, CPF, e-mail), registros de geolocalização exata em tempo real (mesmo em segundo plano, para motoristas parceiros, de modo a permitir o funcionamento adequado da plataforma), dados financeiros de faturamento e o histórico completo de corridas e avaliações.',
                ),
                _LegalSection(
                  title: '2. Finalidade do Tratamento de Dados',
                  content:
                      'Tratamos seus dados com bases legais legítimas e finalidades explícitas (art. 9º da LGPD):\n'
                      '• Execução de Contrato: Processar seu cadastro, conectar motoristas e passageiros, realizar o cálculo exato do valor da corrida e intermediar as transações financeiras.\n'
                      '• Legítimo Interesse: Prevenir fraudes cibernéticas, dar suporte pós-corrida e resolver disputas comerciais.\n'
                      '• Obrigação Legal: Emissão de comprovantes fiscais e guarda obrigatória de registros de acesso de acordo com o Marco Civil da Internet.',
                ),
                _LegalSection(
                  title: '3. Compartilhamento Seguro de Dados',
                  content:
                      'Não comercializamos ou compartilhamos dados pessoais para fins publicitários de terceiros. Seus dados são compartilhados exclusivamente de forma segura nas seguintes hipóteses:\n'
                      '• Com o motorista parceiro (ou passageiro), compartilhando apenas o nome, foto de perfil, avaliação e pontos de partida e destino para fins operacionais.\n'
                      '• Com gateway de pagamento parceiro (Mercado Pago), para fins de cobrança e crédito de saldos.\n'
                      '• Com autoridades policiais ou judiciais mediante requerimento legal legítimo.',
                ),
                _LegalSection(
                  title: '4. Segurança e Armazenamento dos Dados',
                  content:
                      'Utilizamos tecnologia de criptografia ponta a ponta em trânsito (SSL/TLS), firewalls de banco de dados e controle rigoroso de acesso às informações. Os dados pessoais são armazenados de forma segura em servidores de nuvem de alta confiabilidade durante o período em que sua conta estiver ativa ou enquanto houver obrigação regulatória de guarda.',
                ),
                _LegalSection(
                  title: '5. Seus Direitos como Titular (Art. 18 LGPD)',
                  content:
                      'Você possui direitos fundamentais garantidos sobre seus dados pessoais, tais como:\n'
                      '• Confirmar a existência do tratamento de dados pessoais.\n'
                      '• Acessar seus dados coletados pela plataforma.\n'
                      '• Solicitar a retificação imediata de informações incompletas ou incorretas.\n'
                      '• Solicitar a portabilidade dos seus dados para outra plataforma.\n'
                      '• Solicitar a exclusão definitiva da sua conta e de todos os dados associados a qualquer momento, diretamente nas configurações de privacidade do aplicativo ou contactando nosso Encarregado pelo e-mail privacidade@uppimobilidade.com.br.',
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _LegalTextContent extends StatelessWidget {
  final String title;
  final String lastUpdated;
  final List<_LegalSection> sections;

  const _LegalTextContent({
    required this.title,
    required this.lastUpdated,
    required this.sections,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return ListView(
      padding: const EdgeInsets.all(16.0),
      children: [
        Card(
          elevation: 0,
          color: cs.primaryContainer.withOpacity(0.15),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: BorderSide(color: cs.primary.withOpacity(0.1)),
          ),
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: theme.textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: cs.primary,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  lastUpdated,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: cs.onSurface.withOpacity(0.6),
                    fontStyle: FontStyle.italic,
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        ...sections,
        const SizedBox(height: 32),
      ],
    );
  }
}

class _LegalSection extends StatelessWidget {
  final String title;
  final String content;

  const _LegalSection({
    required this.title,
    required this.content,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return Padding(
      padding: const EdgeInsets.only(bottom: 16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.bold,
              color: cs.onSurface,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            content,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: cs.onSurface.withOpacity(0.8),
              height: 1.5,
            ),
          ),
          const SizedBox(height: 8),
          const Divider(),
        ],
      ),
    );
  }
}
