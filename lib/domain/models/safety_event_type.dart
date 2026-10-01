enum SafetyEventType {
  longStop,
  routeDeviation,
  earlyEnd,
  crashDetected,
  sos;

  String get displayName {
    switch (this) {
      case SafetyEventType.longStop:
        return 'Prolonged Unexpected Stop';
      case SafetyEventType.routeDeviation:
        return 'Significant Route Deviation (>500m)';
      case SafetyEventType.earlyEnd:
        return 'Premature Trip Termination';
      case SafetyEventType.crashDetected:
        return 'Sudden Impact / Deceleration';
      case SafetyEventType.sos:
        return 'EMERGENCY SOS DISPATCHED';
    }
  }

  static SafetyEventType fromString(String? val) {
    switch (val?.toUpperCase()) {
      case 'ROUTE_DEVIATION':
        return SafetyEventType.routeDeviation;
      case 'EARLY_END':
        return SafetyEventType.earlyEnd;
      case 'CRASH_DETECTED':
        return SafetyEventType.crashDetected;
      case 'SOS':
        return SafetyEventType.sos;
      default:
        return SafetyEventType.longStop;
    }
  }

  String toDbString() {
    switch (this) {
      case SafetyEventType.longStop:
        return 'LONG_STOP';
      case SafetyEventType.routeDeviation:
        return 'ROUTE_DEVIATION';
      case SafetyEventType.earlyEnd:
        return 'EARLY_END';
      case SafetyEventType.crashDetected:
        return 'CRASH_DETECTED';
      case SafetyEventType.sos:
        return 'SOS';
    }
  }
}
