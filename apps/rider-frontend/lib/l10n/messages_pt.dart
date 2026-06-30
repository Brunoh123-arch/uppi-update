// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'messages.dart';

// ignore_for_file: type=lint

/// The translations for Portuguese (`pt`).
class SPt extends S {
  SPt([String locale = 'pt']) : super(locale);

  @override
  String copyright_notice(Object company) {
    return 'Copyright © $company, Todos os direitos reservados.';
  }

  @override
  String get welcomeTitle => 'Bem-vindo ao Uppi';

  @override
  String get today => 'Hoje';

  @override
  String get yesterday => 'Ontem';

  @override
  String get settings => 'Configurações';

  @override
  String get about => 'Sobre';

  @override
  String get profileInfo => 'Informações do perfil';

  @override
  String get language => 'Idioma';

  @override
  String get firstName => 'Nome';

  @override
  String get lastName => 'Sobrenome';

  @override
  String get mobileNumber => 'Número de celular';

  @override
  String get edit => 'Editar';

  @override
  String get enterCode => 'Digite o código';

  @override
  String get editProfile => 'Editar Perfil';

  @override
  String get bankTransfer => 'Pix (Transferência)';

  @override
  String get gift => 'Presente';

  @override
  String get correction => 'Correção';

  @override
  String get inappPayment => 'Pagamento pelo app';

  @override
  String get orderFee => 'Taxa da corrida';

  @override
  String get parkingFee => 'Taxa de estacionamento';

  @override
  String get cancellationFee => 'Taxa de cancelamento';

  @override
  String get withdraw => 'Sacar';

  @override
  String get walletTransactions => 'Transações da carteira';

  @override
  String get addCard => 'Adicionar cartão';

  @override
  String get visa => 'Visa';

  @override
  String get mastercard => 'Mastercard';

  @override
  String get addBalance => 'Adicionar saldo';

  @override
  String durationInMinutes(num minutes) {
    final intl.NumberFormat minutesNumberFormat = intl.NumberFormat.compact(
      locale: localeName,
    );
    final String minutesString = minutesNumberFormat.format(minutes);

    String _temp0 = intl.Intl.pluralLogic(
      minutes,
      locale: localeName,
      other: '$minutesString Minutos',
      one: '$minutesString Minuto',
      zero: 'Zero minutos',
    );
    return '$_temp0';
  }

  @override
  String durationInHours(num hours) {
    final intl.NumberFormat hoursNumberFormat = intl.NumberFormat.compact(
      locale: localeName,
    );
    final String hoursString = hoursNumberFormat.format(hours);

    String _temp0 = intl.Intl.pluralLogic(
      hours,
      locale: localeName,
      other: '$hoursString Horas',
      one: '$hoursString Hora',
      zero: 'Zero horas',
    );
    return 'Duração: $_temp0';
  }

  @override
  String get timePastDue => 'Atrasado';

  @override
  String get justNow => 'Agora mesmo';

  @override
  String distanceInMeters(num distance) {
    final intl.NumberFormat distanceNumberFormat = intl.NumberFormat.compact(
      locale: localeName,
    );
    final String distanceString = distanceNumberFormat.format(distance);

    return '$distanceString m';
  }

  @override
  String distanceInKilometers(num distance) {
    final intl.NumberFormat distanceNumberFormat = intl.NumberFormat.compact(
      locale: localeName,
    );
    final String distanceString = distanceNumberFormat.format(distance);

    return '$distanceString km';
  }

  @override
  String distanceInFeets(num distance) {
    final intl.NumberFormat distanceNumberFormat = intl.NumberFormat.compact(
      locale: localeName,
    );
    final String distanceString = distanceNumberFormat.format(distance);

    return '$distanceString pés';
  }

  @override
  String distanceInMiles(num distance) {
    final intl.NumberFormat distanceNumberFormat = intl.NumberFormat.compact(
      locale: localeName,
    );
    final String distanceString = distanceNumberFormat.format(distance);

    return '$distanceString mi';
  }

  @override
  String get welcomeSubtitle =>
      'Seu app de mobilidade urbana. Viaje com conforto e segurança pelos melhores motoristas da sua cidade';

