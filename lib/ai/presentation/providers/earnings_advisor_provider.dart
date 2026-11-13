import 'package:flutter/widgets.dart';
import '../dialogs/ai_consent_dialog.dart';
import '../../data/ai_repository.dart';
import '../../domain/ai_insight.dart';

class EarningsAdvisorProvider extends ChangeNotifier {
  final AiRepository _repository;
  AiInsight? _insight;
  AiInsight? _maintenanceAlert;
  bool _isLoading = false;
  String? _error;

  EarningsAdvisorProvider({AiRepository? repository})
      : _repository = repository ?? AiRepository();

  AiInsight? get insight => _insight;
  AiInsight? get maintenanceAlert => _maintenanceAlert;
  bool get isLoading => _isLoading;
  String? get error => _error;

  Future<void> loadEarningsInsight(String driverId, {bool force = false}) async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      _insight = await _repository.fetchLatestEarningsInsight(driverId, force: force);
      _maintenanceAlert = await _repository.fetchLatestMaintenanceAlert(driverId);
    } catch (e) {
      _error = e.toString();
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<bool> loadEarningsInsightWithConsent(
    BuildContext context,
    String driverId, {
    bool force = false,
  }) async {
    final allowed = await AiConsentDialog.ensureConsent(context);
    if (!allowed) return false;
    await loadEarningsInsight(driverId, force: force);
    return true;
  }

  Future<void> refresh(String driverId) => loadEarningsInsight(driverId, force: true);
}
