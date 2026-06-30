import 'package:flutter/material.dart';

import '../features/financials/financials_screen.dart';
import '../features/financials/driver_earnings_screen.dart';
import '../features/rides/rides_history_screen.dart';
import '../features/kyc/kyc_approval_screen.dart';
import '../features/dashboard/overview_dashboard_screen.dart';
import '../features/services/services_pricing_screen.dart';
import '../features/riders/riders_management_screen.dart';
import '../features/coupons/coupons_management_screen.dart';
import '../features/cashback/cashback_management_screen.dart';
import '../features/marketing/marketing_push_screen.dart';
import '../features/settings/settings_screen.dart';
import '../features/map/global_map_screen.dart';
import '../features/map/live_dispatch_screen.dart';
import '../features/marketing/gamification_screen.dart';
import '../features/drivers/drivers_management_screen.dart';
import '../features/reviews/reviews_screen.dart';
import '../features/gift_cards/gift_cards_screen.dart';
import '../features/complaints/complaints_screen.dart';
import '../features/settings/payment_gateways_screen.dart';
import '../features/financials/payment_logs_screen.dart';
import '../features/settings/cancel_reasons_screen.dart';
import '../features/settings/vehicle_config_screen.dart';
import '../features/settings/admin_users_screen.dart';
import '../features/settings/quick_replies_screen.dart';
import '../features/settings/system_config_screen.dart';
import '../features/settings/audit_log_screen.dart';
import '../features/safety/sos_management_screen.dart';
import '../features/drivers/driver_documents_screen.dart';
import '../features/messages/ride_messages_monitor_screen.dart';
import '../features/payments/user_payment_methods_screen.dart';
import '../features/wallets/user_wallets_screen.dart';
import '../features/settings/payout_methods_config_screen.dart';
import '../features/rides/scheduled_rides_screen.dart';
import '../features/actions/admin_actions_screen.dart';
import '../features/kyc/rider_identity_verification_screen.dart';
import '../features/face_verification/driver_face_verification_screen.dart';
import '../features/announcements/announcements_screen.dart';
import '../features/safety/privacy_lgpd_screen.dart';
import '../features/safety/ride_tracking_shares_screen.dart';
import '../features/safety/danger_zones_screen.dart';
import '../features/reports/reports_screen.dart';
import '../features/analytics/analytics_screen.dart';
import '../features/referrals/referral_management_screen.dart';
import '../features/map/demand_heatmap_screen.dart';
import '../features/corporate/corporate_management_screen.dart';
import '../features/safety/suspicious_devices_screen.dart';
import '../features/drivers/accessibility_tags_screen.dart';

// ─────────────────────────────────────────────
// Definição de Item do Menu Administrativo
// ─────────────────────────────────────────────
class AdminMenuItem {
  final IconData icon;
  final IconData selectedIcon;
  final String label;
  final Widget content;
  final List<String> allowedRoles;

  const AdminMenuItem({
    required this.icon,
    required this.selectedIcon,
    required this.label,
    required this.content,
    required this.allowedRoles,
  });
}