  @override
  String get onboardingRewardTitle => 'Ganhe recompensas!';

  @override
  String get onboardingRewardSubtitle =>
      'Ganhe bônus por indicar amigos, completar corridas e muito mais...';

  @override
  String get selectLanguage => 'Selecionar idioma';

  @override
  String get searchForLanguage => 'Buscar idioma';

  @override
  String get enterPhoneNumber => 'Digite seu número de celular';

  @override
  String get actionContinue => 'Continuar';

  @override
  String get whereIsYourDestination => 'Para onde você vai?';

  @override
  String get whereAreYouGoing => 'Para onde você vai?';

  @override
  String get selectDestinations => 'Sua rota';

  @override
  String get pickupPoint => 'Ponto de partida';

  @override
  String get enterPickupPoint => 'Digite o ponto de partida';

  @override
  String get dropoffPoint => 'Destino';

  @override
  String get enterDropoffPoint => 'Digite o destino';

  @override
  String get stopPoint => 'Parada';

  @override
  String get enterStopPoint => 'Digite a parada';

  @override
  String get confirm => 'Confirmar';

  @override
  String get confirmDropoff => 'Confirmar destino';

  @override
  String get confirmPickup => 'Confirmar partida';

  @override
  String get confirmArrival => 'Confirmar chegada';

  @override
  String get enterAtLeast3Characters => 'Digite pelo menos 3 caracteres';

  @override
  String get noResults => 'Nenhum resultado';

  @override
  String get bookNow => 'Pedir agora';

  @override
  String get cash => 'Dinheiro';

  @override
  String get online => 'Online';

  @override
  String get offline => 'Offline';

  @override
  String get onTrip => 'Em corrida';

  @override
  String get confirmPay => 'Confirmar e Pagar';

  @override
  String get cancel => 'Cancelar';

  @override
  String get apply => 'Aplicar';

  @override
  String get enterCouponCode => 'Digite o código do cupom';

  @override
  String get reserveRide => 'Agendar corrida';

  @override
  String get reserveRideMessage =>
      'Selecione a data e hora exatas para agendar sua corrida';

  @override
  String get reserveRideMessageSuccess =>
      'Sua corrida foi agendada com sucesso. Você pode ver suas corridas agendadas na seção \'Corridas agendadas\'.';

  @override
  String get cancelReservation => 'Cancelar agendamento';

  @override
  String get confirmResrve => 'Confirmar e agendar';

  @override
  String get enterCouponDescription =>
      'Insira o código do cupom para aplicar desconto';

  @override
  String get enterCoupon => 'Inserir cupom';

  @override
  String get couponApplied => 'Cupom aplicado';

  @override
  String get couponAppliedDescription =>
      'O cupom foi aplicado à tarifa da sua corrida';

  @override
  String get done => 'Pronto!';

  @override
  String get ridePreferences => 'Preferências da corrida';

  @override
  String get noWaitTime => 'Sem tempo de espera';

  @override
  String minutesRange(String minutes) {
    return '$minutes minutos';
  }

  @override
  String secondsRange(String seconds) {
    return '$seconds segundos';
  }

  @override
  String get rideRequested => 'Corrida solicitada';

  @override
  String get searchingForAnOnlineDriver =>
      'Procurando um motorista disponível...';

  @override
  String get cancelRide => 'Cancelar corrida';

  @override
  String get rideSafety => 'Segurança da corrida';

  @override
  String get shareTripInformation => 'Compartilhar informações da corrida';

  @override
  String get shareTripInformationDescription =>
      'Compartilhe os dados da sua corrida com alguém de confiança';

  @override
  String get sos => 'SOS';

  @override
  String get sosDescription => 'Avise as autoridades sobre uma emergência';

  @override
  String get reportAnIssue => 'Relatar um problema';

  @override
  String get reportAnIssueMidTripDescription =>
      'Informe um problema de segurança durante a corrida';

  @override
  String get rideOptions => 'Opções da corrida';

  @override
  String get goBackToRide => 'Voltar para a corrida';

