import 'package:flutter/foundation.dart';
import '../../data/ai_repository.dart';
import '../../domain/ai_insight.dart';

class EarningsAdvisorProvider extends ChangeNotifier {
  final AiRepository _repository;
  AiInsight? _insight;
  bool _isLoading = false;
  String? _error;

  EarningsAdvisorProvider({AiRepository? repository})
      : _repository = repository ?? AiRepository();

  AiInsight? get insight => _insight;
  bool get isLoading => _isLoading;
  String? get error => _error;

  Future<void> loadEarningsInsight(String driverId, {bool force = false}) async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      _insight = await _repository.fetchLatestEarningsInsight(driverId, force: force);
    } catch (e) {
      _error = e.toString();
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> refresh(String driverId) => loadEarningsInsight(driverId, force: true);
}
