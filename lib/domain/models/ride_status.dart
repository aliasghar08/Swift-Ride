enum RideStatus {
  requested,
  accepted,
  driverArrived,
  inProgress,
  completed,
  cancelled;

  static RideStatus fromString(String? val) {
    switch (val?.toUpperCase()) {
      case 'ACCEPTED':
        return RideStatus.accepted;
      case 'DRIVER_ARRIVED':
        return RideStatus.driverArrived;
      case 'IN_PROGRESS':
        return RideStatus.inProgress;
      case 'COMPLETED':
        return RideStatus.completed;
      case 'CANCELLED':
        return RideStatus.cancelled;
      default:
        return RideStatus.requested;
    }
  }

  String toDbString() {
    switch (this) {
      case RideStatus.requested:
        return 'REQUESTED';
      case RideStatus.accepted:
        return 'ACCEPTED';
      case RideStatus.driverArrived:
        return 'DRIVER_ARRIVED';
      case RideStatus.inProgress:
        return 'IN_PROGRESS';
      case RideStatus.completed:
        return 'COMPLETED';
      case RideStatus.cancelled:
        return 'CANCELLED';
    }
  }

  String get displayName {
    switch (this) {
      case RideStatus.requested:
        return 'Finding Drivers';
      case RideStatus.accepted:
        return 'Driver En Route';
      case RideStatus.driverArrived:
        return 'Driver Arrived';
      case RideStatus.inProgress:
        return 'On Trip';
      case RideStatus.completed:
        return 'Completed';
      case RideStatus.cancelled:
        return 'Cancelled';
    }
  }
}