  @override
  String get waitTime => 'Tempo de espera';

  @override
  String get couponCode => 'Código do cupom';

  @override
  String get giftCardCode => 'Código do vale-presente';

  @override
  String get nicePoints => 'Pontos positivos';

  @override
  String get negativePoints => 'Pontos negativos';

  @override
  String get reviewCommentBoxHint => 'Adicione um comentário...';

  @override
  String get howWasYourTrip => 'Como foi sua corrida?';

  @override
  String oneStarReviewTitle(String name) {
    return 'Corrida péssima com $name';
  }

  @override
  String twoStarReviewTitle(String name) {
    return 'Corrida ruim com $name';
  }

  @override
  String threeStarReviewTitle(String name) {
    return 'Corrida regular com $name';
  }

  @override
  String fourStarReviewTitle(String name) {
    return 'Boa corrida com $name';
  }

  @override
  String fiveStarReviewTitle(String name) {
    return 'Corrida excelente com $name';
  }

  @override
  String get submitFeedback => 'Enviar avaliação';

  @override
  String get typeAMessage => 'Digite uma mensagem';

  @override
  String get findAnotherRide => 'Buscar outra corrida';

  @override
  String get next => 'Próximo';

  @override
  String get searchForDropoffLocation => 'Buscar local de destino';

  @override
  String get searchForPickupLocation => 'Buscar local de partida';

  @override
  String get placeConfirmDialogPlaceholder => 'Qual é o seu destino?';

  @override
  String get noAnnouncements => 'Nenhum aviso';

  @override
  String get announcements => 'Avisos';

  @override
  String reviewsCount(int count) {
    return '($count avaliações)';
  }

  @override
  String get tripDetails => 'Detalhes da corrida';

  @override
  String get rideDetails => 'Detalhes da corrida';

  @override
  String get orderARide => 'Pedir uma corrida';

  @override
  String get noRidesYet => 'Nenhuma corrida ainda!';

  @override
  String get issueSubjectPlaceholder => 'Digite o assunto do problema';

  @override
  String get issueContentPlaceholder => 'Descreva o problema';

  @override
  String get reportThisIssue => 'Relatar este problema';

  @override
  String get fieldIsRequired => 'Campo obrigatório';

  @override
  String get ok => 'OK';

  @override
  String get favoriteLocations => 'Locais favoritos';

  @override
  String get favoriteLocationsSubtitle =>
      'Salve seus locais favoritos para acesso rápido';

  @override
  String get createAFavoriteLocation => 'Criar local favorito';

  @override
  String get addressTitleLabel => 'Nome do endereço';

  @override
  String get clickToSetLocation => 'Toque para definir o local';

  @override
  String get whereIsYourNewFavoriteLocation =>
      'Onde fica o seu novo local favorito?';

  @override
  String get locateFavoriteLocationDescription =>
      'Use a busca abaixo ou o mapa para marcar a localização exata';

  @override
  String get searchLocation => 'Buscar localização';

  @override
  String get saveChanges => 'Salvar alterações';

  @override
  String get rideHistory => 'Histórico de corridas';

  @override
  String get scheduledRides => 'Corridas agendadas';

  @override
  String get keepTheOrder => 'Manter pedido';

  @override
  String get cancelTheRide => 'Cancelar corrida';

  @override
  String get walletBalance => 'Saldo da carteira';

  @override
  String get activities => 'Atividades';

  @override
  String get pleaseEnterGiftCardCode => 'Digite o código do vale-presente';

  @override
  String get redeem => 'Resgatar';

  @override
  String get enterGiftCardCode => 'Código do vale-presente';

  @override
  String get redeemGiftCard => 'Resgatar';

  @override
  String get redeemGiftCardDescription =>
      'Digite o código do seu vale-presente para resgatá-lo.';

  @override
  String get redeemSuccessTitle => 'Vale-presente resgatado!';

  @override
  String redeemSuccessDescription(String amount) {
    return 'Você resgatou com sucesso o vale-presente de $amount.';
  }

  @override
  String get addCredit => 'Adicionar';

