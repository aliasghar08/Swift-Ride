import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:tflite_flutter/tflite_flutter.dart';

/// Service running on-device TensorFlow Lite neural network inference
/// to compute the optimal "Sweet Spot" passenger fare for local routes.
class PricingMLService {
  static final PricingMLService _instance = PricingMLService._internal();
  factory PricingMLService() => _instance;
  PricingMLService._internal();

  Interpreter? _interpreter;
  bool _isInitialized = false;
  bool _isLoading = false;

  // Normalization parameters fitted strictly on the Jhang & Toba Tek Singh training set
  static const double _distMin = 1.0;
  static const double _distMax = 38.0;

  static const double _timeMin = 0.0;
  static const double _timeMax = 23.99;

  static const double _rainMin = 0.0;
  static const double _rainMax = 1.0;

  static const double _trafficMin = 1.0;
  static const double _trafficMax = 1.5;

  /// Loads the TFLite model from bundled app assets
  Future<void> initialize() async {
    if (_isInitialized || _isLoading) return;
    _isLoading = true;
    try {
      _interpreter = await Interpreter.fromAsset('assets/ml/pricing_model.tflite');
      _isInitialized = true;
      debugPrint('[PricingMLService] TensorFlow Lite pricing model loaded successfully.');
    } catch (e) {
      debugPrint('[PricingMLService] Notice: Could not load TFLite model ($e). Using algorithmic fallback.');
    } finally {
      _isLoading = false;
    }
  }

  /// Predicts the optimal sweet-spot bid in PKR.
  /// 
  /// [distanceKm]: Route distance in kilometers.
  /// [timeOfDayHours]: Hour of the day (0.0 to 24.0). If null, uses current device hour.
  /// [isRaining]: Whether it's currently raining (0.0 or 1.0). Default is 0.0.
  /// [trafficMultiplier]: Traffic density factor (1.0 to 1.5). Default is 1.15.
  Future<double> predictSuggestedBid({
    required double distanceKm,
    double? timeOfDayHours,
    double isRaining = 0.0,
    double trafficMultiplier = 1.15,
  }) async {
    if (!_isInitialized && !_isLoading) {
      await initialize();
    }

    final double validDist = distanceKm.clamp(0.5, 80.0);
    final double curTime = timeOfDayHours ?? (DateTime.now().hour + (DateTime.now().minute / 60.0));
    final double validTime = curTime.clamp(0.0, 24.0);
    final double validRain = isRaining.clamp(0.0, 1.0);
    final double validTraffic = trafficMultiplier.clamp(1.0, 1.5);

    // Min-Max normalize using the exact bounds from model training
    final double normDist = ((validDist - _distMin) / (_distMax - _distMin)).clamp(0.0, 1.0);
    final double normTime = ((validTime - _timeMin) / (_timeMax - _timeMin)).clamp(0.0, 1.0);
    final double normRain = ((validRain - _rainMin) / (_rainMax - _rainMin)).clamp(0.0, 1.0);
    final double normTraffic = ((validTraffic - _trafficMin) / (_trafficMax - _trafficMin)).clamp(0.0, 1.0);

    if (_interpreter != null) {
      try {
        final input = [
          [normDist, normTime, normRain, normTraffic]
        ];
        // Output shape [1, 1]
        final output = [
          [0.0]
        ];
        _interpreter!.run(input, output);
        final rawBid = output[0][0];
        if (rawBid > 30.0 && !rawBid.isNaN && !rawBid.isInfinite) {
          // Round to nearest PKR 5 for clean local market cash handling
          return (rawBid / 5.0).round() * 5.0;
        }
      } catch (e) {
        debugPrint('[PricingMLService] Inference error ($e), using calibrated fallback.');
      }
    }

    // Calibrated algorithmic fallback modeled after the local training distribution
    final baseFare = (50.0 + (validDist * 25.0)) * validTraffic;
    final rainAdjustment = validRain > 0.5 ? 20.0 : 0.0;
    final rounded = ((baseFare + rainAdjustment) / 5.0).round() * 5.0;
    return math.max(60.0, rounded.toDouble());
  }

  void dispose() {
    _interpreter?.close();
    _interpreter = null;
    _isInitialized = false;
  }
}
