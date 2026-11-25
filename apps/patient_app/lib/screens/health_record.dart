import 'package:flutter/material.dart';
import 'package:tamreedy_core/tamreedy_core.dart';
import '../controller.dart';

class HealthRecordScreen extends StatefulWidget {
  final PatientController c;

  const HealthRecordScreen({super.key, required this.c});

  @override
  State<HealthRecordScreen> createState() => _HealthRecordScreenState();
}

class _HealthRecordScreenState extends State<HealthRecordScreen> {
  final List<Map<String, dynamic>> _profiles = [];
  bool _isLoading = false;
  String? _error;
  String? _selectedProfileId;

  @override
  void initState() {
    super.initState();
    _loadHealthData();
  }

  Future<void> _loadHealthData() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final res = await widget.c.api.getMap('/v1/health-records/profiles');
      final list = res['profiles'];
      if (list is List) {
        _profiles
          ..clear()
          ..addAll(
            list
                .whereType<Map>()
                .map((e) => Map<String, dynamic>.from(e)),
          );
        if (_profiles.isNotEmpty) {
          _selectedProfileId ??= '${_profiles.first['id'] ?? ''}';
        }
      }
    } catch (e) {
      _error = 'تعذر تحميل الملف الصحي من الخادم حالياً.';
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Map<String, dynamic>? get _activeProfile {
    if (_profiles.isEmpty) return null;
    for (final p in _profiles) {
      if ('${p['id']}' == _selectedProfileId) return p;
    }
    return _profiles.first;
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
      title: 'السجل الصحي',
      subtitle: 'البيانات الطبية والقياسات المعتمدة للمستفيد',
      showBack: true,
      onRefresh: _loadHealthData,
      children: [
        if (_isLoading) ...[
          const TamSkeleton.card(height: 120),
          const SizedBox(height: TamSpacing.md),
          const TamSkeleton.card(height: 140),
        ] else if (_error != null) ...[
          TamErrorState(
            title: 'تعذر تحميل السجل الصحي',
            message: _error!,
            onRetry: _loadHealthData,
          ),
        ] else if (_profiles.isEmpty) ...[
          const TamEmptyState(
            icon: Icons.folder_shared_outlined,
            title: 'لا توجد ملفات صحية مسجلة',
            message:
                'سيظهر ملفك الصحي والقياسات السريرية هنا بعد توثيقها من قبل الممرض أو إضافتها في ملف المستفيد.',
          ),
        ] else ...[
          const SectionTitle('المستفيدون المسجلون'),
          SizedBox(
            height: 48,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: _profiles.length,
              separatorBuilder: (_, _) => const SizedBox(width: 8),
              itemBuilder: (context, index) {
                final prof = _profiles[index];
                final id = '${prof['id'] ?? ''}';
                final isSelected = id == _selectedProfileId;
                return ChoiceChip(
                  label: Text(
                    '${prof['full_name'] ?? prof['fullName'] ?? 'مستفيد'}',
                    style: aeroText(
                      size: 13,
                      weight: isSelected ? FontWeight.w700 : FontWeight.w500,
                      color: isSelected ? Colors.white : tc.textPrimary,
                    ),
                  ),
                  selected: isSelected,
                  selectedColor: tc.primary,
                  backgroundColor: tc.surface,
                  side: BorderSide(color: isSelected ? tc.primary : tc.border),
                  onSelected: (val) {
                    if (val) setState(() => _selectedProfileId = id);
                  },
                );
              },
            ),
          ),
          const SizedBox(height: TamSpacing.lg),
          TamCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'البيانات الطبية الأساسية',
                        style: aeroText(
                          size: 15,
                          weight: FontWeight.w800,
                          color: tc.textPrimary,
                        ),
                      ),
                    ),
                    const TamStatusBadge(
                      labelOverride: 'خصوصية محمية',
                      iconOverride: Icons.verified_user_outlined,
                      compact: true,
                    ),
                  ],
                ),
                const SizedBox(height: TamSpacing.md),
                KeyValueRow(
                  'فصيلة الدم',
                  bloodType != null && '$bloodType'.isNotEmpty
                      ? '$bloodType'
                      : 'غير مسجلة',
                ),
                KeyValueRow(
                  'الأمراض المزمنة',
                  _formatListOrText(chronic, fallback: 'لا توجد بيانات مسجلة'),
                ),
                KeyValueRow(
                  'الحساسية',
                  _formatListOrText(allergies, fallback: 'لا توجد حساسية مسجلة'),
                ),
                KeyValueRow(
                  'الأدوية الحالية',
                  _formatListOrText(medications, fallback: 'لا توجد أدوية مسجلة'),
                ),
              ],
            ),
          ),
          const SectionTitle('أحدث القياسات الحيوية'),
          if (observations is List && observations.isNotEmpty)
            TamCard(
              child: Column(
                children: [
                  for (var i = 0; i < observations.length; i++)
                    if (observations[i] is Map)
                      KeyValueRow(
                        '${observations[i]['label'] ?? observations[i]['type'] ?? 'قياس'}',
                        '${observations[i]['value'] ?? '—'} ${observations[i]['unit'] ?? ''}'
                            .trim(),
                      ),
                ],
              ),
            )
          else
            const TamEmptyState(
              icon: Icons.monitor_heart_outlined,
              title: 'لا توجد قياسات سريرية مسجلة',
              message:
                  'ستظهر قراءات الضغط والنبض والسكر هنا فور تسجيلها خلال الزيارات المنزلية.',
            ),
        ],
      ],
    );
  }

  String _formatListOrText(dynamic raw, {required String fallback}) {
    if (raw is List && raw.isNotEmpty) {
      return raw.map((e) => '$e').join('، ');
    }
    if (raw is String && raw.trim().isNotEmpty) return raw.trim();
    return fallback;
  }
}