  @override
  String get payNow => 'Pagar agora';

  @override
  String get addCreditToWallet => 'Adicionar crédito à carteira';

  @override
  String get pleaseSelectAmount => 'Selecione o valor';

  @override
  String get enterAmount => 'Digite o valor';

  @override
  String get selectAmount => 'Selecione o valor:';

  @override
  String get wallet => 'Carteira';

  @override
  String get totalRides => 'Total de corridas';

  @override
  String get appSettings => 'Configurações do app';

  @override
  String get mapSettings => 'Configurações do mapa';

  @override
  String get lanugageSettings => 'Configurações de idioma';

  @override
  String get paymentMethods => 'Formas de pagamento';

  @override
  String get selectCards => 'Selecionar cartões';

  @override
  String get selectCardsDescription =>
      'Selecione os cartões que deseja exibir como formas de pagamento.';

  @override
  String get delete => 'Excluir';

  @override
  String get nameOnCard => 'Nome no cartão';

  @override
  String get profile => 'Perfil';

  @override
  String get scheduledRide => 'Corrida agendada';

  @override
  String get addPaymentMethod => 'Adicionar forma de pagamento';

  @override
  String get addPaymentMethodDescription =>
      'Adicione uma nova forma de pagamento à sua conta';

  @override
  String get saveCard => 'Salvar cartão';

  @override
  String get selectDialCode => 'Selecionar código do país';

  @override
  String get searchCountryName => 'Buscar país';

  @override
  String get preferences => 'Preferências:';

  @override
  String get onboardingDescription =>
      'Falta pouco para criar sua conta e aproveitar corridas com conforto e segurança';

  @override
  String get signInSignUp => 'Entrar / Cadastrar';

  @override
  String get enterOtp => 'Digite o código';

  @override
  String get enterPassword => 'Digite a senha';

  @override
  String get enterPasswordDescription =>
      'Por favor, digite sua senha para continuar';

  @override
  String get setPassword => 'Criar senha';

  @override
  String get password => 'Senha';

  @override
  String get passwordRuleDescription => 'Inclua pelo menos dois dos seguintes:';

  @override
  String get passwordRuleLength => 'Entre 9 e 64 caracteres';

  @override
  String get passwordRuleUpperCase => 'Letras maiúsculas';

  @override
  String get passwordRuleLowerCase => 'Letras minúsculas';

  @override
  String get passwordRuleNumber => 'Números';

  @override
  String get passwordRuleSpecialCharacter => 'Caracteres especiais';

  @override
  String get contactDetails => 'Dados pessoais';

  @override
  String get vehicleDetails => 'Dados do veículo';

  @override
  String get payoutInformation => 'Dados bancários';

  @override
  String get documents => 'Documentos';

  @override
  String get accessDenied => 'Acesso negado';

  @override
  String get success => 'Sucesso';

  @override
  String get skipForNow => 'Pular por enquanto';

  @override
  String get sendOtpDescription =>
      'Um código de verificação foi enviado para o seu celular';

  @override
  String get resendOtp => 'Reenviar código';

  @override
  String get useOtpInstead => 'Usar código SMS';

  @override
  String get home => 'Início';

  @override
  String get logout => 'Sair';

  @override
  String get driverLicenseNumber => 'Número da CNH';

  @override
  String get email => 'E-mail';

  @override
  String get address => 'Endereço';

  @override
  String get gender => 'Gênero';

  @override
  String get genderMale => 'Masculino';

  @override
  String get genderFemale => 'Feminino';

  @override
  String get genderUnknown => 'Prefiro não informar';

  @override
  String get vehiclePlateNumber => 'Placa do veículo';

  @override
  String get vehicleColor => 'Cor do veículo';

  @override
  String get vehicleModelAndMake => 'Modelo do veículo';

  @override
  String get vehicleProductionYear => 'Ano do veículo';

  @override
  String get bankName => 'Instituição (Ex: Nubank, Inter)';

  @override
  String get bankRoutingNumber => 'Tipo de Chave Pix (CPF, Celular...)';

  @override
  String get bankAccountNumber => 'Sua Chave Pix';

