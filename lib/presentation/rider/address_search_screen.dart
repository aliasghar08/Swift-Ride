import 'dart:async';
import 'dart:collection';
import 'package:flutter/material.dart';
import '../../services/native_map_service.dart';

import '../../core/provider/custom_provider.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/design_tokens.dart';
import '../../domain/models/location_point_model.dart';
import '../../providers/location_provider.dart';
import '../../services/coordinate_parser.dart';
import '../../services/map_service.dart';
import '../common/prominent_disclosure_dialog.dart';
import '../common/glass_container.dart';
import '../common/skeleton.dart';
import '../common/reserved_bottom_ad_bar.dart';
import '../view_models/responsive_layout_helper.dart';

/// Hybrid signal returned when rider chooses to select location on map.
/// Inherits from [LocationPoint] for compatibility with [Navigator.push<LocationPoint>]
/// and mixes in [MapMixin] for compatibility with [Navigator.pop({'chooseOnMap': true})].
class ChooseOnMapSignal extends LocationPoint with MapMixin<String, dynamic> {
  final Map<String, dynamic> _data;

  ChooseOnMapSignal({bool isPickup = false})
      : _data = {'chooseOnMap': true, 'isPickup': isPickup},
        super(latitude: 0, longitude: 0, address: '__CHOOSE_ON_MAP__');

  @override
  dynamic operator [](Object? key) => _data[key];

  @override
  void operator []=(String key, dynamic value) => _data[key] = value;

  @override
  void clear() => _data.clear();

  @override
  Iterable<String> get keys => _data.keys;

  @override
  dynamic remove(Object? key) => _data.remove(key);
}

class AddressSearchScreen extends StatefulWidget {
  final String title;
  final String initialQuery;
  final bool isPickup;

  const AddressSearchScreen({
    super.key,
    this.title = 'Select Address',
    this.initialQuery = '',
    this.isPickup = false,
  });

  @override
  State<AddressSearchScreen> createState() => _AddressSearchScreenState();
}

class _AddressSearchScreenState extends State<AddressSearchScreen> {
  final TextEditingController _searchController = TextEditingController();
  final MapService _mapService = MapService();
  List<PlaceSuggestion> _suggestions = [];
  bool _isLoading = false;
  Timer? _debounce;
  bool _hasSearched = false;

