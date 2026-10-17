import 'dart:async';
import 'package:flutter/material.dart';
import '../../services/native_map_service.dart';

import '../../core/provider/custom_provider.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/design_tokens.dart';
import '../../domain/models/location_point_model.dart';
import '../../providers/location_provider.dart';
import '../../services/coordinate_parser.dart';
import '../../services/map_service.dart';
import '../common/glass_container.dart';
import '../common/skeleton.dart';

class AddressSearchScreen extends StatefulWidget {
  final String title;
  final String initialQuery;

  const AddressSearchScreen({
    super.key,
    this.title = 'Select Address',
    this.initialQuery = '',
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
      Navigator.of(context).pop(
        LocationPoint(
          latitude: parsed.latitude,
          longitude: parsed.longitude,
          address: parsed.label ?? trimmed,
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

    final address = place.placeId.startsWith('pinned:') ||
            place.placeId.startsWith('plus:')
        ? place.mainText
        : [
            place.mainText,
            place.secondaryText,
          ].where((s) => s.trim().isNotEmpty).join(', ');

    Navigator.of(context).pop(
      LocationPoint(
        latitude: coords.latitude,
        longitude: coords.longitude,
        address: address,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final trimmed = _searchController.text.trim();

    return Scaffold(
      backgroundColor: c.canvas,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: Text(
            widget.title,
            style: TextStyle(
              fontWeight: FontWeight.w700,
              fontSize: 18,
              color: c.textPrimary,
            ),
        ),
        leading: IconButton(
          tooltip: 'Back',
          icon: Icon(
            Icons.arrow_back_ios_new,
            color: c.textPrimary,
            size: 20,
          ),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Column(
            children: [
              // Search Input Box
              GlassContainer(
                backgroundColor: isDark ? c.surfaceRaised : c.surface,
                borderColor: c.border,
                isDark: isDark,
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 4,
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.search,
                      color: isDark ? AppTheme.accentCyan : AppTheme.primaryBlue,
                      size: 22,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: TextField(
                        controller: _searchController,
                        autofocus: true,
                        style: TextStyle(
                          color: c.textPrimary,
                          fontSize: 16,
                        ),
                        textInputAction: TextInputAction.search,
                        onSubmitted: (val) => _handleSubmit(val),
                        decoration: InputDecoration(
                          hintText:
                              'Search street, Plus Code, coordinates...',
                          hintStyle: TextStyle(
                            color: c.textMuted,
                            fontSize: 14,
                          ),
                          border: InputBorder.none,
                        ),
                        onChanged: _onQueryChanged,
                      ),
                    ),
                    if (_isLoading)
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 10),
                        child: SizedBox(
                          width: 18,
                          height: 18,
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
                          size: 18,
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

              const SizedBox(height: 12),

              // Professional "Choose on Map" Action Bar
              InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: () {
                  Navigator.of(context).pop(
                    const LocationPoint(
                      latitude: 0,
                      longitude: 0,
                      address: '__CHOOSE_ON_MAP__',
                    ),
                  );
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
                  decoration: BoxDecoration(
                    color: isDark
                        ? AppTheme.accentCyan.withValues(alpha: 0.1)
                        : AppTheme.primaryBlue.withValues(alpha: 0.06),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: isDark
                          ? AppTheme.accentCyan.withValues(alpha: 0.28)
                          : AppTheme.primaryBlue.withValues(alpha: 0.22),
                    ),
                  ),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(7),
                        decoration: BoxDecoration(
                          gradient: AppTheme.brandGradient,
                          shape: BoxShape.circle,
                          boxShadow: AppTheme.glowShadow(
                            AppTheme.primaryBlue,
                            blur: 8,
                            opacity: 0.25,
                          ),
                        ),
                        child: const Icon(
                          Icons.map_rounded,
                          color: Colors.white,
                          size: 16,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Choose on Map',
                              style: TextStyle(
                                color: c.textPrimary,
                                fontWeight: FontWeight.w700,
                                fontSize: 14,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              'Pinpoint exact spot with interactive map pin',
                              style: TextStyle(
                                color: c.textSecondary,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Icon(
                        Icons.chevron_right_rounded,
                        color: isDark ? AppTheme.accentCyan : AppTheme.primaryBlue,
                        size: 22,
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 10),

              if (_isLoading)
                LinearProgressIndicator(
                  backgroundColor: Colors.transparent,
                  color: isDark ? AppTheme.accentCyan : AppTheme.primaryBlue,
                  minHeight: 2,
                ),

              const SizedBox(height: 8),

              // Suggestions list
              Expanded(
                child: _suggestions.isEmpty
                    ? (_isLoading
                          ? ListView.separated(
                              itemCount: 4,
                              separatorBuilder: (_, index) =>
                                  const SizedBox(height: 4),
                              itemBuilder: (context, index) =>
                                  const _SuggestionSkeletonRow(),
                            )
                          : _buildEmptyState(trimmed, c))
                    : ListView.separated(
                        itemCount: _suggestions.length,
                        separatorBuilder: (_, index) => Divider(
                          color: c.border,
                          height: 1,
                        ),
                        itemBuilder: (context, index) {
                          final item = _suggestions[index];
                          final isPinned = item.placeId.startsWith('pinned:') ||
                              item.placeId.startsWith('plus:') ||
                              item.placeId.startsWith('coord:');

                          return ListTile(
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 4,
                            ),
                            leading: Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: isPinned
                                    ? (isDark
                                        ? AppTheme.accentCyan.withValues(alpha: 0.18)
                                        : AppTheme.emeraldGreen.withValues(alpha: 0.15))
                                    : (isDark ? c.surfaceRaised : c.surfaceMuted),
                                shape: BoxShape.circle,
                              ),
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
                                size: 20,
                              ),
                            ),
                            title: Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    item.mainText,
                                    style: TextStyle(
                                      color: isPinned
                                          ? (isDark
                                              ? AppTheme.accentCyan
                                              : AppTheme.primaryBlue)
                                          : c.textPrimary,
                                      fontWeight: FontWeight.w600,
                                      fontSize: 14,
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
                                      borderRadius: BorderRadius.circular(4),
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
                                    style: TextStyle(
                                      color: c.textSecondary,
                                      fontSize: 12,
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
  }

  Widget _buildEmptyState(String trimmed, AppColors c) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    if (trimmed.isEmpty && !_hasSearched) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ListTile(
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 12,
              vertical: 4,
            ),
            leading: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: AppTheme.emeraldGreen.withValues(alpha: 0.15),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.my_location,
                color: AppTheme.emeraldGreen,
                size: 20,
              ),
            ),
            title: Text(
              'Use Current Location',
              style: TextStyle(
                color: c.textPrimary,
                fontWeight: FontWeight.w700,
                fontSize: 14,
              ),
            ),
            subtitle: Text(
              'Start trip from your GPS position',
              style: TextStyle(
                color: c.textSecondary,
                fontSize: 12,
              ),
            ),
            onTap: () async {
              final loc = CustomChangeNotifierProvider.read<LocationProvider>(
                context,
              );
              String address = 'Current Location';
              try {
                final resolved = await _mapService.reverseGeocode(
                  loc.latitude,
                  loc.longitude,
                );
                if (resolved.isNotEmpty) address = resolved;
              } catch (_) {}
              if (!mounted) return;
              Navigator.of(context).pop(
                LocationPoint(
                  latitude: loc.latitude,
                  longitude: loc.longitude,
                  address: address,
                ),
              );
            },
          ),
          Divider(color: c.border, height: 1),
          ListTile(
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 12,
              vertical: 4,
            ),
            leading: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: (isDark ? AppTheme.accentCyan : AppTheme.primaryBlue)
                    .withValues(alpha: 0.15),
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.pin_drop_rounded,
                color: isDark ? AppTheme.accentCyan : AppTheme.primaryBlue,
                size: 20,
              ),
            ),
            title: Text(
              'Set Location on Map',
              style: TextStyle(
                color: c.textPrimary,
                fontWeight: FontWeight.w700,
                fontSize: 14,
              ),
            ),
            subtitle: Text(
              'Move and place pin directly on the map',
              style: TextStyle(
                color: c.textSecondary,
                fontSize: 12,
              ),
            ),
            onTap: () {
              Navigator.of(context).pop(
                const LocationPoint(
                  latitude: 0,
                  longitude: 0,
                  address: '__CHOOSE_ON_MAP__',
                ),
              );
            },
          ),
          Divider(color: c.border, height: 1),
          const SizedBox(height: 24),
          Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.search, color: c.textMuted, size: 32),
                  const SizedBox(height: 12),
                  Text(
                    'Type a destination or area name',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: c.textSecondary, fontSize: 14),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Tip: paste coordinates to set exact location',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: c.textMuted,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      );
    } else if (trimmed.isEmpty || trimmed.length < 2) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.travel_explore, color: c.textMuted, size: 32),
              const SizedBox(height: 12),
              Text(
                'Type at least 2 characters to search',
                textAlign: TextAlign.center,
                style: TextStyle(color: c.textSecondary, fontSize: 14),
              ),
            ],
          ),
        ),
      );
    }

    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.location_off_outlined, color: c.textMuted, size: 32),
            const SizedBox(height: 12),
            Text(
              'No places found for "$trimmed"',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: c.textPrimary,
                fontWeight: FontWeight.w600,
                fontSize: 14,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Try a different street name or city.',
              textAlign: TextAlign.center,
              style: TextStyle(color: c.textSecondary, fontSize: 12),
            ),
            const SizedBox(height: 16),
            OutlinedButton.icon(
              icon: const Icon(Icons.refresh, size: 16),
              label: const Text('Retry Search'),
              onPressed: () => _fetchSuggestions(trimmed),
            ),
          ],
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
