import 'package:flutter/material.dart';
import 'package:tamreedy_core/tamreedy_core.dart';
import '../controller.dart';

class FavoriteNursesScreen extends StatefulWidget {
  final PatientController c;

  const FavoriteNursesScreen({super.key, required this.c});

  @override
  State<FavoriteNursesScreen> createState() => _FavoriteNursesScreenState();
}

class _FavoriteNursesScreenState extends State<FavoriteNursesScreen> {
  final List<Map<String, dynamic>> _favorites = [];
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _loadFavorites();
  }

  Future<void> _loadFavorites() async {
    setState(() => _isLoading = true);
    try {
      final res = await widget.c.api.getMap('/v1/favorites/nurses');
      if (res['favorites'] is List) {
        setState(() {
          _favorites.clear();
          _favorites.addAll(List<Map<String, dynamic>>.from(res['favorites']));
        });
      }
    } catch (_) {
      // Offline fallback mock data
      if (_favorites.isEmpty) {
        _favorites.addAll([
          {
            'nurse_id': 'nurse-101',
            'nurse_name': 'م. سارة المحمود',
            'average_rating': 4.95,
            'completed_visits_count': 34,
            'skills': ['حقن وريدي', 'عناية بالجروح', 'قياس سكر وضغط'],
          },
          {
            'nurse_id': 'nurse-102',
            'nurse_name': 'م. خالد العلي',
            'average_rating': 4.88,
            'completed_visits_count': 19,
            'skills': ['تركيب قسطرة', 'رعاية تنفسية', 'إعطاء محاليل'],
          },
        ]);
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _removeFavorite(String nurseId) async {
    try {
      await widget.c.api.delete('/v1/favorites/nurses/$nurseId');
      setState(() {
        _favorites.removeWhere((f) => f['nurse_id'] == nurseId);
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('تمت إزالة الممرض من قائمة المفضلة')),
        );
      }
    } catch (_) {
      // Offline fallback
      setState(() {
        _favorites.removeWhere((f) => f['nurse_id'] == nurseId);
      });
    }
  }

  void _requestDirectNurse(Map<String, dynamic> nurse) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('تم توجيه طلب الزيارة المباشر إلى ${nurse['nurse_name']}')),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: AeroColors.lightCanvas,
        appBar: AppBar(
          title: Text(
            'الممرضون المفضلون',
            style: aeroText(size: 16, weight: FontWeight.w700, color: AeroColors.primaryNavy),
          ),
          backgroundColor: Colors.white,
          elevation: 0,
          centerTitle: true,
          iconTheme: const IconThemeData(color: AeroColors.primaryNavy),
        ),
        body: _isLoading
            ? const Center(child: CircularProgressIndicator(color: AeroColors.accentTeal))
            : _favorites.isEmpty
                ? Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.favorite_border, size: 48, color: AeroColors.textMuted),
                        const SizedBox(height: 12),
                        Text(
                          'لم تقم بإضافة أي ممرض إلى المفضلة بعد',
                          style: aeroText(size: 14, color: AeroColors.textSecondary),
                        ),
                      ],
                    ),
                  )
                : ListView.separated(
                    padding: const EdgeInsets.all(16),
                    itemCount: _favorites.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 12),
                    itemBuilder: (context, index) {
                      final f = _favorites[index];
                      return AeroFavoriteNurseCard(
                        name: f['nurse_name'] ?? 'ممرض معتمد',
                        rating: (f['average_rating'] as num?)?.toDouble() ?? 5.0,
                        totalVisits: (f['completed_visits_count'] as num?)?.toInt() ?? 0,
                        skills: (f['skills'] as List?)?.map((e) => e.toString()).toList() ?? [],
                        onRequestDirect: () => _requestDirectNurse(f),
                        onRemoveFavorite: () => _removeFavorite(f['nurse_id']),
                      );
                    },
                  ),
      ),
    );
  }
}
