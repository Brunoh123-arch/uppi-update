class EarningsRideDetails {
  final String id;
  final double amount;
  final DateTime createdAt;
  final String serviceName;
  final String pickupAddress;
  final String dropoffAddress;

  EarningsRideDetails({
    required this.id,
    required this.amount,
    required this.createdAt,
    required this.serviceName,
    required this.pickupAddress,
    required this.dropoffAddress,
  });
}
