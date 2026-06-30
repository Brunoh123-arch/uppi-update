import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../domain/lgpd_consent.dart';

/// Tela profissional de Termos de Privacidade e Uso da Uppi.
/// Textos redigidos em linguagem jurídica profissional conforme LGPD.
class LgpdPrivacyTermsScreen extends StatelessWidget {
  const LgpdPrivacyTermsScreen({super.key});

  Future<void> _openUrl(String url) async {
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return Scaffold(
      backgroundColor: cs.surface,
      body: CustomScrollView(
        slivers: [
          // ── AppBar com gradiente ────────────────────────────
          SliverAppBar(
            expandedHeight: 160,
            pinned: true,
            backgroundColor: cs.primary,
            leading: IconButton(
              icon: Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(
                  Icons.arrow_back_rounded,
                  color: Colors.white,
                  size: 20,
                ),
              ),
              onPressed: () => Navigator.of(context).pop(),
            ),
            flexibleSpace: FlexibleSpaceBar(
              background: Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      cs.primary,
                      cs.primary.withValues(alpha: 0.8),
                    ],
                  ),
                ),
                child: SafeArea(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(24, 48, 24, 16),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.end,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: const Icon(
                                Icons.verified_user_rounded,
                                color: Colors.white,
                                size: 22,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Privacidade e Uso',
                                    style:
                                        theme.textTheme.titleLarge?.copyWith(
                                      color: Colors.white,
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    'Uppi Mobilidade Urbana',
                                    style:
                                        theme.textTheme.bodySmall?.copyWith(
                                      color:
                                          Colors.white.withValues(alpha: 0.7),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),

          // ── Conteúdo ────────────────────────────────────────
          SliverPadding(
            padding: const EdgeInsets.all(20),
            sliver: SliverList(
              delegate: SliverChildListDelegate([
                // ── Última atualização ────────────────────────
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: cs.primaryContainer.withValues(alpha: 0.4),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.update_rounded,
                          size: 16, color: cs.primary),
                      const SizedBox(width: 8),
                      Text(
                        'Última atualização: 29 de maio de 2025',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: cs.primary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),

                // ── 1. Termos de Uso — Passageiro ─────────────
                _TermsSection(
                  icon: Icons.person_rounded,
                  iconColor: cs.primary,
                  title: 'Termos de Uso — Passageiro',
                  content: 'TERMOS E CONDIÇÕES GERAIS DE USO DO APLICATIVO UPPI — MODALIDADE PASSAGEIRO\n\n'
                      'O presente instrumento regula as condições gerais de uso do aplicativo UPPI ("Plataforma"), '
                      'de titularidade da UPPI MOBILIDADE LTDA., pessoa jurídica de direito privado, inscrita no '
                      'CNPJ sob o nº [CNPJ], com sede na cidade de Castanhal, Estado do Pará, doravante denominada '
                      'simplesmente "UPPI".\n\n'
                      '1. DO OBJETO\n\n'
                      '1.1. A Plataforma UPPI tem por objeto a intermediação tecnológica entre passageiros e '
                      'motoristas parceiros cadastrados, viabilizando a conexão entre usuários que necessitam de '
                      'transporte individual privado de passageiros e condutores habilitados e aptos a prestar '
                      'tal serviço.\n\n'
                      '1.2. A UPPI atua exclusivamente como plataforma intermediadora de tecnologia, não '
                      'constituindo, em nenhuma hipótese, empresa de transporte, empregadora dos motoristas '
                      'parceiros ou responsável direta pela prestação do serviço de transporte.\n\n'
                      '2. DO CADASTRO E ACEITAÇÃO\n\n'
                      '2.1. Para utilizar os serviços da Plataforma, o Passageiro deverá realizar cadastro '
                      'prévio, fornecendo informações verídicas, completas e atualizadas, incluindo, mas não '
                      'se limitando a: nome completo, número de telefone celular válido, endereço de e-mail '
                      'e, quando aplicável, dados para faturamento.\n\n'
                      '2.2. Ao concluir o cadastro e utilizar a Plataforma, o Passageiro declara ter lido, '
                      'compreendido e aceito integralmente os presentes Termos de Uso, a Política de Privacidade '
                      'e demais políticas disponibilizadas pela UPPI.\n\n'
                      '2.3. O Passageiro é integralmente responsável pela veracidade e atualização dos dados '
                      'cadastrais, respondendo civil e penalmente por informações falsas ou fraudulentas.\n\n'
                      '3. DAS OBRIGAÇÕES DO PASSAGEIRO\n\n'
                      '3.1. Utilizar a Plataforma em conformidade com a legislação vigente, especialmente o '
                      'Código de Trânsito Brasileiro (Lei nº 9.503/1997), a Lei nº 12.587/2012 (Política Nacional '
                      'de Mobilidade Urbana) e as normas municipais aplicáveis.\n\n'
                      '3.2. Tratar os motoristas parceiros com respeito, urbanidade e cordialidade, abstendo-se '
                      'de quaisquer condutas discriminatórias, abusivas, ameaçadoras, difamatórias ou que '
                      'configurem assédio moral ou sexual, sob pena de suspensão imediata ou exclusão '
                      'definitiva da Plataforma, sem prejuízo das medidas judiciais cabíveis.\n\n'
                      '3.3. Efetuar o pagamento integral do valor da corrida conforme calculado pela Plataforma, '
                      'que considera a distância percorrida, o tempo de viagem, a tarifa base vigente, '
                      'eventuais taxas de espera, pedágios, tarifas dinâmicas e demais encargos aplicáveis.\n\n'
                      '3.4. Zelar pela integridade e conservação do veículo durante toda a corrida. O Passageiro '
                      'responderá integralmente por danos causados ao veículo, incluindo, mas não se limitando '
                      'a: sujeira excessiva, avarias no interior ou exterior, derramamento de líquidos e '
                      'deterioração de bancos e acessórios.\n\n'
                      '3.5. Não transportar substâncias ilícitas, materiais perigosos, inflamáveis, explosivos '
                      'ou quaisquer objetos cuja posse ou transporte seja vedado pela legislação brasileira.\n\n'
                      '3.6. Não solicitar ao motorista parceiro a prática de atos ilegais, incluindo excesso '
                      'de velocidade, ultrapassagem em local proibido, desrespeito à sinalização de trânsito '
                      'ou desvios de rota com o intuito de evadir-se de obrigações legais.\n\n'
                      '4. DA POLÍTICA DE CANCELAMENTO\n\n'
                      '4.1. O Passageiro poderá cancelar a corrida solicitada sem ônus dentro do prazo '
                      'estabelecido pela Plataforma, contado a partir da aceitação da corrida pelo motorista.\n\n'
                      '4.2. Cancelamentos realizados após o prazo de tolerância ou após a chegada do motorista '
                      'ao ponto de embarque poderão gerar a cobrança de taxa de cancelamento, cujo valor '
                      'será informado previamente na Plataforma.\n\n'
                      '4.3. O cancelamento reiterado e injustificado de corridas poderá resultar na aplicação '
                      'de restrições temporárias ou permanentes à conta do Passageiro.\n\n'
                      '5. DA LIMITAÇÃO DE RESPONSABILIDADE\n\n'
                      '5.1. A UPPI não se responsabiliza por objetos esquecidos no veículo, cabendo ao '
                      'Passageiro entrar em contato diretamente com o motorista parceiro por meio da Plataforma.\n\n'
                      '5.2. A UPPI envida seus melhores esforços para manter a Plataforma em pleno funcionamento, '
                      'porém não garante a disponibilidade ininterrupta do serviço, podendo haver indisponibilidade '
                      'temporária por motivos de manutenção, atualização ou força maior.\n\n'
                      '5.3. A UPPI não se responsabiliza por atrasos, incidentes de trânsito, condições '
                      'climáticas adversas ou quaisquer outros eventos externos que possam impactar o tempo '
                      'ou a qualidade da viagem.',
                ),
                const SizedBox(height: 16),

                // ── 2. Política de Privacidade ────────────────
                _TermsSection(
                  icon: Icons.privacy_tip_rounded,
                  iconColor: cs.tertiary,
                  title: 'Política de Privacidade — LGPD',
                  content: 'POLÍTICA DE PRIVACIDADE E PROTEÇÃO DE DADOS PESSOAIS\n'
                      'Em conformidade com a Lei nº 13.709/2018 (Lei Geral de Proteção de Dados Pessoais — LGPD)\n\n'
                      'A UPPI MOBILIDADE LTDA. ("Controladora"), na qualidade de controladora de dados pessoais, '
                      'apresenta a presente Política de Privacidade com o objetivo de informar aos titulares de '
                      'dados — usuários da Plataforma UPPI, na condição de passageiros e/ou motoristas parceiros — '
                      'sobre o tratamento de seus dados pessoais, em observância aos princípios e fundamentos '
                      'estabelecidos nos artigos 2º e 6º da LGPD.\n\n'
                      '1. DEFINIÇÕES\n\n'
                      'Para os fins desta Política, aplicam-se as definições constantes do artigo 5º da LGPD, '
                      'especialmente:\n\n'
                      '• Dado Pessoal: informação relacionada a pessoa natural identificada ou identificável (art. 5º, I).\n\n'
                      '• Dado Pessoal Sensível: dado pessoal sobre origem racial ou étnica, convicção religiosa, '
                      'opinião política, filiação sindical, dado referente à saúde ou à vida sexual, dado genético '
                      'ou biométrico (art. 5º, II).\n\n'
                      '• Tratamento: toda operação realizada com dados pessoais, como coleta, produção, recepção, '
                      'classificação, utilização, acesso, reprodução, transmissão, distribuição, processamento, '
                      'arquivamento, armazenamento, eliminação, avaliação ou controle da informação (art. 5º, X).\n\n'
                      '• Controlador: pessoa natural ou jurídica a quem competem as decisões referentes ao '
                      'tratamento de dados pessoais (art. 5º, VI).\n\n'
                      '• Encarregado (DPO): pessoa indicada pelo controlador para atuar como canal de comunicação '
                      'entre o controlador, os titulares dos dados e a ANPD (art. 5º, VIII).\n\n'
                      '2. BASES LEGAIS PARA O TRATAMENTO\n\n'
                      'O tratamento de dados pessoais pela UPPI fundamenta-se nas seguintes bases legais previstas '
                      'no artigo 7º da LGPD:\n\n'
                      '• Execução de contrato ou de procedimentos preliminares relacionados a contrato do qual '
                      'seja parte o titular, a pedido do titular dos dados (art. 7º, V) — aplicável aos dados '
                      'necessários para a prestação do serviço de intermediação de transporte.\n\n'
                      '• Cumprimento de obrigação legal ou regulatória pelo controlador (art. 7º, II) — aplicável '
                      'à retenção de dados para fins fiscais, tributários e regulatórios.\n\n'
                      '• Exercício regular de direitos em processo judicial, administrativo ou arbitral (art. 7º, VI) — '
                      'aplicável à retenção de dados para defesa em eventuais litígios.\n\n'
                      '• Consentimento do titular (art. 7º, I) — aplicável ao tratamento de dados para '
                      'finalidades opcionais, como envio de comunicações de marketing, notificações promocionais '
                      'e relatórios de diagnóstico do aplicativo.\n\n'
                      '• Legítimo interesse do controlador (art. 7º, IX) — aplicável à análise de dados de uso '
                      'para melhoria contínua da Plataforma, prevenção a fraudes e garantia da segurança dos '
                      'usuários.\n\n'
                      '3. PRINCÍPIOS OBSERVADOS\n\n'
                      'Todo tratamento de dados pessoais realizado pela UPPI observa rigorosamente os princípios '
                      'elencados no artigo 6º da LGPD:\n\n'
                      '• Finalidade: tratamento realizado para propósitos legítimos, específicos, explícitos e '
                      'informados ao titular;\n\n'
                      '• Adequação: compatibilidade do tratamento com as finalidades informadas;\n\n'
                      '• Necessidade: limitação do tratamento ao mínimo necessário para a realização de suas '
                      'finalidades;\n\n'
                      '• Livre acesso: garantia de consulta facilitada e gratuita sobre a forma e a duração do '
                      'tratamento;\n\n'
                      '• Qualidade dos dados: garantia de exatidão, clareza, relevância e atualização dos dados;\n\n'
                      '• Transparência: informações claras, precisas e facilmente acessíveis sobre o tratamento;\n\n'
                      '• Segurança: utilização de medidas técnicas e administrativas aptas a proteger os dados;\n\n'
                      '• Prevenção: adoção de medidas para prevenir a ocorrência de danos;\n\n'
                      '• Não discriminação: impossibilidade de realização do tratamento para fins discriminatórios;\n\n'
                      '• Responsabilização e prestação de contas: demonstração da adoção de medidas eficazes e '
                      'capazes de comprovar a observância e o cumprimento das normas de proteção de dados pessoais.',
                ),
                const SizedBox(height: 16),

                // ── 3. Dados coletados e finalidade ───────────
                _TermsSection(
                  icon: Icons.storage_rounded,
                  iconColor: cs.secondary,
                  title: 'Dados Coletados e Finalidade (Art. 9º)',
                  isExpanded: true,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Em atendimento ao disposto no artigo 9º da LGPD, a UPPI informa de forma '
                        'clara e ostensiva as categorias de dados pessoais coletados, suas respectivas '
                        'finalidades e as bases legais que fundamentam cada tratamento:',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: cs.onSurface.withValues(alpha: 0.75),
                          height: 1.7,
                          fontSize: 15,
                        ),
                      ),
                      const SizedBox(height: 16),
                      ...LgpdConsent.dataCategories.map((item) {
                        return _DataItemTile(
                          dado: item['dado']!,
                          finalidade: item['finalidade']!,
                          baseLegal: item['base_legal']!,
                        );
                      }),
                    ],
                  ),
                ),
                const SizedBox(height: 16),

                // ── 4. Segurança da Informação ────────────────
                _TermsSection(
                  icon: Icons.security_rounded,
                  iconColor: Colors.orange.shade700,
                  title: 'Segurança da Informação e Prevenção a Fraudes',
                  content: 'MEDIDAS DE SEGURANÇA TÉCNICAS E ADMINISTRATIVAS\n'
                      'Conforme artigos 46 e 47 da LGPD\n\n'
                      'A UPPI adota medidas de segurança, técnicas e administrativas aptas a proteger os dados '
                      'pessoais de acessos não autorizados e de situações acidentais ou ilícitas de destruição, '
                      'perda, alteração, comunicação ou qualquer forma de tratamento inadequado ou ilícito, '
                      'conforme disposto no artigo 46 da LGPD.\n\n'
                      '1. MEDIDAS TÉCNICAS IMPLEMENTADAS\n\n'
                      '1.1. Criptografia: Todas as comunicações entre o dispositivo do usuário e os servidores '
                      'da UPPI são protegidas por protocolo TLS 1.3 (Transport Layer Security), garantindo a '
                      'confidencialidade e integridade dos dados em trânsito.\n\n'
                      '1.2. Armazenamento seguro: Os dados pessoais são armazenados em servidores com certificação '
                      'de segurança, protegidos por firewalls, sistemas de detecção e prevenção de intrusão (IDS/IPS) '
                      'e controles de acesso baseados em princípios de menor privilégio.\n\n'
                      '1.3. Backups: São realizados backups automáticos e regulares em localidades geograficamente '
                      'distintas, assegurando a disponibilidade e recuperação dos dados em caso de incidentes.\n\n'
                      '1.4. Autenticação: Implementação de mecanismos de autenticação robustos, incluindo '
                      'verificação por SMS/OTP para acesso às contas de usuários.\n\n'
                      '1.5. Monitoramento: Sistemas de monitoramento contínuo 24/7 para detecção de atividades '
                      'suspeitas, tentativas de invasão e comportamentos anômalos na Plataforma.\n\n'
                      '2. MEDIDAS ADMINISTRATIVAS\n\n'
                      '2.1. Política de acesso: Acesso aos dados pessoais restrito a colaboradores autorizados, '
                      'mediante assinatura de termo de confidencialidade e compromisso com as normas de proteção '
                      'de dados.\n\n'
                      '2.2. Treinamento: Programa periódico de conscientização e capacitação dos colaboradores '
                      'sobre proteção de dados pessoais e segurança da informação.\n\n'
                      '2.3. Verificação de identidade (KYC — Know Your Customer): Motoristas parceiros passam '
                      'por processo rigoroso de verificação de identidade, incluindo validação de documentos '
                      '(CNH, CRLV) e análise de antecedentes, em conformidade com as exigências regulatórias.\n\n'
                      '2.4. Sistema antifraude: Algoritmos de detecção de padrões suspeitos para prevenir uso '
                      'indevido da Plataforma, como criação de contas falsas, manipulação de corridas e '
                      'atividades fraudulentas.\n\n'
                      '3. COMUNICAÇÃO DE INCIDENTES\n\n'
                      '3.1. Em caso de incidente de segurança que possa acarretar risco ou dano relevante aos '
                      'titulares de dados, a UPPI comunicará à Autoridade Nacional de Proteção de Dados (ANPD) '
                      'e aos titulares afetados, em prazo razoável, conforme disposto no artigo 48 da LGPD.\n\n'
                      '3.2. A comunicação conterá, no mínimo: (i) a descrição da natureza dos dados pessoais '
                      'afetados; (ii) as informações sobre os titulares envolvidos; (iii) a indicação das medidas '
                      'técnicas e de segurança utilizadas; (iv) os riscos relacionados ao incidente; e (v) as '
                      'medidas que foram ou que serão adotadas para reverter ou mitigar os efeitos do prejuízo.',
                ),
                const SizedBox(height: 16),

                // ── 5. Direitos do Titular ────────────────────
                _TermsSection(
                  icon: Icons.gavel_rounded,
                  iconColor: cs.primary,
                  title: 'Direitos do Titular (Art. 18 LGPD)',
                  content: 'DOS DIREITOS DO TITULAR DE DADOS PESSOAIS\n'
                      'Conforme artigo 18 da Lei nº 13.709/2018\n\n'
                      'O titular dos dados pessoais tem direito a obter do controlador, em relação aos dados '
                      'do titular por ele tratados, a qualquer momento e mediante requisição:\n\n'
                      'I — CONFIRMAÇÃO DA EXISTÊNCIA DE TRATAMENTO\n'
                      'O titular tem direito a obter a confirmação da existência de tratamento de seus dados '
                      'pessoais pela UPPI. A confirmação será providenciada de forma clara e completa, no prazo '
                      'de até 15 (quinze) dias contados da data do requerimento do titular.\n\n'
                      'II — ACESSO AOS DADOS\n'
                      'O titular poderá requisitar acesso a todos os dados pessoais que a UPPI mantém a seu '
                      'respeito, obtendo cópia integral e legível das informações armazenadas, incluindo dados '
                      'cadastrais, histórico de corridas, registros de pagamento e logs de acesso.\n\n'
                      'III — CORREÇÃO DE DADOS INCOMPLETOS, INEXATOS OU DESATUALIZADOS\n'
                      'O titular tem direito a solicitar a correção de dados pessoais que estejam incompletos, '
                      'inexatos ou desatualizados. A UPPI procederá à correção imediata dos dados, mediante '
                      'comprovação pelo titular.\n\n'
                      'IV — ANONIMIZAÇÃO, BLOQUEIO OU ELIMINAÇÃO\n'
                      'O titular poderá solicitar a anonimização, bloqueio ou eliminação de dados desnecessários, '
                      'excessivos ou tratados em desconformidade com o disposto na LGPD. Ressalva-se que dados '
                      'necessários ao cumprimento de obrigação legal ou regulatória serão retidos pelo prazo '
                      'legalmente exigido.\n\n'
                      'V — PORTABILIDADE DOS DADOS\n'
                      'O titular tem direito a solicitar a portabilidade dos dados a outro fornecedor de serviço '
                      'ou produto, mediante requisição expressa, de acordo com a regulamentação da ANPD, '
                      'observados os segredos comercial e industrial.\n\n'
                      'VI — ELIMINAÇÃO DOS DADOS TRATADOS COM CONSENTIMENTO\n'
                      'O titular poderá solicitar a eliminação dos dados pessoais tratados com base no '
                      'consentimento (art. 7º, I), exceto nas hipóteses previstas no artigo 16 da LGPD.\n\n'
                      'VII — INFORMAÇÃO SOBRE COMPARTILHAMENTO\n'
                      'O titular tem direito a ser informado sobre as entidades públicas e privadas com as quais '
                      'o controlador realizou uso compartilhado de dados.\n\n'
                      'VIII — REVOGAÇÃO DO CONSENTIMENTO\n'
                      'O titular tem direito a revogar o consentimento a qualquer momento, mediante manifestação '
                      'expressa, por procedimento gratuito e facilitado, ratificados os tratamentos realizados '
                      'sob o amparo do consentimento anteriormente manifestado enquanto não houver requerimento '
                      'de eliminação.\n\n'
                      'CANAIS PARA EXERCÍCIO DOS DIREITOS\n\n'
                      'O titular poderá exercer seus direitos:\n'
                      '• Diretamente pelo aplicativo, em Configurações → Privacidade e Dados;\n'
                      '• Por e-mail ao Encarregado de Dados: ${LgpdConsent.dpoEmail};\n'
                      '• Os requerimentos serão atendidos no prazo de até 15 (quinze) dias, conforme '
                      'art. 18, §5º da LGPD.',
                ),
                const SizedBox(height: 16),

                // ── 6. Uso de Localização ─────────────────────
                _TermsSection(
                  icon: Icons.location_on_rounded,
                  iconColor: Colors.red.shade600,
                  title: 'Tratamento de Dados de Geolocalização',
                  content: 'POLÍTICA DE USO DE DADOS DE LOCALIZAÇÃO\n\n'
                      'A UPPI realiza o tratamento de dados de geolocalização precisa (GPS) do dispositivo '
                      'do titular, com fundamento na base legal de execução de contrato (art. 7º, V, LGPD), '
                      'por ser dado essencial e indispensável à prestação do serviço de intermediação de '
                      'transporte individual de passageiros.\n\n'
                      '1. FINALIDADES DO TRATAMENTO DE GEOLOCALIZAÇÃO\n\n'
                      '1.1. Identificação da posição geográfica atual do passageiro para exibição de '
                      'motoristas parceiros disponíveis nas proximidades.\n\n'
                      '1.2. Cálculo automatizado de rotas otimizadas, estimativas de tempo de chegada (ETA) '
                      'e estimativas de preço da corrida.\n\n'
                      '1.3. Acompanhamento da corrida em tempo real (tracking), permitindo que o passageiro '
                      'monitore o trajeto e compartilhe sua localização com contatos de confiança para '
                      'fins de segurança pessoal.\n\n'
                      '1.4. Cálculo da tarifa final com base na distância efetivamente percorrida e no '
                      'tempo de viagem, assegurando precisão e transparência na cobrança.\n\n'
                      '1.5. Geração de registros de corrida para fins de auditoria, resolução de disputas '
                      'e atendimento a requisições judiciais ou regulatórias.\n\n'
                      '2. CONDIÇÕES DO TRATAMENTO\n\n'
                      '2.1. A coleta de dados de geolocalização ocorre exclusivamente quando o aplicativo '
                      'está em uso ativo pelo titular (foreground), mediante concessão prévia e expressa '
                      'da permissão de localização no sistema operacional do dispositivo.\n\n'
                      '2.2. O titular poderá revogar a permissão de acesso à localização a qualquer momento '
                      'por meio das configurações do sistema operacional de seu dispositivo. Contudo, a '
                      'revogação impossibilitará a utilização das funcionalidades essenciais da Plataforma '
                      'que dependem de dados de geolocalização.\n\n'
                      '2.3. Os dados de geolocalização são armazenados de forma associada ao registro da '
                      'corrida e retidos pelo prazo necessário ao cumprimento das finalidades descritas, '
                      'observados os prazos legais de retenção aplicáveis.\n\n'
                      '3. COMPARTILHAMENTO DE DADOS DE LOCALIZAÇÃO\n\n'
                      '3.1. Durante a corrida, a localização do passageiro é compartilhada com o motorista '
                      'parceiro exclusivamente para fins de embarque e navegação.\n\n'
                      '3.2. A UPPI não comercializa, cede ou compartilha dados de geolocalização com '
                      'terceiros para finalidades de marketing, publicidade direcionada ou qualquer '
                      'outra finalidade não relacionada à prestação do serviço.',
                ),
                const SizedBox(height: 16),

                // ── 7. Pagamentos ─────────────────────────────
                _TermsSection(
                  icon: Icons.payment_rounded,
                  iconColor: Colors.green.shade700,
                  title: 'Pagamentos, Cobranças e Política de Reembolso',
                  content: 'TERMOS DE PAGAMENTO E POLÍTICA FINANCEIRA\n\n'
                      '1. FORMAS DE PAGAMENTO\n\n'
                      '1.1. A Plataforma UPPI disponibiliza as seguintes modalidades de pagamento para '
                      'as corridas realizadas:\n'
                      '   a) PIX — transferência instantânea;\n'
                      '   b) Cartão de crédito — bandeiras Visa, Mastercard, Elo e American Express;\n'
                      '   c) Cartão de débito — quando disponível pela operadora;\n'
                      '   d) Dinheiro — pagamento presencial ao motorista parceiro.\n\n'
                      '1.2. A UPPI poderá, a seu exclusivo critério, disponibilizar outras formas de '
                      'pagamento, mediante prévia comunicação aos usuários.\n\n'
                      '2. PROCESSAMENTO DE PAGAMENTOS\n\n'
                      '2.1. O processamento de pagamentos eletrônicos é realizado por operadoras '
                      'de pagamento terceirizadas, devidamente certificadas pelo padrão PCI-DSS (Payment '
                      'Card Industry Data Security Standard), assegurando a proteção dos dados financeiros '
                      'dos usuários.\n\n'
                      '2.2. A UPPI declara que NÃO armazena em seus servidores os dados completos de cartões '
                      'de crédito ou débito dos usuários. Os dados de pagamento são tokenizados e '
                      'armazenados exclusivamente nos sistemas das operadoras de pagamento parceiras.\n\n'
                      '3. CÁLCULO DA TARIFA\n\n'
                      '3.1. O valor da corrida é calculado automaticamente pela Plataforma com base nos '
                      'seguintes parâmetros:\n'
                      '   a) Tarifa base: valor fixo inicial aplicável a todas as corridas;\n'
                      '   b) Valor por quilômetro: aplicado sobre a distância total percorrida;\n'
                      '   c) Valor por minuto: aplicado sobre o tempo total da corrida;\n'
                      '   d) Taxa de espera: cobrada quando o motorista aguarda além do tempo de tolerância;\n'
                      '   e) Pedágios: repassados integralmente ao passageiro, quando aplicável;\n'
                      '   f) Tarifa dinâmica: multiplicador aplicável em períodos de alta demanda.\n\n'
                      '3.2. O valor estimado da corrida é informado ao passageiro antes da confirmação '
                      'da solicitação. O valor final poderá sofrer alteração em razão de mudanças no '
                      'trajeto, tempo de espera ou condições de tráfego.\n\n'
                      '4. CONTESTAÇÕES E REEMBOLSOS\n\n'
                      '4.1. Contestações de cobrança deverão ser realizadas pelo canal de suporte do '
                      'aplicativo no prazo de até 7 (sete) dias corridos após a realização da corrida.\n\n'
                      '4.2. Solicitações de reembolso serão analisadas individualmente pela equipe de '
                      'suporte da UPPI, que poderá solicitar informações adicionais para instrução do '
                      'procedimento.\n\n'
                      '4.3. Reembolsos aprovados serão processados na mesma forma de pagamento utilizada '
                      'na corrida original, no prazo de até 10 (dez) dias úteis.',
                ),
                const SizedBox(height: 16),

                // ── 8. Retenção e eliminação ──────────────────
                _TermsSection(
                  icon: Icons.delete_sweep_rounded,
                  iconColor: Colors.deepPurple,
                  title: 'Retenção e Eliminação de Dados (Art. 15 e 16)',
                  content: 'POLÍTICA DE RETENÇÃO E ELIMINAÇÃO DE DADOS PESSOAIS\n'
                      'Conforme artigos 15 e 16 da LGPD\n\n'
                      '1. PRAZOS DE RETENÇÃO\n\n'
                      '1.1. Os dados pessoais serão retidos apenas pelo período necessário ao cumprimento '
                      'das finalidades para as quais foram coletados, observando-se os seguintes prazos '
                      'mínimos:\n\n'
                      '• Dados cadastrais: mantidos durante a vigência da conta do usuário e por até '
                      '5 (cinco) anos após o encerramento, para fins de cumprimento de obrigações legais '
                      'e exercício regular de direitos (art. 16, I e II).\n\n'
                      '• Registros de corridas: mantidos por 5 (cinco) anos, em conformidade com o '
                      'Código de Defesa do Consumidor (art. 27, Lei nº 8.078/1990) e legislação fiscal.\n\n'
                      '• Dados financeiros e fiscais: mantidos pelo prazo legal de 5 (cinco) anos, '
                      'conforme legislação tributária federal (art. 173, CTN).\n\n'
                      '• Registros de acesso (logs): mantidos pelo prazo mínimo de 6 (seis) meses, '
                      'conforme Marco Civil da Internet (art. 15, Lei nº 12.965/2014).\n\n'
                      '• Dados de geolocalização: mantidos pelo prazo de 1 (um) ano, para fins de '
                      'auditoria e resolução de disputas.\n\n'
                      '2. ELIMINAÇÃO\n\n'
                      '2.1. Decorridos os prazos de retenção, os dados pessoais serão eliminados de '
                      'forma segura e irreversível, mediante procedimentos de sanitização que garantem '
                      'a impossibilidade de recuperação.\n\n'
                      '2.2. O titular poderá solicitar a eliminação antecipada de seus dados a qualquer '
                      'momento, ressalvadas as hipóteses legais de conservação previstas no artigo 16 da LGPD.\n\n'
                      '2.3. A exclusão da conta do usuário acarretará a eliminação dos dados pessoais '
                      'que não estejam sujeitos a obrigação legal de retenção, no prazo de até 30 (trinta) '
                      'dias corridos após a solicitação.',
                ),
                const SizedBox(height: 16),

                // ── 9. Compartilhamento com terceiros ─────────
                _TermsSection(
                  icon: Icons.share_rounded,
                  iconColor: Colors.teal,
                  title: 'Compartilhamento de Dados com Terceiros',
                  content: 'DO COMPARTILHAMENTO E TRANSFERÊNCIA DE DADOS PESSOAIS\n'
                      'Conforme artigos 26 a 28 e 33 a 36 da LGPD\n\n'
                      '1. HIPÓTESES DE COMPARTILHAMENTO\n\n'
                      '1.1. A UPPI poderá compartilhar dados pessoais dos titulares exclusivamente nas '
                      'seguintes hipóteses:\n\n'
                      '• Motoristas parceiros: compartilhamento do nome e localização do passageiro '
                      'durante a corrida, estritamente para fins de prestação do serviço de transporte.\n\n'
                      '• Processadoras de pagamento: compartilhamento de dados financeiros tokenizados '
                      'para processamento de cobranças, por operadoras certificadas PCI-DSS.\n\n'
                      '• Autoridades públicas: compartilhamento de dados pessoais em cumprimento a '
                      'obrigação legal, decisão judicial ou determinação da ANPD, conforme previsto na LGPD.\n\n'
                      '• Prestadores de serviços essenciais: compartilhamento limitado com provedores '
                      'de infraestrutura tecnológica (servidores, banco de dados, CDN) e serviços de '
                      'comunicação (SMS, e-mail), mediante contratos que assegurem nível equivalente de '
                      'proteção aos dados pessoais.\n\n'
                      '2. VEDAÇÕES\n\n'
                      '2.1. A UPPI declara expressamente que NÃO:\n'
                      '   a) Vende, comercializa ou negocia dados pessoais de seus usuários a terceiros;\n'
                      '   b) Compartilha dados pessoais para fins de publicidade direcionada de terceiros;\n'
                      '   c) Transfere dados pessoais para países que não ofereçam grau de proteção '
                      'adequado, salvo nas hipóteses autorizadas pela LGPD (art. 33);\n'
                      '   d) Utiliza dados pessoais para formação de perfis comportamentais destinados '
                      'a discriminação de qualquer natureza.\n\n'
                      '3. OPERADORES DE DADOS\n\n'
                      '3.1. Os terceiros que realizam tratamento de dados pessoais em nome da UPPI '
                      '(operadores) estão vinculados a contratos que estabelecem obrigações de '
                      'confidencialidade, segurança e conformidade com a LGPD, respondendo solidariamente '
                      'por eventuais violações.',
                ),
                const SizedBox(height: 16),

                // ── 10. Disposições Gerais ────────────────────
                _TermsSection(
                  icon: Icons.menu_book_rounded,
                  iconColor: cs.onSurface.withValues(alpha: 0.7),
                  title: 'Disposições Gerais e Foro',
                  content: 'CLÁUSULAS GERAIS E FINAIS\n\n'
                      '1. ALTERAÇÕES NOS TERMOS\n\n'
                      '1.1. A UPPI reserva-se o direito de alterar os presentes Termos de Uso e a Política '
                      'de Privacidade a qualquer momento, mediante comunicação prévia aos usuários por '
                      'meio de notificação no aplicativo e/ou e-mail cadastrado.\n\n'
                      '1.2. As alterações entrarão em vigor na data de sua publicação. A continuidade do '
                      'uso da Plataforma após a publicação das alterações será considerada como aceitação '
                      'tácita dos novos termos.\n\n'
                      '1.3. Alterações substanciais que impliquem em novas finalidades de tratamento de '
                      'dados pessoais ou redução de direitos dos titulares exigirão novo consentimento '
                      'expresso do usuário.\n\n'
                      '2. LEI APLICÁVEL E FORO\n\n'
                      '2.1. Os presentes Termos de Uso e a Política de Privacidade são regidos pelas leis '
                      'da República Federativa do Brasil, em especial pela Lei nº 13.709/2018 (LGPD), '
                      'pelo Código de Defesa do Consumidor (Lei nº 8.078/1990), pelo Marco Civil da '
                      'Internet (Lei nº 12.965/2014) e pelo Código Civil Brasileiro (Lei nº 10.406/2002).\n\n'
                      '2.2. Fica eleito o foro da Comarca de Castanhal, Estado do Pará, para dirimir '
                      'quaisquer questões oriundas dos presentes Termos, com renúncia expressa a qualquer '
                      'outro, por mais privilegiado que seja.\n\n'
                      '3. CONTATO\n\n'
                      'Controlador: ${LgpdConsent.controllerName}\n'
                      'Encarregado de Dados (DPO): ${LgpdConsent.dpoEmail}\n'
                      'Endereço: Castanhal — PA, Brasil\n\n'
                      '4. VIGÊNCIA\n\n'
                      '4.1. Os presentes Termos entram em vigor na data de sua publicação e permanecerão '
                      'vigentes por prazo indeterminado, até que sejam substituídos por nova versão.\n\n'
                      'Castanhal/PA, 29 de maio de 2025.\n\n'
                      'UPPI MOBILIDADE LTDA.',
                ),
                const SizedBox(height: 16),

                // ── DPO Contact ───────────────────────────────
                _DpoContactCard(),
                const SizedBox(height: 16),

                // ── Links oficiais ────────────────────────────
                _ExternalLinksCard(onOpenUrl: _openUrl),
                const SizedBox(height: 40),
              ]),
            ),
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// Subwidgets
// ═══════════════════════════════════════════════════════════════════════════════

/// Seção expansível de termos
class _TermsSection extends StatefulWidget {
  final IconData icon;
  final Color iconColor;
  final String title;
  final String? content;
  final Widget? child;
  final bool isExpanded;

  const _TermsSection({
    required this.icon,
    required this.iconColor,
    required this.title,
    this.content,
    this.child,
    this.isExpanded = false,
  });

  @override
  State<_TermsSection> createState() => _TermsSectionState();
}

class _TermsSectionState extends State<_TermsSection>
    with SingleTickerProviderStateMixin {
  late bool _expanded;
  late final AnimationController _expandController;
  late final Animation<double> _expandAnim;

  @override
  void initState() {
    super.initState();
    _expanded = widget.isExpanded;
    _expandController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
      value: _expanded ? 1.0 : 0.0,
    );
    _expandAnim = CurvedAnimation(
      parent: _expandController,
      curve: Curves.easeInOut,
    );
  }

  @override
  void dispose() {
    _expandController.dispose();
    super.dispose();
  }

  void _toggle() {
    setState(() {
      _expanded = !_expanded;
      if (_expanded) {
        _expandController.forward();
      } else {
        _expandController.reverse();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return Container(
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: _expanded
              ? widget.iconColor.withValues(alpha: 0.3)
              : cs.outline.withValues(alpha: 0.15),
          width: _expanded ? 1.5 : 1,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        children: [
          // Header (sempre visível)
          InkWell(
            onTap: _toggle,
            borderRadius: BorderRadius.circular(16),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: widget.iconColor.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(
                      widget.icon,
                      color: widget.iconColor,
                      size: 22,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Text(
                      widget.title,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: cs.onSurface,
                        fontSize: 15,
                      ),
                    ),
                  ),
                  AnimatedRotation(
                    turns: _expanded ? 0.5 : 0.0,
                    duration: const Duration(milliseconds: 300),
                    child: Icon(
                      Icons.keyboard_arrow_down_rounded,
                      color: cs.onSurface.withValues(alpha: 0.5),
                    ),
                  ),
                ],
              ),
            ),
          ),

          // Conteúdo expansível
          SizeTransition(
            sizeFactor: _expandAnim,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Divider(
                    color: cs.outline.withValues(alpha: 0.1),
                    height: 1,
                  ),
                  const SizedBox(height: 16),
                  if (widget.content != null)
                    Text(
                      widget.content!,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: cs.onSurface.withValues(alpha: 0.75),
                        height: 1.7,
                        fontSize: 15,
                      ),
                    ),
                  if (widget.child != null) widget.child!,
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Tile para exibir dados coletados com base legal
class _DataItemTile extends StatelessWidget {
  final String dado;
  final String finalidade;
  final String baseLegal;

  const _DataItemTile({
    required this.dado,
    required this.finalidade,
    required this.baseLegal,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            dado,
            style: theme.textTheme.bodyMedium?.copyWith(
              fontWeight: FontWeight.w700,
              fontSize: 15,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            finalidade,
            style: theme.textTheme.bodySmall?.copyWith(
              color: cs.onSurface.withValues(alpha: 0.65),
              height: 1.4,
              fontSize: 13,
            ),
          ),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: cs.primaryContainer.withValues(alpha: 0.5),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              baseLegal,
              style: theme.textTheme.labelSmall?.copyWith(
                color: cs.primary,
                fontWeight: FontWeight.w600,
                fontSize: 11,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Card de contato do DPO
class _DpoContactCard extends StatelessWidget {
  Future<void> _sendEmail() async {
    final uri = Uri(
      scheme: 'mailto',
      path: LgpdConsent.dpoEmail,
      queryParameters: {
        'subject': 'Direitos LGPD — Solicitação do Titular',
        'body':
            'Ilmo(a). Sr(a). Encarregado(a) de Dados,\n\n'
            'Eu, [SEU NOME COMPLETO], titular de dados pessoais tratados pela UPPI MOBILIDADE LTDA., '
            'venho, com fundamento no artigo 18 da Lei nº 13.709/2018 (LGPD), exercer o seguinte direito:\n\n'
            '[ ] Confirmação da existência de tratamento\n'
            '[ ] Acesso aos dados\n'
            '[ ] Correção de dados\n'
            '[ ] Anonimização, bloqueio ou eliminação\n'
            '[ ] Portabilidade\n'
            '[ ] Eliminação dos dados tratados com consentimento\n'
            '[ ] Informação sobre compartilhamento\n'
            '[ ] Revogação do consentimento\n\n'
            'Descreva sua solicitação:\n\n'
            'Atenciosamente,',
      },
    );
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            cs.primaryContainer.withValues(alpha: 0.5),
            cs.primaryContainer.withValues(alpha: 0.2),
          ],
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: cs.primary.withValues(alpha: 0.15),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: cs.primary.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  Icons.contact_mail_rounded,
                  color: cs.primary,
                  size: 22,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Encarregado de Dados (DPO)',
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                        fontSize: 15,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Conforme Art. 41 — LGPD',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: cs.onSurface.withValues(alpha: 0.5),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Text(
            LgpdConsent.controllerName,
            style: theme.textTheme.bodyMedium?.copyWith(
              fontWeight: FontWeight.w600,
              fontSize: 15,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            LgpdConsent.dpoEmail,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: cs.primary,
              fontSize: 14,
            ),
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: _sendEmail,
              icon: const Icon(Icons.email_outlined, size: 18),
              label: const Text('Enviar solicitação formal ao DPO'),
              style: OutlinedButton.styleFrom(
                foregroundColor: cs.primary,
                side: BorderSide(color: cs.primary.withValues(alpha: 0.4)),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                padding: const EdgeInsets.symmetric(vertical: 12),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Card de links externos (Privacidade / Termos)
class _ExternalLinksCard extends StatelessWidget {
  final Future<void> Function(String url) onOpenUrl;

  const _ExternalLinksCard({required this.onOpenUrl});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: cs.outline.withValues(alpha: 0.15),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Documentos oficiais',
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w700,
              fontSize: 14,
              color: cs.onSurface.withValues(alpha: 0.6),
            ),
          ),
          const SizedBox(height: 12),
          _LinkTile(
            icon: Icons.privacy_tip_outlined,
            label: 'Política de Privacidade Completa',
            subtitle: 'uppimobilidade.com.br/privacidade',
            onTap: () => onOpenUrl(LgpdConsent.privacyPolicyUrl),
          ),
          const Divider(height: 1),
          _LinkTile(
            icon: Icons.article_outlined,
            label: 'Termos de Uso Completos',
            subtitle: 'uppimobilidade.com.br/termos',
            onTap: () => onOpenUrl(LgpdConsent.termsOfServiceUrl),
          ),
          const Divider(height: 1),
          _LinkTile(
            icon: Icons.cookie_outlined,
            label: 'Política de Cookies',
            subtitle: 'uppimobilidade.com.br/privacidade#cookies',
            onTap: () => onOpenUrl(LgpdConsent.cookiePolicyUrl),
          ),
        ],
      ),
    );
  }
}

/// Tile de link externo
class _LinkTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final String subtitle;
  final VoidCallback onTap;

  const _LinkTile({
    required this.icon,
    required this.label,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(icon, color: cs.primary, size: 22),
      title: Text(
        label,
        style: TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w600,
          color: cs.onSurface,
        ),
      ),
      subtitle: Text(
        subtitle,
        style: TextStyle(
          fontSize: 11,
          color: cs.onSurface.withValues(alpha: 0.4),
        ),
      ),
      trailing: Icon(
        Icons.open_in_new_rounded,
        size: 16,
        color: cs.onSurface.withValues(alpha: 0.4),
      ),
      onTap: onTap,
    );
  }
}