// ─────────────────────────────────────────────
// Lista Global de Itens do Menu
// ─────────────────────────────────────────────
final List<AdminMenuItem> allMenuItems = [
  const AdminMenuItem(
    icon: Icons.dashboard_outlined,
    selectedIcon: Icons.dashboard_rounded,
    label: 'Visao Geral',
    content: OverviewDashboardScreen(),
    allowedRoles: ['operator', 'admin', 'superadmin'],
  ),
  const AdminMenuItem(
    icon: Icons.assignment_outlined,
    selectedIcon: Icons.assignment_rounded,
    label: 'Relatórios & Exportação',
    content: ReportsScreen(),
    allowedRoles: ['admin', 'superadmin'],
  ),
  const AdminMenuItem(
    icon: Icons.analytics_outlined,
    selectedIcon: Icons.analytics_rounded,
    label: 'Analytics Avançado',
    content: AnalyticsScreen(),
    allowedRoles: ['admin', 'superadmin'],
  ),
  const AdminMenuItem(
    icon: Icons.map_outlined,
    selectedIcon: Icons.map_rounded,
    label: 'Mapa Global',
    content: GlobalMapScreen(),
    allowedRoles: ['operator', 'admin', 'superadmin'],
  ),
  const AdminMenuItem(
    icon: Icons.local_fire_department_outlined,
    selectedIcon: Icons.local_fire_department,
    label: 'Calor de Demanda',
    content: DemandHeatmapScreen(),
    allowedRoles: ['operator', 'admin', 'superadmin'],
  ),
  const AdminMenuItem(
    icon: Icons.flash_on_outlined,
    selectedIcon: Icons.flash_on_rounded,
    label: 'Live Dispatch',
    content: LiveDispatchScreen(),
    allowedRoles: ['operator', 'admin', 'superadmin'],
  ),
  const AdminMenuItem(
    icon: Icons.verified_user_outlined,
    selectedIcon: Icons.verified_user_rounded,
    label: 'Aprovações KYC',
    content: KycApprovalScreen(),
    allowedRoles: ['operator', 'admin', 'superadmin'],
  ),
  const AdminMenuItem(
    icon: Icons.shield_outlined,
    selectedIcon: Icons.shield_rounded,
    label: 'Identidade Rider',
    content: RiderIdentityVerificationScreen(),
    allowedRoles: ['operator', 'admin', 'superadmin'],
  ),
  const AdminMenuItem(
    icon: Icons.face_outlined,
    selectedIcon: Icons.face_rounded,
    label: 'Verificação Facial',
    content: DriverFaceVerificationScreen(),
    allowedRoles: ['operator', 'admin', 'superadmin'],
  ),
  const AdminMenuItem(
    icon: Icons.star_border,
    selectedIcon: Icons.star_rounded,
    label: 'Gamificação',
    content: GamificationScreen(),
    allowedRoles: ['admin', 'superadmin'],
  ),
  const AdminMenuItem(
    icon: Icons.drive_eta_outlined,
    selectedIcon: Icons.drive_eta_rounded,
    label: 'Motoristas',
    content: DriversManagementScreen(),
    allowedRoles: ['operator', 'admin', 'superadmin'],
  ),
  const AdminMenuItem(
    icon: Icons.person_outline,
    selectedIcon: Icons.person_rounded,
    label: 'Passageiros',
    content: RidersManagementScreen(),
    allowedRoles: ['operator', 'admin', 'superadmin'],
  ),
  const AdminMenuItem(
    icon: Icons.history_outlined,
    selectedIcon: Icons.history_rounded,
    label: 'Histórico de Corridas',
    content: RidesHistoryScreen(),
    allowedRoles: ['operator', 'admin', 'superadmin'],
  ),
  const AdminMenuItem(
    icon: Icons.reviews_outlined,
    selectedIcon: Icons.reviews_rounded,
    label: 'Avaliações',
    content: ReviewsScreen(),
    allowedRoles: ['operator', 'admin', 'superadmin'],
  ),
  const AdminMenuItem(
    icon: Icons.attach_money_outlined,
    selectedIcon: Icons.attach_money_rounded,
    label: 'Financeiro',
    content: FinancialsScreen(),
    allowedRoles: ['admin', 'superadmin'],
  ),
  const AdminMenuItem(
    icon: Icons.trending_up_outlined,
    selectedIcon: Icons.trending_up_rounded,
    label: 'Earnings Motorista',
    content: DriverEarningsScreen(),
    allowedRoles: ['admin', 'superadmin'],
  ),
  const AdminMenuItem(
    icon: Icons.monetization_on_outlined,
    selectedIcon: Icons.monetization_on_rounded,
    label: 'Taxas e Preços',
    content: ServicesPricingScreen(),
    allowedRoles: ['admin', 'superadmin'],
  ),
  const AdminMenuItem(
    icon: Icons.local_offer_outlined,
    selectedIcon: Icons.local_offer_rounded,
    label: 'Cupons',
    content: CouponsManagementScreen(),
    allowedRoles: ['admin', 'superadmin'],
  ),
  const AdminMenuItem(
    icon: Icons.share_outlined,
    selectedIcon: Icons.share_rounded,
    label: 'Indicações (Referral)',
    content: ReferralManagementScreen(),
    allowedRoles: ['admin', 'superadmin'],
  ),
  const AdminMenuItem(
    icon: Icons.savings_outlined,
    selectedIcon: Icons.savings,
    label: 'Cashback Dinâmico',
    content: CashbackManagementScreen(),
    allowedRoles: ['admin', 'superadmin'],
  ),
  const AdminMenuItem(
    icon: Icons.card_giftcard_outlined,
    selectedIcon: Icons.card_giftcard_rounded,
    label: 'Cartões Presente',
    content: GiftCardsScreen(),
    allowedRoles: ['admin', 'superadmin'],
  ),
  const AdminMenuItem(
    icon: Icons.campaign_outlined,
    selectedIcon: Icons.campaign_rounded,
    label: 'Marketing (Push)',
    content: MarketingPushScreen(),
    allowedRoles: ['admin', 'superadmin'],
  ),
  const AdminMenuItem(
    icon: Icons.campaign_outlined,
    selectedIcon: Icons.campaign_rounded,
    label: 'Comunicados & Avisos',
    content: AnnouncementsScreen(),
    allowedRoles: ['admin', 'superadmin'],
  ),
  const AdminMenuItem(
    icon: Icons.support_agent_outlined,
    selectedIcon: Icons.support_agent_rounded,
    label: 'Reclamações',
    content: ComplaintsScreen(),
    allowedRoles: ['operator', 'admin', 'superadmin'],
  ),
  const AdminMenuItem(
    icon: Icons.credit_card_outlined,
    selectedIcon: Icons.credit_card_rounded,
    label: 'Pagamentos',
    content: PaymentGatewaysScreen(),
    allowedRoles: ['superadmin'],
  ),
  const AdminMenuItem(
    icon: Icons.receipt_long_outlined,
    selectedIcon: Icons.receipt_long_rounded,
    label: 'Logs de Gateways',
    content: PaymentLogsScreen(),
    allowedRoles: ['superadmin'],
  ),
  const AdminMenuItem(
    icon: Icons.cancel_outlined,
    selectedIcon: Icons.cancel_rounded,
    label: 'Motivos Cancel.',
    content: CancelReasonsScreen(),
    allowedRoles: ['admin', 'superadmin'],
  ),
  const AdminMenuItem(
    icon: Icons.directions_car_outlined,
    selectedIcon: Icons.directions_car_rounded,
    label: 'Config. Veículos',
    content: VehicleConfigScreen(),
    allowedRoles: ['admin', 'superadmin'],
  ),
  const AdminMenuItem(
    icon: Icons.admin_panel_settings_outlined,
    selectedIcon: Icons.admin_panel_settings_rounded,
    label: 'Equipe Admin',
    content: AdminUsersScreen(),
    allowedRoles: ['superadmin'],
  ),
  const AdminMenuItem(
    icon: Icons.sos_outlined,
    selectedIcon: Icons.sos_rounded,
    label: 'Emergências SOS',
    content: SosManagementScreen(),
    allowedRoles: ['operator', 'admin', 'superadmin'],
  ),
  const AdminMenuItem(
    icon: Icons.shield_outlined,
    selectedIcon: Icons.shield,
    label: 'Zonas de Perigo (99)',
    content: DangerZonesScreen(),
    allowedRoles: ['admin', 'superadmin'],
  ),
  const AdminMenuItem(
    icon: Icons.description_outlined,
    selectedIcon: Icons.description_rounded,
    label: 'Docs Motorista',
    content: DriverDocumentsScreen(),
    allowedRoles: ['operator', 'admin', 'superadmin'],
  ),
  const AdminMenuItem(
    icon: Icons.quickreply_outlined,
    selectedIcon: Icons.quickreply_rounded,
    label: 'Respostas Rápidas',
    content: QuickRepliesScreen(),
    allowedRoles: ['admin', 'superadmin'],
  ),
  const AdminMenuItem(
    icon: Icons.tune_outlined,
    selectedIcon: Icons.tune_rounded,
    label: 'Config Sistema',
    content: SystemConfigScreen(),
    allowedRoles: ['superadmin'],
  ),
  const AdminMenuItem(
    icon: Icons.policy_outlined,
    selectedIcon: Icons.policy_rounded,
    label: 'Audit Log',
    content: AuditLogScreen(),
    allowedRoles: ['superadmin'],
  ),
  const AdminMenuItem(
    icon: Icons.chat_outlined,
    selectedIcon: Icons.chat_rounded,
    label: 'Chat Corridas',
    content: RideMessagesMonitorScreen(),
    allowedRoles: ['operator', 'admin', 'superadmin'],
  ),
  const AdminMenuItem(
    icon: Icons.account_balance_outlined,
    selectedIcon: Icons.account_balance_rounded,
    label: 'Pagamentos Usuários',
    content: UserPaymentMethodsScreen(),
    allowedRoles: ['admin', 'superadmin'],
  ),
  const AdminMenuItem(
    icon: Icons.wallet_outlined,
    selectedIcon: Icons.wallet_rounded,
    label: 'Carteiras & Favoritos',
    content: UserWalletsScreen(),
    allowedRoles: ['admin', 'superadmin'],
  ),
  const AdminMenuItem(
    icon: Icons.output_outlined,
    selectedIcon: Icons.output_rounded,
    label: 'Métodos de Saque',
    content: PayoutMethodsConfigScreen(),
    allowedRoles: ['admin', 'superadmin'],
  ),
  const AdminMenuItem(
    icon: Icons.offline_bolt_outlined,
    selectedIcon: Icons.offline_bolt_rounded,
    label: 'Ações Avançadas',
    content: AdminActionsScreen(),
    allowedRoles: ['superadmin'],
  ),
  const AdminMenuItem(
    icon: Icons.event_available_outlined,
    selectedIcon: Icons.event_available_rounded,
    label: 'Corridas Agendadas',
    content: ScheduledRidesScreen(),
    allowedRoles: ['operator', 'admin', 'superadmin'],
  ),
  const AdminMenuItem(
    icon: Icons.gavel_outlined,
    selectedIcon: Icons.gavel_rounded,
    label: 'Privacidade & LGPD',
    content: PrivacyLgpdScreen(),
    allowedRoles: ['admin', 'superadmin'],
  ),
  const AdminMenuItem(
    icon: Icons.share_location_outlined,
    selectedIcon: Icons.share_location_rounded,
    label: 'Monitor de Rotas',
    content: RideTrackingSharesScreen(),
    allowedRoles: ['admin', 'superadmin'],
  ),
  const AdminMenuItem(
    icon: Icons.business_outlined,
    selectedIcon: Icons.business_rounded,
    label: 'Gestão Corporativa B2B',
    content: CorporateManagementScreen(),
    allowedRoles: ['admin', 'superadmin'],
  ),
  const AdminMenuItem(
    icon: Icons.phonelink_lock_outlined,
    selectedIcon: Icons.phonelink_lock_rounded,
    label: 'Fraude & Dispositivos',
    content: SuspiciousDevicesScreen(),
    allowedRoles: ['operator', 'admin', 'superadmin'],
  ),
  const AdminMenuItem(
    icon: Icons.accessibility_new_outlined,
    selectedIcon: Icons.accessibility_new_rounded,
    label: 'Tags de Acessibilidade',
    content: AccessibilityTagsScreen(),
    allowedRoles: ['operator', 'admin', 'superadmin'],
  ),
  const AdminMenuItem(
    icon: Icons.settings_outlined,
    selectedIcon: Icons.settings_rounded,
    label: 'Configurações',
    content: SettingsScreen(),
    allowedRoles: ['superadmin'],
  ),
];
