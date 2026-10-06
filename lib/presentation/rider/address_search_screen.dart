import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import '../../core/theme/design_tokens.dart';
import '../../domain/models/location_point_model.dart';
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

  @override
  void initState() {
    super.initState();
    _searchController.text = widget.initialQuery;
    _fetchSuggestions(widget.initialQuery);
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

  Future<void> _fetchSuggestions(String query) async {
    setState(() => _isLoading = true);
    final results = await _mapService.searchPlaces(query);
    if (mounted) {
      setState(() {
        _suggestions = results;
        _isLoading = false;
      });
    }
  }

  Future<void> _selectPlace(PlaceSuggestion place) async {
    var coords = place.coordinates;

    // Remote autocomplete predictions carry no location, so resolve it before
    // returning. This used to be impossible because every suggestion came with
    // invented coordinates baked in.
    if (coords == null) {
      setState(() => _isLoading = true);
      coords = await _mapService.resolvePlace(place.placeId);
      if (mounted) setState(() => _isLoading = false);
    }

    if (coords == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('We could not load that place. Please try another.'),
          backgroundColor: AppTheme.sunsetCoral,
        ),
      );
      return;
    }

    if (!mounted) return;
    Navigator.of(context).pop(
      LocationPoint(
        latitude: coords.latitude,
        longitude: coords.longitude,
        address: [
          place.mainText,
          place.secondaryText,
        ].where((s) => s.trim().isNotEmpty).join(', '),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
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
                          color: Colors.white,
                          fontSize: 16,
                        ),
                        decoration: InputDecoration(
                          hintText:
                              'Search street, area, landmark in Pakistan...',
                          hintStyle: TextStyle(
                            color: Colors.white.withValues(alpha: 0.5),
                            fontSize: 14,
                          ),
                          border: InputBorder.none,
                        ),
                        onChanged: _onQueryChanged,
                      ),
                    ),
                    if (_searchController.text.isNotEmpty)
                      IconButton(
                        tooltip: 'Clear search',
                        icon: const Icon(
                          Icons.close,
                          color: Colors.white70,
                          size: 18,
                        ),
                        onPressed: () {
                          _searchController.clear();
                          _fetchSuggestions('');
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
                          // Show the shape of the results while they load, rather
                          // than a bare "Searching..." label.
                          ? ListView.separated(
                              itemCount: 4,
                              separatorBuilder: (_, index) =>
                                  const SizedBox(height: 4),
                              itemBuilder: (context, index) =>
                                  const _SuggestionSkeletonRow(),
                            )
                          : Center(
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 24,
                                ),
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      _searchController.text.trim().isEmpty
                                          ? Icons.search
                                          : Icons.location_off_outlined,
                                      color: Colors.white.withValues(
                                        alpha: 0.4,
                                      ),
                                      size: 32,
                                    ),
                                    const SizedBox(height: 12),
                                    Text(
                                      _searchController.text.trim().isEmpty
                                          ? 'Type a destination or area name'
                                          : 'No places matched "${_searchController.text.trim()}"',
                                      textAlign: TextAlign.center,
                                      style: TextStyle(
                                        color: Colors.white.withValues(
                                          alpha: 0.6,
                                        ),
                                        fontSize: 14,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ))
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
}

/// Placeholder row matching a suggestion ListTile, tinted for the dark overlay.
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