  @override
  String get bankSwift => 'Nome do Titular da Conta';

  @override
  String get uploadImage => 'Enviar imagem';

  @override
  String get yourBalance => 'Seu saldo';

  @override
  String get rideCancellation => 'Cancelamento de corrida';

  @override
  String get cancelRideMessage =>
      'Tem certeza que deseja cancelar sua corrida?';

  @override
  String get cancelRideSuccess => 'Corrida cancelada com sucesso';

  @override
  String get confirmAndCancelRide => 'Confirmar e cancelar corrida';

  @override
  String get selectPaymentMethod => 'Selecionar forma de pagamento';

  @override
  String get rideFeePaid => 'Corrida paga';

  @override
  String get rideFeeUnpaid => 'Corrida ainda não foi paga';

  @override
  String get total => 'Total';

  @override
  String get totalPrice => 'Valor total';

  @override
  String get addCustomCredit => 'Adicionar valor personalizado';

  @override
  String get serviceFee => 'Taxa de serviço';

  @override
  String get serviceOptionFee => 'Taxa de opção de serviço';

  @override
  String get couponDiscount => 'Desconto do cupom';

  @override
  String get walletCreit => 'Crédito da carteira';

  @override
  String get custom => 'Personalizado';

  @override
  String get payment => 'Pagamento';

  @override
  String get cashPayment => 'Dinheiro ou PIX';

  @override
  String cashPaymentDescription(String amount) {
    return 'Você confirma que recebeu $amount?';
  }

  @override
  String get cashPaymentReceived => 'Pagamento em dinheiro/PIX recebido';

  @override
  String get confirmAndEndTrip => 'Confirmar e encerrar corrida';

  @override
  String get earnings => 'Ganhos';

  @override
  String get acceptOrder => 'Aceitar corrida';

  @override
  String get canceled => 'Cancelado';

  @override
  String get unknown => 'Desconhecido';

  @override
  String get commission => 'Comissão';

  @override
  String get selectProfileImage => 'Selecionar foto de perfil';

  @override
  String get chooseAvatarDescription => 'Ou escolha um avatar da lista abaixo:';

  @override
  String get fullName => 'Nome completo';

  @override
  String get favoriteDrivers => 'Motoristas favoritos';

  @override
  String get distanceTraveled => 'Distância percorrida';

  @override
  String get rating => 'Avaliação';

  @override
  String get map => 'Mapa';

  @override
  String get income => 'Renda';

  @override
  String get timeSpent => 'Tempo gasto';

  @override
  String get daily => 'Diário';

  @override
  String get weekly => 'Semanal';

  @override
  String get monthly => 'Mensal';

  @override
  String get noRecordsFoundEarnings =>
      'Nenhum registro encontrado para estes filtros';

  @override
  String get feedbacksSummaryEmptyStateHeading => 'Nenhuma avaliação ainda';

  @override
  String get feedbacksSummaryEmptyStateTitle =>
      'Você ainda não tem avaliações suficientes para exibir.';

  @override
  String get feedbacksSummary => 'Resumo das avaliações';

  @override
  String get feedbacksGoodTitle => 'Excelente trabalho!';

  @override
  String get feedbacksGoodSubtitle => 'Suas avaliações estão ótimas';

  @override
  String get feedbacksBadTitle => 'Regular';

  @override
  String get feedbacksBadSubtitle => 'Você pode melhorar em alguns pontos';

  @override
  String get feedbacksGoodPointsTitle => 'Seus pontos fortes:';

  @override
  String get feedbacksbadPointsTitle => 'Pontos para melhorar:';

  @override
  String get feedbacksReviewsTitle => 'Avaliações recentes';

  @override
  String get payoutMethods => 'Formas de recebimento';

  @override
  String get notice => 'Aviso:';

  @override
  String get payoutNoticeTitle =>
      'Você receberá automaticamente do administrador duas vezes por semana.';

  @override
  String get addPayoutMethod => 'Adicionar forma de recebimento';

  @override
  String get navigate => 'Navegar';

  @override
  String get noPayoutMethods => 'Nenhuma forma de recebimento';

