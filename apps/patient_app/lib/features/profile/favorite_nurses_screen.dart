import 'package:flutter/material.dart';
import 'package:tamreedy_core/tamreedy_core.dart';

class FavoriteNursesScreen extends StatefulWidget {
  final TamreedyApi api;

  const FavoriteNursesScreen({super.key, required this.api});

  @override
  State<FavoriteNursesScreen> createState() => _FavoriteNursesScreenState();
}

class _FavoriteNursesScreenState extends State<FavoriteNursesScreen> {
  final List<Map<String, dynamic>> _favorites = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    if (kDemoMode) {
      _loading = false;
      return;
    }
    try {
      final raw = await widget.api.getList('/v1/favorites/nurses');
      _favorites
        ..clear()
        ..addAll(raw.whereType<Map>().map((e) => Map<String, dynamic>.from(e)));
    } catch (e) {
      _error = explainError(e, fallback: 'تعذر تحميل الممرضين المفضلين');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _remove(String nurseId) async {
    try {
      await widget.api.delete('/v1/favorites/nurses/$nurseId');
      setState(() => _favorites.removeWhere((f) => f['nurse_id'] == nurseId));
      if (mounted) TamToast.show(context, 'تمت الإزالة من المفضلة', tone: TamToastTone.success);
    } catch (e) {
      if (mounted) TamToast.show(context, explainError(e), tone: TamToastTone.error);
    }
  }

  @override
  Widget build(BuildContext context) {
    final tc = context.tamColors;
    return TamScaffold(
      title: 'الممرضون المفضلون',
      subtitle: 'الكوادر التي قمت بتفضيلها بعد الزيارات',
      showBack: true,
      onRefresh: _load,
      children: [
        if (_loading)
          const TamSkeleton.card(height: 110)
        else if (_error != null)
          TamErrorState(title: 'تعذر تحميل القائمة', message: _error!, onRetry: _load)
        else if (_favorites.isEmpty)
          const TamEmptyState(
            icon: Icons.favorite_border_rounded,
            title: 'القائمة فارغة حالياً',
            message: 'يمكنك حفظ الممرضين المميزين من تفاصيل الزيارات المكتملة.',
          )
        else
          for (final f in _favorites)
            TamCard(
              child: ListTile(
                contentPadding: EdgeInsets.zero,
                leading: CircleAvatar(
                  backgroundColor: tc.primaryTint,
                  child: Icon(Icons.medical_services_outlined, color: tc.primary),
                ),
                title: Text('${f['nurse_name'] ?? 'ممرض معتمد'}',
                    style: aeroText(size: 15, weight: FontWeight.w800)),
                subtitle: Text('ممرض معتمد في تمريضي',
                    style: aeroText(size: 12.5, color: tc.textSecondary)),
                trailing: IconButton(
                  tooltip: 'إزالة',
                  icon: Icon(Icons.favorite_rounded, color: tc.danger),
                  onPressed: () => _remove('${f['nurse_id'] ?? ''}'),
                ),
              ),
            ),
      ],
    );
  }
}
