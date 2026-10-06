import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../../core/provider/custom_provider.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/design_tokens.dart';
import '../../domain/models/location_point_model.dart';
import '../../providers/location_provider.dart';
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
    if (widget.initialQuery.trim().isNotEmpty) {
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
    _debounce = Timer(const Duration(milliseconds: 300), () {
      _fetchSuggestions(query);
    });
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

    final address = [
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
    final trimmed = _searchController.text.trim();

    return Scaffold(
      backgroundColor: c.mapChromeStrong,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: Text(
          widget.title,
          style: const TextStyle(
            fontWeight: FontWeight.w700,
            fontSize: 18,
            color: Colors.white,
          ),
        ),
        leading: IconButton(
          tooltip: 'Back',
          icon: const Icon(
            Icons.arrow_back_ios_new,
            color: Colors.white,
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
                backgroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 4,
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.search,
                      color: AppTheme.accentCyan,
                      size: 22,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: TextField(
                        controller: _searchController,
                        autofocus: true,
                        style: const TextStyle(
                          color: Colors.black87,
                          fontSize: 16,
                        ),
                        decoration: const InputDecoration(
                          hintText:
                              'Search street, area, landmark in Pakistan...',
                          hintStyle: TextStyle(
                            color: Colors.black54,
                            fontSize: 14,
                          ),
                          border: InputBorder.none,
                        ),
                        onChanged: _onQueryChanged,
                      ),
                    ),
                    if (trimmed.isNotEmpty)
                      IconButton(
                        tooltip: 'Clear search',
                        icon: const Icon(
                          Icons.close,
                          color: Colors.black54,
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

              if (_isLoading)
                const LinearProgressIndicator(
                  backgroundColor: Colors.transparent,
                  color: AppTheme.accentCyan,
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
                          : _buildEmptyState(trimmed))
                    : ListView.separated(
                        itemCount: _suggestions.length,
                        separatorBuilder: (_, index) => Divider(
                          color: Colors.white.withValues(alpha: 0.1),
                          height: 1,
                        ),
                        itemBuilder: (context, index) {
                          final item = _suggestions[index];
                          return ListTile(
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 4,
                            ),
                            leading: Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: 0.1),
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(
                                Icons.location_on,
                                color: AppTheme.accentCyan,
                                size: 20,
                              ),
                            ),
                            title: Text(
                              item.mainText,
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w600,
                                fontSize: 14,
                              ),
                            ),
                            subtitle: Text(
                              item.secondaryText,
                              style: TextStyle(
                                color: Colors.white.withValues(alpha: 0.7),
                                fontSize: 12,
                              ),
                            ),
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

  Widget _buildEmptyState(String trimmed) {
    final IconData icon;
    final String message;

    if (trimmed.isEmpty && !_hasSearched) {
      icon = Icons.search;
      message = 'Type a destination or area name';
    } else if (trimmed.isEmpty) {
      icon = Icons.travel_explore;
      message = 'Type at least 2 characters to search';
    } else if (trimmed.length < 2) {
      icon = Icons.more_horiz;
      message = 'Keep typing…';
    } else {
      icon = Icons.location_off_outlined;
      message = 'No places matched "$trimmed"';
    }

    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              color: Colors.white.withValues(alpha: 0.4),
              size: 32,
            ),
            const SizedBox(height: 12),
            Text(
              message,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.6),
                fontSize: 14,
              ),
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
    final base = Colors.white.withValues(alpha: 0.08);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: Row(
        children: [
          SkeletonBox(
            width: 36,
            height: 36,
            baseColor: base,
            borderRadius: BorderRadius.circular(18),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SkeletonBox(height: 12, baseColor: base),
                const SizedBox(height: 6),
                SkeletonBox(height: 10, width: 140, baseColor: base),
              ],
            ),
          ),
        ],
      ),
    );
  }
}