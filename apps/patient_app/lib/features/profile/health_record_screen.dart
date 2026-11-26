import 'package:flutter/material.dart';
import 'package:tamreedy_core/tamreedy_core.dart';

class HealthRecordScreen extends StatefulWidget {
  final TamreedyApi api;

  const HealthRecordScreen({super.key, required this.api});

  @override
  State<HealthRecordScreen> createState() => _HealthRecordScreenState();
}

class _HealthRecordScreenState extends State<HealthRecordScreen> {
  final List<Map<String, dynamic>> _profiles = [];
  bool _loading = true;
  String? _error;
  String? _selectedId;

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
      final res = await widget.api.getMap('/v1/health-records/profiles');
      final list = res['profiles'];
      if (list is List) {
        _profiles
          ..clear()
          ..addAll(list.whereType<Map>().map((e) => Map<String, dynamic>.from(e)));
        if (_profiles.isNotEmpty) {
          _selectedId ??= '${_profiles.first['id'] ?? ''}';
        }
      }
    } catch (e) {
      _error = explainError(e, fallback: 'تعذر تحميل السجل الصحي من الخادم');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Map<String, dynamic>? get _activeProfile {
    if (_profiles.isEmpty) return null;
    for (final p in _profiles) {
      if ('${p['id']}' == _selectedId) return p;
    }
    return _profiles.first;
  }

  String _formatField(dynamic raw, {required String fallback}) {
    if (raw is List && raw.isNotEmpty) return raw.map((e) => '$e').join('، ');
    if (raw is String && raw.trim().isNotEmpty) return raw.trim();
    return fallback;
  }

  @override
  Widget build(BuildContext context) {
    final tc = context.tamColors;
    final active = _activeProfile;
    final bloodType = active?['blood_type'] ?? active?['bloodType'];
    final allergies = active?['allergies'];
    final chronic = active?['chronic_diseases'] ?? active?['chronicDiseases'];
    final medications = active?['medications'];
    final observations = active?['observations'] ?? active?['latestObservations'];

    return TamScaffold(
      title: 'السجل الصحي والتقارير',
      subtitle: 'البيانات السريرية والقياسات الحيوية الموثقة',
      showBack: true,
      onRefresh: _load,
      children: [
        if (_loading)
          const TamSkeleton.card(height: 150)
        else if (_error != null)
          TamErrorState(title: 'تعذر تحميل السجل الصحي', message: _error!, onRetry: _load)
        else if (_profiles.isEmpty)
          const TamEmptyState(
            icon: Icons.folder_shared_outlined,
            title: 'لا توجد ملفات صحية مسجلة',
            message: 'ستظهر بيانات الحساسية والأدوية والقياسات الحيوية هنا بمجرد توثيقها.',
          )
        else ...[
          SizedBox(
            height: 44,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: _profiles.length,
              separatorBuilder: (_, _) => const SizedBox(width: 8),
              itemBuilder: (context, idx) {
                final p = _profiles[idx];
                final id = '${p['id'] ?? ''}';
                return ChoiceChip(
                  label: Text('${p['full_name'] ?? p['fullName'] ?? 'مستفيد'}'),
                  selected: id == _selectedId,
                  onSelected: (_) => setState(() => _selectedId = id),
                );
              },
            ),
          ),
          const SizedBox(height: 12),
          TamCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('البيانات الطبية', style: aeroText(size: 15, weight: FontWeight.w800, color: tc.textPrimary)),
                const SizedBox(height: 10),
                KeyValueRow('فصيلة الدم', bloodType != null && '$bloodType'.isNotEmpty ? '$bloodType' : 'غير مسجلة'),
                KeyValueRow('الأمراض المزمنة', _formatField(chronic, fallback: 'لا توجد بيانات')),
                KeyValueRow('الحساسية', _formatField(allergies, fallback: 'لا توجد حساسية مسجلة')),
                KeyValueRow('الأدوية الحالية', _formatField(medications, fallback: 'لا توجد أدوية مسجلة')),
              ],
            ),
          ),
          const SectionTitle('القياسات الحيوية الأخيرة'),
          if (observations is List && observations.isNotEmpty)
            TamCard(
              child: Column(
                children: [
                  for (final o in observations.whereType<Map>())
                    KeyValueRow(
                      '${o['label'] ?? o['type'] ?? 'قياس'}',
                      '${o['value'] ?? '—'} ${o['unit'] ?? ''}'.trim(),
                    ),
                ],
              ),
            )
          else
            const TamEmptyState(
              icon: Icons.monitor_heart_outlined,
              title: 'لا توجد قياسات سريرية مسجلة',
              message: 'ستظهر قراءات الضغط والنبض والحرارة هنا فور تسجيلها من الممرض.',
            ),
        ],
      ],
    );
  }
}
