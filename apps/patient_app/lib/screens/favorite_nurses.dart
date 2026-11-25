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
      final raw = await widget.c.api.getList('/v1/favorites/nurses');
      setState(() {
        _favorites
          ..clear()
          ..addAll(raw.map((e) => Map<String, dynamic>.from(e as Map)));
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(explainError(e, fallback: 'تعذر تحميل الممرضين المفضلين'))),
        );
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
                      final offered = (f['offered_services'] as List?) ?? const [];
                      final skills = offered.isNotEmpty
                          ? offered
                                .map((e) => (e is Map ? (e['titleAr'] ?? e['code']) : e).toString())
                                .toList()
                          : (f['skills'] as List?)?.map((e) => e.toString()).toList() ?? [];
                      return AeroFavoriteNurseCard(
                        name: f['nurse_name']?.toString() ?? 'ممرض معتمد',
                        rating: double.tryParse('${f['rating'] ?? f['average_rating'] ?? 5.0}') ?? 5.0,
                        totalVisits: int.tryParse('${f['review_count'] ?? f['completed_visits_count'] ?? 0}') ?? 0,
                        skills: skills,
                        onRequestDirect: () => _requestDirectNurse(f),
                        onRemoveFavorite: () => _removeFavorite(f['nurse_id'].toString()),
                      );
                    },
                  ),
      ),
    );
  }
}