  @override
  String get name => 'Nome';

  @override
  String get nameHint => 'Digite o nome';

  @override
  String get bankNameHint => 'Digite a sua instituição financeira';

  @override
  String get branchName => 'Agência';

  @override
  String get branchNameHint => 'Digite a agência';

  @override
  String get accountHolderName => 'Nome do titular';

  @override
  String get routingNumber => 'Chave PIX';

  @override
  String get routingNumberHint => 'Digite o número da sua chave PIX';

  @override
  String get accountNumber => 'Número da conta';

  @override
  String get accountNumberHint => 'Digite o número da conta';

  @override
  String get addressHint => 'Digite o endereço';

  @override
  String get dateOfBith => 'Data de nascimento';

  @override
  String get yearHint => 'Ano';

  @override
  String get monthHint => 'Mês';

  @override
  String get dayHint => 'Dia';

  @override
  String get city => 'Cidade';

  @override
  String get cityHint => 'Digite a cidade';

  @override
  String get state => 'Estado';

  @override
  String get stateHint => 'Digite o estado';

  @override
  String get zipCode => 'CEP';

  @override
  String get zipCodeHint => 'Digite o CEP';

  @override
  String get day => 'Dia';

  @override
  String get month => 'Mês';

  @override
  String get year => 'Ano';

  @override
  String get noActivitiesYet => 'Nenhuma atividade ainda.';

  @override
  String get headingToDestination => 'Indo para o destino';

  @override
  String get driverArrivedNotice => 'O motorista está esperando por você';

  @override
  String get driverShouldAriveInNotice => 'O motorista deve chegar em';

  @override
  String get driverShouldHaveArrivedNotice =>
      'O motorista deve chegar a qualquer momento';

  @override
  String get deleteAccount => 'Excluir conta';

  @override
  String get deleteAccountNotice =>
      'Tem certeza que deseja excluir sua conta? Após 30 dias, ela será excluída permanentemente. Nesse período, você pode restaurá-la fazendo login novamente.';

  @override
  String get confirmAndDeleteAccount => 'Confirmar e excluir conta';

  @override
  String get accountDeleted => 'Conta excluída';

  @override
  String share_trip_text_locations(Object destination, Object pickup) {
    return 'Estou a caminho de $destination saindo de $pickup.';
  }

  @override
  String share_trip_text_driver(
      Object firstName, Object lastName, Object mobileNumber) {
    return ' Meu motorista é $firstName $lastName, celular: +$mobileNumber.';
  }

  @override
  String share_trip_text_rider(
      Object firstName, Object lastName, Object mobileNumber) {
    return ' O passageiro comigo é $firstName $lastName, celular: +$mobileNumber.';
  }

  @override
  String share_trip_started_time(Object startTime, Object duration) {
    return ' A corrida começou às $startTime e deve durar aproximadamente $duration minutos.';
  }

  @override
  String share_trip_not_arrived_time(Object duration) {
    return ' A corrida deve durar aproximadamente $duration minutos após eu entrar no carro.';
  }

  @override
  String get sendSOSMessage =>
      'IMPORTANTE: Use este recurso apenas em caso de emergência. Entraremos em contato com as autoridades em seu nome.';

  @override
  String get confirmAndSendSOS => 'Confirmar e enviar SOS';

  @override
  String get sosSentSuccessfully => 'SOS enviado com sucesso';

  @override
  String get topUpSuccess => 'Carteira recarregada com sucesso';

  @override
  String get cancelNotAllowed =>
      'Não é possível cancelar uma corrida já iniciada.';

  @override
  String get error => 'Erro';

  @override
  String get connectionError => 'Erro de conexão';

  @override
  String get serverError => 'Erro no servidor';

  @override
  String get addNewLocation => 'Adicionar novo local';

  @override
  String get twoWayTrip => 'Ida e volta';

  @override
  String get reportSubmitted => 'Relato enviado';

  @override
  String get reportSubmittedDescription =>
      'Seu relato foi enviado com sucesso. Vamos analisar e tomar as medidas necessárias.';