  @override
  void initState() {
    super.initState();
    _searchController.text = widget.initialQuery;
    if (widget.initialQuery.trim().isNotEmpty &&
        widget.initialQuery != 'Current Location' &&
        widget.initialQuery != 'Loading current location...') {
      _fetchSuggestions(widget.initialQuery);
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  void _onQueryChanged(String query) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 250), () {
      _fetchSuggestions(query);
    });
  }

  Future<void> _handleSubmit(String query) async {
    final trimmed = query.trim();
    if (trimmed.isEmpty) return;

    final riderPos = _riderLatLng();
    final parsed = CoordinateParser.tryParse(
      trimmed,
      referenceLat: riderPos?.latitude,
      referenceLng: riderPos?.longitude,
    );

    if (parsed != null) {
      if (!mounted) return;
      setState(() => _isLoading = true);
      String finalAddress = parsed.label ?? trimmed;
      double finalLat = parsed.latitude;
      double finalLng = parsed.longitude;
      try {
        final exact = await _mapService.resolveExactLocation(
          lat: parsed.latitude,
          lng: parsed.longitude,
          query: trimmed,
        );
        if (exact != null &&
            exact.address.isNotEmpty &&
            !exact.address.startsWith('Location (')) {
          finalAddress = exact.address;
          finalLat = exact.coordinates.latitude;
          finalLng = exact.coordinates.longitude;
        } else {
          final resolved = await _mapService.reverseGeocode(
            parsed.latitude,
            parsed.longitude,
          );
          if (resolved.isNotEmpty && !resolved.startsWith('Location (')) {
            finalAddress = resolved;
          }
        }
      } catch (_) {}

      if (!mounted) return;
      setState(() => _isLoading = false);

      Navigator.of(context).pop(
        LocationPoint(
          latitude: finalLat,
          longitude: finalLng,
          address: finalAddress,
        ),
      );
      return;
    }

    if (_suggestions.isNotEmpty) {
      _selectPlace(_suggestions.first);
    }
  }

  LatLng? _riderLatLng() {
    try {
      final loc = CustomChangeNotifierProvider.read<LocationProvider>(context);
      if (loc.hasRealFix) {
        return LatLng(loc.latitude, loc.longitude);
      }
    } catch (_) {}
    return null;
  }

  Future<void> _fetchSuggestions(String query) async {
    final q = query.trim();

    setState(() {
      _isLoading = true;
      _hasSearched = true;
    });

    final results = q.isEmpty
        ? <PlaceSuggestion>[]
        : await _mapService.searchPlaces(q, near: _riderLatLng());

    if (!mounted) return;

    setState(() {
      _suggestions = results;
      _isLoading = false;
    });
  }

  Future<void> _selectPlace(PlaceSuggestion place) async {
    var coords = place.coordinates;
    if (coords == null && (place.placeId.startsWith('pinned:') || place.placeId.startsWith('plus:'))) {
      final parts = place.placeId.split(':');
      if (parts.length >= 2) {
        final coordParts = parts[1].split(',');
        if (coordParts.length == 2) {
          final lat = double.tryParse(coordParts[0]);
          final lng = double.tryParse(coordParts[1]);
          if (lat != null && lng != null) {
            coords = LatLng(lat, lng);
          }
        }
      }
    }

    if (coords == null) {
      setState(() => _isLoading = true);
      coords = await _mapService.resolvePlace(place.placeId);
      if (mounted) setState(() => _isLoading = false);
    }

    if (!mounted) return;

    if (coords == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('We could not load that place. Please try another.'),
          backgroundColor: AppTheme.sunsetCoral,
        ),
      );
      return;
    }

    String address = place.placeId.startsWith('pinned:') ||
            place.placeId.startsWith('plus:')
        ? place.mainText
        : [
            place.mainText,
            place.secondaryText,
          ].where((s) => s.trim().isNotEmpty).join(', ');

    final isBroadCityOnly = !address.contains(',') &&
        CoordinateParser.pakistanCities.containsKey(address.toLowerCase().trim());

    final needsExactResolution = place.placeId.startsWith('pinned:') ||
        place.placeId.startsWith('plus:') ||
        address == 'Pinned Location' ||
        address.startsWith('Coordinates:') ||
        RegExp(r'[A-Za-z0-9]{4,8}\+[A-Za-z0-9]{2,5}').hasMatch(address) ||
        isBroadCityOnly ||
        !NativeMapService.isGranularAddress(address) ||
        address.toLowerCase().trim() == 'faisalabad' ||
        address.toLowerCase().trim() == 'jhang';

    if (needsExactResolution) {
      setState(() => _isLoading = true);
      try {
        final queryHint = _searchController.text.trim().isNotEmpty
            ? _searchController.text.trim()
            : (place.mainText.contains('+') ? place.mainText : null);

        final exact = await _mapService.resolveExactLocation(
          lat: coords.latitude,
          lng: coords.longitude,
          query: queryHint,
        );
        if (exact != null &&
            exact.address.isNotEmpty &&
            !exact.address.startsWith('Location (')) {
          address = exact.address;
          coords = exact.coordinates;
        } else {
          final resolved = await _mapService.reverseGeocode(
            coords.latitude,
            coords.longitude,
          );
          if (resolved.isNotEmpty && !resolved.startsWith('Location (')) {
            address = resolved;
          }
        }
      } catch (_) {}
      if (mounted) setState(() => _isLoading = false);
    }

    if (!mounted) return;
    final finalCoords = coords;
    if (finalCoords == null) return;

    Navigator.of(context).pop(
      LocationPoint(
        latitude: finalCoords.latitude,
        longitude: finalCoords.longitude,
        address: address,
      ),
    );
  }

  Future<void> _handleUseCurrentLocation() async {
    final loc = CustomChangeNotifierProvider.read<LocationProvider>(
      context,
    );
    double lat = loc.latitude;
    double lng = loc.longitude;
    if (!loc.hasRealFix) {
      await PermissionDisclosures.ensureForegroundLocation(context);
      if (!mounted) return;
      final fix = await loc.waitForFirstFix(
        timeout: const Duration(seconds: 4),
      );
      if (fix != null) {
        lat = fix.latitude;
        lng = fix.longitude;
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Acquiring GPS location... Please ensure location permissions are enabled.',
              ),
              duration: Duration(seconds: 3),
            ),
          );
        }
        return;
      }
    }

    String address = loc.address;
    if (address.isEmpty || !NativeMapService.isGranularAddress(address)) {
      try {
        final resolved = await _mapService.reverseGeocode(
          lat,
          lng,
        );
        if (resolved.isNotEmpty &&
            !resolved.startsWith('Location (') &&
            !resolved.startsWith('Pinned Spot')) {
          if (NativeMapService.isGranularAddress(resolved) ||
              !NativeMapService.isGranularAddress(address) ||
              address.isEmpty) {
            address = resolved;
          }
        }
      } catch (_) {}
    }
    if (address.isEmpty) address = 'Current Location';
    if (!mounted) return;
    Navigator.of(context).pop(
      LocationPoint(
        latitude: lat,
        longitude: lng,
        address: address,
      ),
    );
  }

  Widget _buildChooseOnMapActionBar({
    required BuildContext context,
    required AppColors c,
    required bool isDark,
    required double verticalPadding,
    required double horizontalPadding,
    required double badgePadding,
    required double iconSize,
    required double titleFontSize,
    required double subtitleFontSize,
    required double chevronSize,
    required double borderRadius,
  }) {
    return InkWell(
      borderRadius: BorderRadius.circular(borderRadius),
      onTap: () {
        Navigator.of(context).pop(
          ChooseOnMapSignal(isPickup: widget.isPickup),
        );
      },
      child: Container(
        padding: EdgeInsets.symmetric(
          horizontal: horizontalPadding,
          vertical: verticalPadding,
        ),
        decoration: BoxDecoration(
          color: isDark
              ? AppTheme.accentCyan.withValues(alpha: 0.1)
              : AppTheme.primaryBlue.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(borderRadius),
          border: Border.all(
            color: isDark
                ? AppTheme.accentCyan.withValues(alpha: 0.28)
                : AppTheme.primaryBlue.withValues(alpha: 0.22),
          ),
        ),
        child: Row(
          children: [
            Container(
              padding: EdgeInsets.all(badgePadding),
              decoration: BoxDecoration(
                gradient: AppTheme.brandGradient,
                shape: BoxShape.circle,
                boxShadow: AppTheme.glowShadow(
                  AppTheme.primaryBlue,
                  blur: 8,
                  opacity: 0.25,
                ),
              ),
              child: Icon(
                Icons.map_rounded,
                color: Colors.white,
                size: iconSize,
              ),
            ),
            SizedBox(width: (horizontalPadding * 0.85).clamp(8.0, 14.0)),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Choose on Map',
                    style: TextStyle(
                      color: c.textPrimary,
                      fontWeight: FontWeight.w700,
                      fontSize: titleFontSize,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Pinpoint exact spot with interactive map pin',
                    style: TextStyle(
                      color: c.textSecondary,
                      fontSize: subtitleFontSize,
                    ),
                  ),
                ],
              ),
            ),
            Icon(
              Icons.chevron_right_rounded,
              color: isDark ? AppTheme.accentCyan : AppTheme.primaryBlue,
              size: chevronSize,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildQuickActionTile({
    required BuildContext context,
    required AppColors c,
    required bool isDark,
    required IconData icon,
    required Color iconColor,
    required Color badgeBgColor,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
    required double badgeDiameter,
    required double iconSize,
    required double titleFontSize,
    required double subtitleFontSize,
    required double horizontalPadding,
    required double verticalPadding,
  }) {
    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: onTap,
      child: Padding(
        padding: EdgeInsets.symmetric(
          horizontal: horizontalPadding,
          vertical: verticalPadding,
        ),
        child: Row(
          children: [
            Container(
              width: badgeDiameter,
              height: badgeDiameter,
              decoration: BoxDecoration(
                color: badgeBgColor,
                shape: BoxShape.circle,
              ),
              child: Center(
                child: Icon(
                  icon,
                  color: iconColor,
                  size: iconSize,
                ),
              ),
            ),
            SizedBox(width: (horizontalPadding * 0.9).clamp(8.0, 14.0)),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      color: c.textPrimary,
                      fontWeight: FontWeight.w700,
                      fontSize: titleFontSize,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: TextStyle(
                      color: c.textSecondary,
                      fontSize: subtitleFontSize,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyStatePrompt({
    required AppColors c,
    required IconData icon,
    required String title,
    String? subtitle,
    Widget? actionWidget,
    required double iconSize,
    required double titleFontSize,
    required double subtitleFontSize,
    required double minHeight,
    required double gap,
  }) {
    return ConstrainedBox(
      constraints: BoxConstraints(minHeight: minHeight),
      child: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, color: c.textMuted, size: iconSize),
              SizedBox(height: gap),
              Text(
                title,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: c.textPrimary,
                  fontWeight: FontWeight.w600,
                  fontSize: titleFontSize,
                ),
              ),
              if (subtitle != null) ...[
                SizedBox(height: (gap * 0.65).clamp(4.0, 8.0)),
                Text(
                  subtitle,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: c.textSecondary,
                    fontSize: subtitleFontSize,
                  ),
                ),
              ],
              if (actionWidget != null) ...[
                SizedBox(height: (gap * 1.2).clamp(10.0, 18.0)),
                actionWidget,
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyState({
    required BuildContext context,
    required String trimmed,
    required AppColors c,
    required bool isDark,
    required BoxConstraints constraints,
    required double verticalGap,
    required double badgeDiameter,
    required double actionIconSize,
    required double actionTitleFontSize,
    required double actionSubtitleFontSize,
    required double actionTileHorizontalPadding,
    required double actionTileVerticalPadding,
    required double emptyIconSize,
    required double emptyPromptMinHeight,
  }) {
    if (trimmed.isEmpty && !_hasSearched) {
      return LayoutBuilder(
        builder: (context, scrollConstraints) {
          return SingleChildScrollView(
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            physics: const AlwaysScrollableScrollPhysics(),
            child: ConstrainedBox(
              constraints: BoxConstraints(
                minHeight: scrollConstraints.maxHeight,
              ),
              child: IntrinsicHeight(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _buildQuickActionTile(
                      context: context,
                      c: c,
                      isDark: isDark,
                      icon: Icons.my_location,
                      iconColor: AppTheme.emeraldGreen,
                      badgeBgColor:
                          AppTheme.emeraldGreen.withValues(alpha: 0.15),
                      title: 'Use Current Location',
                      subtitle: 'Start trip from your GPS position',
                      badgeDiameter: badgeDiameter,
                      iconSize: actionIconSize,
                      titleFontSize: actionTitleFontSize,
                      subtitleFontSize: actionSubtitleFontSize,
                      horizontalPadding: actionTileHorizontalPadding,
                      verticalPadding: actionTileVerticalPadding,
                      onTap: _handleUseCurrentLocation,
                    ),
                    Divider(color: c.border, height: 1),
                    _buildQuickActionTile(
                      context: context,
                      c: c,
                      isDark: isDark,
                      icon: Icons.pin_drop_rounded,
                      iconColor:
                          isDark ? AppTheme.accentCyan : AppTheme.primaryBlue,
                      badgeBgColor: (isDark
                              ? AppTheme.accentCyan
                              : AppTheme.primaryBlue)
                          .withValues(alpha: 0.15),
                      title: 'Set Location on Map',
                      subtitle: 'Move and place pin directly on the map',
                      badgeDiameter: badgeDiameter,
                      iconSize: actionIconSize,
                      titleFontSize: actionTitleFontSize,
                      subtitleFontSize: actionSubtitleFontSize,
                      horizontalPadding: actionTileHorizontalPadding,
                      verticalPadding: actionTileVerticalPadding,
                      onTap: () {
                        Navigator.of(context).pop(
                          ChooseOnMapSignal(isPickup: widget.isPickup),
                        );
                      },
                    ),
                    Divider(color: c.border, height: 1),
                    Expanded(
                      child: _buildEmptyStatePrompt(
                        c: c,
                        icon: Icons.search,
                        title: 'Type a destination or area name',
                        subtitle:
                            'Tip: paste coordinates to set exact location',
                        iconSize: emptyIconSize,
                        titleFontSize: actionTitleFontSize,
                        subtitleFontSize: actionSubtitleFontSize,
                        minHeight: emptyPromptMinHeight,
                        gap: (verticalGap * 0.9).clamp(6.0, 12.0),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      );
    } else if (trimmed.isEmpty || trimmed.length < 2) {
      return SingleChildScrollView(
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        physics: const AlwaysScrollableScrollPhysics(),
        child: _buildEmptyStatePrompt(
          c: c,
          icon: Icons.travel_explore,
          title: 'Type at least 2 characters to search',
          iconSize: emptyIconSize,
          titleFontSize: actionTitleFontSize,
          subtitleFontSize: actionSubtitleFontSize,
          minHeight: (constraints.maxHeight * 0.35).clamp(120.0, 300.0),
          gap: (verticalGap * 0.9).clamp(6.0, 12.0),
        ),
      );
    }

    return SingleChildScrollView(
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      physics: const AlwaysScrollableScrollPhysics(),
      child: _buildEmptyStatePrompt(
        c: c,
        icon: Icons.location_off_outlined,
        title: 'No places found for "$trimmed"',
        subtitle: 'Try a different street name or city.',
        actionWidget: OutlinedButton.icon(
          icon: const Icon(Icons.refresh, size: 16),
          label: const Text('Retry Search'),
          onPressed: () => _fetchSuggestions(trimmed),
        ),
        iconSize: emptyIconSize,
        titleFontSize: actionTitleFontSize,
        subtitleFontSize: actionSubtitleFontSize,
        minHeight: (constraints.maxHeight * 0.35).clamp(120.0, 300.0),
        gap: (verticalGap * 0.9).clamp(6.0, 12.0),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final trimmed = _searchController.text.trim();
    final viewInsets = MediaQuery.viewInsetsOf(context);
    final isKeyboardOpen = viewInsets.bottom > 0;
    final responsive = ResponsiveLayoutHelper(context);

    return Scaffold(
      backgroundColor: c.canvas,
      resizeToAvoidBottomInset: true,
      bottomNavigationBar: isKeyboardOpen ? null : const ReservedBottomAdBar(),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: Text(
          widget.title,
          style: TextStyle(
            fontWeight: FontWeight.w700,
            fontSize: responsive.fontSize(18),
            color: c.textPrimary,
          ),
        ),
        leading: IconButton(
          tooltip: 'Back',
          icon: Icon(
            Icons.arrow_back_ios_new,
            color: c.textPrimary,
            size: responsive.scale(20).clamp(18.0, 24.0),
          ),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final availableWidth = constraints.maxWidth;
            final availableHeight = constraints.maxHeight;

            // 1. Horizontal screen padding clamped to safe ergonomic ranges
            final horizontalPadding =
                (availableWidth * 0.045).clamp(14.0, 24.0);

            // 2. Vertical section gaps clamped to safe ergonomic ranges
            final verticalGap = (availableHeight * 0.018).clamp(6.0, 16.0);

            // 3. Search input dynamic sizing & padding
            final searchMinHeight =
                (availableHeight * 0.065).clamp(44.0, 56.0);
            final searchHorizontalPadding =
                (availableWidth * 0.035).clamp(10.0, 16.0);
            final searchIconSize = (availableWidth * 0.055).clamp(18.0, 24.0);
            final searchFontSize = (availableWidth * 0.04).clamp(14.0, 16.0);
            final searchHintFontSize =
                (availableWidth * 0.035).clamp(12.0, 14.0);
            final searchBorderRadius =
                (availableWidth * 0.035).clamp(12.0, 16.0);

            // 4. Quick-action tile & badge dynamic sizing
            final actionVerticalPadding =
                (availableHeight * 0.014).clamp(8.0, 14.0);
            final actionHorizontalPadding =
                (availableWidth * 0.035).clamp(10.0, 16.0);
            final actionBadgePadding = (availableWidth * 0.02).clamp(6.0, 8.0);
            final actionMapIconSize =
                (availableWidth * 0.042).clamp(14.0, 18.0);
            final actionTitleFontSize =
                (availableWidth * 0.038).clamp(13.0, 15.0);
            final actionSubtitleFontSize =
                (availableWidth * 0.032).clamp(11.0, 13.0);
            final actionChevronSize = (availableWidth * 0.05).clamp(18.0, 24.0);
            final actionBorderRadius =
                (availableWidth * 0.03).clamp(10.0, 14.0);

            // Quick-action tiles (Current Location / Set Location on Map)
            final badgeDiameter = (availableWidth * 0.10).clamp(36.0, 46.0);
            final quickActionIconSize =
                (availableWidth * 0.05).clamp(18.0, 24.0);
            final tileHorizontalPadding =
                (availableWidth * 0.03).clamp(8.0, 14.0);
            final tileVerticalPadding =
                (availableHeight * 0.008).clamp(2.0, 8.0);

            // 5. Empty-state search icon & prompt dynamic sizing
            final emptyIconSize = (availableHeight * 0.08).clamp(28.0, 52.0);
            final emptyPromptMinHeight =
                (availableHeight * 0.22).clamp(72.0, 220.0);

            return Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 640),
                child: Padding(
                  padding: EdgeInsets.symmetric(horizontal: horizontalPadding),
                  child: Column(
                    children: [
                      SizedBox(height: (verticalGap * 0.5).clamp(2.0, 6.0)),
                      // Search Input Box
                      ConstrainedBox(
                        constraints: BoxConstraints(minHeight: searchMinHeight),
                        child: GlassContainer(
                          backgroundColor:
                              isDark ? c.surfaceRaised : c.surface,
                          borderColor: c.border,
                          isDark: isDark,
                          borderRadius: searchBorderRadius,
                          padding: EdgeInsets.symmetric(
                            horizontal: searchHorizontalPadding,
                            vertical: 4,
                          ),
                          child: Row(
                            children: [
                              Icon(
                                Icons.search,
                                color: isDark
                                    ? AppTheme.accentCyan
                                    : AppTheme.primaryBlue,
                                size: searchIconSize,
                              ),
                              SizedBox(
                                width: (searchHorizontalPadding * 0.75)
                                    .clamp(6.0, 12.0),
                              ),
                              Expanded(
                                child: TextField(
                                  controller: _searchController,
                                  autofocus: true,
                                  style: TextStyle(
                                    color: c.textPrimary,
                                    fontSize: searchFontSize,
                                  ),
                                  textInputAction: TextInputAction.search,
                                  onSubmitted: (val) => _handleSubmit(val),
                                  decoration: InputDecoration(
                                    hintText:
                                        'Search street, Plus Code, coordinates...',
                                    hintStyle: TextStyle(
                                      color: c.textMuted,
                                      fontSize: searchHintFontSize,
                                    ),
                                    border: InputBorder.none,
                                    isDense: true,
                                  ),
                                  onChanged: _onQueryChanged,
                                ),
                              ),
                              if (_isLoading)
                                Padding(
                                  padding: EdgeInsets.symmetric(
                                    horizontal: (searchHorizontalPadding * 0.6)
                                        .clamp(6.0, 10.0),
                                  ),
                                  child: SizedBox(
                                    width: (searchIconSize * 0.85)
                                        .clamp(16.0, 20.0),
                                    height: (searchIconSize * 0.85)
                                        .clamp(16.0, 20.0),
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: isDark
                                          ? AppTheme.accentCyan
                                          : AppTheme.primaryBlue,
                                    ),
                                  ),
                                )
                              else if (trimmed.isNotEmpty)
                                IconButton(
                                  tooltip: 'Clear search',
                                  icon: Icon(
                                    Icons.close,
                                    color: c.textMuted,
                                    size: searchIconSize * 0.85,
                                  ),
                                  onPressed: () {
                                    _searchController.clear();
                                    _debounce?.cancel();
                                    setState(() {
                                      _suggestions = [];
                                      _hasSearched = false;
                                    });
                                  },
                                ),
                            ],
                          ),
                        ),
                      ),

                      SizedBox(height: verticalGap),

                      // Professional "Choose on Map" Action Bar
                      _buildChooseOnMapActionBar(
                        context: context,
                        c: c,
                        isDark: isDark,
                        verticalPadding: actionVerticalPadding,
                        horizontalPadding: actionHorizontalPadding,
                        badgePadding: actionBadgePadding,
                        iconSize: actionMapIconSize,
                        titleFontSize: actionTitleFontSize,
                        subtitleFontSize: actionSubtitleFontSize,
                        chevronSize: actionChevronSize,
                        borderRadius: actionBorderRadius,
                      ),

                      SizedBox(height: (verticalGap * 0.8).clamp(4.0, 10.0)),

                      if (_isLoading)
                        LinearProgressIndicator(
                          backgroundColor: Colors.transparent,
                          color: isDark
                              ? AppTheme.accentCyan
                              : AppTheme.primaryBlue,
                          minHeight: 2,
                        ),

                      SizedBox(height: (verticalGap * 0.6).clamp(2.0, 8.0)),

                      // Suggestions or Keyboard-aware Scrollable Content
                      Expanded(
                        child: _suggestions.isEmpty
                            ? (_isLoading
                                ? ListView.separated(
                                    keyboardDismissBehavior:
                                        ScrollViewKeyboardDismissBehavior.onDrag,
                                    itemCount: 4,
                                    separatorBuilder: (_, index) =>
                                        const SizedBox(height: 4),
                                    itemBuilder: (_, index) =>
                                        const _SuggestionSkeletonRow(),
                                  )
                                : _buildEmptyState(
                                    context: context,
                                    trimmed: trimmed,
                                    c: c,
                                    isDark: isDark,
                                    constraints: constraints,
                                    verticalGap: verticalGap,
                                    badgeDiameter: badgeDiameter,
                                    actionIconSize: quickActionIconSize,
                                    actionTitleFontSize: actionTitleFontSize,
                                    actionSubtitleFontSize:
                                        actionSubtitleFontSize,
                                    actionTileHorizontalPadding:
                                        tileHorizontalPadding,
                                    actionTileVerticalPadding:
                                        tileVerticalPadding,
                                    emptyIconSize: emptyIconSize,
                                    emptyPromptMinHeight:
                                        emptyPromptMinHeight,
                                  ))
                            : ListView.separated(
                                keyboardDismissBehavior:
                                    ScrollViewKeyboardDismissBehavior.onDrag,
                                physics:
                                    const AlwaysScrollableScrollPhysics(),
                                itemCount: _suggestions.length,
                                separatorBuilder: (_, index) => Divider(
                                  color: c.border,
                                  height: 1,
                                ),
                                itemBuilder: (context, index) {
                                  final item = _suggestions[index];
                                  final isPinned =
                                      item.placeId.startsWith('pinned:') ||
                                          item.placeId.startsWith('plus:') ||
                                          item.placeId.startsWith('coord:');

                                  return ListTile(
                                    contentPadding: EdgeInsets.symmetric(
                                      horizontal: tileHorizontalPadding,
                                      vertical: tileVerticalPadding,
                                    ),
                                    leading: Container(
                                      width: badgeDiameter,
                                      height: badgeDiameter,
                                      decoration: BoxDecoration(
                                        color: isPinned
                                            ? (isDark
                                                ? AppTheme.accentCyan
                                                    .withValues(alpha: 0.18)
                                                : AppTheme.emeraldGreen
                                                    .withValues(alpha: 0.15))
                                            : (isDark
                                                ? c.surfaceRaised
                                                : c.surfaceMuted),
                                        shape: BoxShape.circle,
                                      ),
                                      child: Center(
                                        child: Icon(
                                          isPinned
                                              ? Icons.push_pin_rounded
                                              : Icons.location_on,
                                          color: isPinned
                                              ? (isDark
                                                  ? AppTheme.accentCyan
                                                  : AppTheme.emeraldGreen)
                                              : (isDark
                                                  ? AppTheme.accentCyan
                                                  : AppTheme.primaryBlue),
                                          size: quickActionIconSize,
                                        ),
                                      ),
                                    ),
                                    title: Row(
                                      children: [
                                        Expanded(
                                          child: Text(
                                            item.mainText,
                                            maxLines: 2,
                                            overflow: TextOverflow.ellipsis,
                                            style: TextStyle(
                                              color: isPinned
                                                  ? (isDark
                                                      ? AppTheme.accentCyan
                                                      : AppTheme.primaryBlue)
                                                  : c.textPrimary,
                                              fontWeight: FontWeight.w600,
                                              fontSize: actionTitleFontSize,
                                            ),
                                          ),
                                        ),
                                        if (isPinned)
                                          Container(
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 6,
                                              vertical: 2,
                                            ),
                                            decoration: BoxDecoration(
                                              color: (isDark
                                                      ? AppTheme.accentCyan
                                                      : AppTheme.emeraldGreen)
                                                  .withValues(alpha: 0.15),
                                              borderRadius:
                                                  BorderRadius.circular(4),
                                            ),
                                            child: Text(
                                              'PINNED',
                                              style: TextStyle(
                                                fontSize: 10,
                                                fontWeight: FontWeight.w800,
                                                color: isDark
                                                    ? AppTheme.accentCyan
                                                    : AppTheme.emeraldGreen,
                                                letterSpacing: 0.5,
                                              ),
                                            ),
                                          ),
                                      ],
                                    ),
                                    subtitle: item.secondaryText.isNotEmpty
                                        ? Text(
                                            item.secondaryText,
                                            maxLines: 2,
                                            overflow: TextOverflow.ellipsis,
                                            style: TextStyle(
                                              color: c.textSecondary,
                                              fontSize:
                                                  actionSubtitleFontSize,
                                            ),
                                          )
                                        : null,
                                    onTap: () => _selectPlace(item),
                                  );
                                },
                              ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

class _SuggestionSkeletonRow extends StatelessWidget {
  const _SuggestionSkeletonRow();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: Row(
        children: [
          SkeletonBox(
            width: 36,
            height: 36,
            borderRadius: BorderRadius.circular(18),
          ),
          const SizedBox(width: 12),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SkeletonBox(height: 12),
                SizedBox(height: 6),
                SkeletonBox(height: 10, width: 140),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
