import 'package:uppi_motorista/core/enums/driver_status.dart';

/// Converte a string de status do banco de dados (snake_case ou camelCase)
/// para o enum [DriverStatus] correspondente.
///
/// Aceita ambos os formatos para compatibilidade com dados legados.
class StatusParser {
  static DriverStatus fromString(String? status) {
    final s = status?.trim().toLowerCase();
    switch (s) {
      case 'offline':
      case 'active':
      case 'approved':
        return const DriverStatus.offline();
      case 'online':
        return const DriverStatus.online();
      case 'in_progress':
      case 'ontrip':
        return const DriverStatus.onTrip();
      case 'blocked':
        return const DriverStatus.blocked();
      case 'softreject':
      case 'soft_reject':
        return const DriverStatus.softReject();
      case 'hardreject':
      case 'hard_reject':
        return const DriverStatus.hardReject();
      case 'pendingapproval':
      case 'pending_approval':
      case 'waiting_documents':
      case 'pending_review':
        return const DriverStatus.pendingApproval();
      default:
        return const DriverStatus.pendingSubmission();
    }
  }
}