  @override
  String get cardNumber => 'Número do cartão';

  @override
  String get cardNumberHint => 'Digite o número do cartão';

  @override
  String get expiryDate => 'Validade';

  @override
  String get expiryDateHint => 'MM/AA';

  @override
  String get noFavoriteDrivers => 'Nenhum motorista favorito';

  @override
  String get noFavoriteDriversDescription =>
      'Você pode favoritar motoristas ao avaliá-los após a corrida.';

  @override
  String get pickupLocationNotFound =>
      'Não foi possível determinar sua localização pelo GPS. Digite o ponto de partida manualmente.';

  @override
  String get dragToSelect => 'Confirme o local no mapa';

  @override
  String get skip => 'Pular';

  @override
  String get openSettings => 'Abrir configurações';

  @override
  String get locationPermission => 'Permissão de localização';

  @override
  String get locationPermissionDeniedForeverMessage =>
      'A permissão de localização é necessária para receber corridas próximas e para o passageiro acompanhar sua posição. Sem essa permissão, não é possível receber corridas. Você pode alterar isso nas configurações do celular.';

  @override
  String get allow => 'Permitir';

  @override
  String get driverOnlineTitle => 'Buscando corridas';

  @override
  String get driverOfflineTitle => 'Fique online para receber solicitações';

  @override
  String get payInCash => 'Pagamento em Dinheiro/PIX';

  @override
  String get payInCashDescription =>
      'Efetue o pagamento em dinheiro ou PIX ao motorista. Ele confirmará o recebimento no aplicativo.';

  @override
  String get addToFavoriteDrivers => 'Adicionar aos motoristas favoritos';

  @override
  String get slideToConfirmArrival => 'Cheguei no local';

  @override
  String get slideToConfirmPickup => 'Iniciar viagem';

  @override
  String get slideToConfirmDropoff => 'Finalizar corrida';

  @override
  String get noticePickingUpRiderIn => 'Buscando o passageiro em:';

  @override
  String get noticeRiderNotified =>
      'O passageiro foi notificado. Busque o passageiro e inicie a corrida';

  @override
  String get adminPanelOnboardingOneTitle => 'Bem-vindo ao painel';

  @override
  String get adminPanelOnboardingOneSubtitle =>
      'Gerencie sua plataforma de mobilidade';

  @override
  String get adminPanelOnboardingTwoTitle => 'Simplifique suas operações';

  @override
  String get adminPanelOnboardingTwoSubtitle =>
      'Controle tudo pelo painel centralizado';

  @override
  String get rider => 'Passageiro';

  @override
  String get customer => 'Cliente';

  @override
  String get back => 'Voltar';

  @override
  String get addressHome => 'Casa';

  @override
  String get addressWork => 'Trabalho';

  @override
  String get addressPartner => 'Parceiro(a)';

  @override
  String get addressGym => 'Academia';

  @override
  String get addressParent => 'Pais';

  @override
  String get addressCafe => 'Café';

  @override
  String get addressPark => 'Parque';

  @override
  String get addressOther => 'Outro';

  @override
  String resendOtpIn(int seconds) {
    return 'Reenviar código em $seconds segundos';
  }

  @override
  String get appearance => 'Aparência';

  @override
  String get themeModeLight => 'Claro';

  @override
  String get themeModeDark => 'Escuro';

  @override
  String get themeModeSystem => 'Seguir o sistema';

  @override
  String get privacyPolicy => 'Privacidade e Dados (LGPD)';

  @override
  String get account => 'Conta';

  @override
  String get logoutConfirmMessage =>
      'Tem certeza que deseja sair da sua conta?';

  @override
  String get driverDocumentsTitle => 'Documentos Obrigatórios';

  @override
  String get cnhLabel => 'Carteira de Habilitação (CNH)';

  @override
  String get crlvLabel => 'Documento do Veículo (CRLV)';

  @override
  String get residenceLabel => 'Comprovante de Residência';

  @override
  String get documentsSuccess => 'Documentos enviados com sucesso!';

  @override
  String get attentionDocsText =>
      'Atenção: Seu RG/CNH e CRLV devem estar perfeitamente legíveis para aprovação.';

