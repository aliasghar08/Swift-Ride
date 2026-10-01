import 'dart:async';
import 'package:flutter/material.dart';
import '../../core/theme/app_theme.dart';
import '../../domain/models/location_point_model.dart';
import '../../services/map_service.dart';
import '../common/glass_container.dart';

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

  void _selectPlace(PlaceSuggestion place) {
    Navigator.of(context).pop(
      LocationPoint(
        latitude: place.coordinates.latitude,
        longitude: place.coordinates.longitude,
        address: '${place.mainText}, ${place.secondaryText}',
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F172A),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: Text(
          widget.title,
          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 18, color: Colors.white),
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new, color: Colors.white, size: 20),
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
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
                child: Row(
                  children: [
                    const Icon(Icons.search, color: AppTheme.accentCyan, size: 22),
                    const SizedBox(width: 10),
                    Expanded(
                      child: TextField(
                        controller: _searchController,
                        autofocus: true,
                        style: const TextStyle(color: Colors.white, fontSize: 16),
                        decoration: InputDecoration(
                          hintText: 'Search street, area, landmark in Pakistan...',
                          hintStyle: TextStyle(color: Colors.white.withValues(alpha: 0.5), fontSize: 14),
                          border: InputBorder.none,
                        ),
                        onChanged: _onQueryChanged,
                      ),
                    ),
                    if (_searchController.text.isNotEmpty)
                      IconButton(
                        icon: const Icon(Icons.close, color: Colors.white70, size: 18),
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
                    ? Center(
                        child: Text(
                          _isLoading ? 'Searching...' : 'Type a destination or area name',
                          style: TextStyle(color: Colors.white.withValues(alpha: 0.6), fontSize: 14),
                        ),
                      )
                    : ListView.separated(
                        itemCount: _suggestions.length,
                        separatorBuilder: (_, index) => Divider(
                          color: Colors.white.withValues(alpha: 0.1),
                          height: 1,
                        ),
                        itemBuilder: (context, index) {
                          final item = _suggestions[index];
                          return ListTile(
                            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                            leading: Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: 0.1),
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(Icons.location_on, color: AppTheme.accentCyan, size: 20),
                            ),
                            title: Text(
                              item.mainText,
                              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 14),
                            ),
                            subtitle: Text(
                              item.secondaryText,
                              style: TextStyle(color: Colors.white.withValues(alpha: 0.7), fontSize: 12),
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