  @override
  String get driverDocumentsSub =>
      'Gerencie e envie seus documentos obrigatórios.';

  @override
  String get responsibilityAgreement =>
      'Declaro que sou o proprietário legal ou possuo autorização expressa para uso de todos os documentos enviados. Assumo total responsabilidade civil e criminal pela autenticidade, nitidez e conformidade das fotos de CNH, CRLV e comprovante de residência anexadas, ciente de que fraudes resultarão no banimento imediato e em ações judiciais.';

  @override
  String get responsibilityAgreementCheckbox =>
      'Declaro que as fotos enviadas são autênticas, legíveis e correspondem exatamente aos documentos exigidos.';

  @override
  String get responsibilityAgreementClean =>
      'Declaro que todos os documentos e fotos enviados são autênticos, legíveis e correspondem exatamente aos originais exigidos, assumindo inteira responsabilidade legal pelas informações prestadas.';

  @override
  String get searchingNavigation => 'Buscando navegação...';

  @override
  String get recalculatingRoute => 'Recalculando rota...';

  @override
  String get then => 'EM SEGUIDA: ';

  @override
  String get turnByTurnInstructions => 'Instruções passo a passo';

  @override
  String get navStreetDefault => 'rua';

  @override
  String get navDefault => 'Siga em frente';

  @override
  String navNewName(Object streetName) {
    return 'Continue na $streetName';
  }

  @override
  String navDepart(Object streetName) {
    return 'Siga em direção a $streetName';
  }

  @override
  String get navArrive => 'Você chegou ao seu destino!';

  @override
  String navMerge(Object streetName) {
    return 'Incorpore-se à $streetName';
  }

  @override
  String navRamp(Object streetName) {
    return 'Pegue a rampa em direção a $streetName';
  }

  @override
  String navRoundabout(Object streetName) {
    return 'Na rotatória, pegue a saída para $streetName';
  }

  @override
  String navFork(Object streetName) {
    return 'Na bifurcação, siga em direção a $streetName';
  }

  @override
  String navTurnLeft(Object streetName) {
    return 'Vire à esquerda na $streetName';
  }

  @override
  String navTurnRight(Object streetName) {
    return 'Vire à direita na $streetName';
  }

  @override
  String navTurnSharpLeft(Object streetName) {
    return 'Vire acentuadamente à esquerda na $streetName';
  }

  @override
  String navTurnSharpRight(Object streetName) {
    return 'Vire acentuadamente à direita na $streetName';
  }

  @override
  String navTurnSlightLeft(Object streetName) {
    return 'Mantenha-se à esquerda na $streetName';
  }

  @override
  String navTurnSlightRight(Object streetName) {
    return 'Mantenha-se à direita na $streetName';
  }

  @override
  String navTurnStraight(Object streetName) {
    return 'Siga em frente na $streetName';
  }

  @override
  String navTurnUturn(Object streetName) {
    return 'Faça o retorno na $streetName';
  }

  @override
  String navTurnDefault(Object streetName) {
    return 'Vire na $streetName';
  }

  @override
  String get preferenceSilent => 'Silêncio';

  @override
  String get preferenceAc => 'Ar Frio';

  @override
  String get preferenceChatty => 'Conversar';

  @override
  String get chainedRideAvailable => 'Próxima corrida disponível!';

  @override
  String rideEstimate(Object amount) {
    return 'Estimativa: $amount';
  }

  @override
  String get decline => 'Recusar';

  @override
  String get dailyChallengeTitle => 'Desafio Diário Uppi';

  @override
  String dailyChallengeCompleted(Object bonus) {
    return '✨ Desafio Concluído! +R\$ $bonus garantidos hoje!';
  }

  @override
  String dailyChallengeSubtitle(Object target, Object bonus) {
    return 'Complete $target corridas hoje e ganhe bônus de R\$ $bonus!';
  }

  @override
  String get emergencyContacts => 'Contatos de emergência';

  @override
  String get emergencyContactsSubtitle => 'Quem será notificado ao acionar SOS';
}
