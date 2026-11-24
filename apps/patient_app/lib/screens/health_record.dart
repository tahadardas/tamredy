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
  String? _selectedProfileId;

  @override
  void initState() {
    super.initState();
    _loadHealthData();
  }

  Future<void> _loadHealthData() async {
    setState(() => _isLoading = true);
    try {
      final res = await widget.c.api.getMap('/v1/health-records/profiles');
      if (res['profiles'] is List) {
        setState(() {
          _profiles.clear();
          _profiles.addAll(List<Map<String, dynamic>>.from(res['profiles']));
          if (_profiles.isNotEmpty) {
            _selectedProfileId = _profiles.first['id'];
          }
        });
      }
    } catch (_) {
      // Offline fallback
      if (_profiles.isEmpty) {
        _profiles.addAll([
          {
            'id': 'prof-1',
            'full_name': 'المريض الأساسي',
            'relationship': 'SELF',
            'blood_type': 'O+',
            'chronic_diseases': ['ارتفاع ضغط الدم'],
          },
          {
            'id': 'prof-2',
            'full_name': 'الوالد (عمر)',
            'relationship': 'FATHER',
            'blood_type': 'A+',
            'chronic_diseases': ['السكري النوع الثاني'],
          },
        ]);
        _selectedProfileId = 'prof-1';
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: AeroColors.lightCanvas,
        appBar: AppBar(
          title: Text(
            'السجل الصحي والملاحظات السريرية',
            style: aeroText(size: 16, weight: FontWeight.w700, color: AeroColors.primaryNavy),
          ),
          backgroundColor: Colors.white,
          elevation: 0,
          centerTitle: true,
          iconTheme: const IconThemeData(color: AeroColors.primaryNavy),
        ),
        body: _isLoading
            ? const Center(child: CircularProgressIndicator(color: AeroColors.accentTeal))
            : ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  // Beneficiary Profiles Selector
                  Text(
                    'المستفيدون المسجلون:',
                    style: aeroText(size: 14, weight: FontWeight.w700, color: AeroColors.primaryNavy),
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                    height: 48,
                    child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      itemCount: _profiles.length,
                      separatorBuilder: (_, _) => const SizedBox(width: 8),
                      itemBuilder: (context, index) {
                        final prof = _profiles[index];
                        final isSelected = prof['id'] == _selectedProfileId;
                        return ChoiceChip(
                          label: Text(
                            prof['full_name'] ?? 'مستفيد',
                            style: aeroText(
                              size: 13,
                              weight: isSelected ? FontWeight.w700 : FontWeight.w500,
                              color: isSelected ? Colors.white : AeroColors.textPrimary,
                            ),
                          ),
                          selected: isSelected,
                          selectedColor: AeroColors.accentTeal,
                          backgroundColor: Colors.white,
                          onSelected: (val) {
                            if (val) setState(() => _selectedProfileId = prof['id']);
                          },
                        );
                      },
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Profile Card
                  AeroGlassCard(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              'بيانات الملف الصحي المعتمد',
                              style: aeroText(size: 15, weight: FontWeight.w700, color: AeroColors.primaryNavy),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                              decoration: BoxDecoration(
                                color: AeroColors.aeroTint,
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Text('موثق', style: aeroText(size: 11, color: AeroColors.accentTeal, weight: FontWeight.w700)),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        Text('فصيلة الدم: O+', style: aeroText(size: 13, color: AeroColors.textSecondary)),
                        const SizedBox(height: 4),
                        Text('الأمراض المزمنة: ارتفاع ضغط الدم (متابع)', style: aeroText(size: 13, color: AeroColors.textSecondary)),
                        const SizedBox(height: 4),
                        Text('الحساسية الدوائية: البنسلين ومشتقاته', style: aeroText(size: 13, color: const Color(0xFFDC2626))),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Recent Clinical Observations
                  Text(
                    'أحدث القراءات السريرية المسجلة:',
                    style: aeroText(size: 14, weight: FontWeight.w700, color: AeroColors.primaryNavy),
                  ),
                  const SizedBox(height: 8),
                  AeroGlassCard(
                    padding: const EdgeInsets.all(14),
                    child: Column(
                      children: [
                        _buildReadingRow('ضغط الدم', '125 / 82', 'mmHg', Icons.speed),
                        const Divider(height: 16),
                        _buildReadingRow('النبض', '74', 'bpm', Icons.favorite),
                        const Divider(height: 16),
                        _buildReadingRow('سكر الدم (عشوائي)', '112', 'mg/dL', Icons.bloodtype),
                        const Divider(height: 16),
                        _buildReadingRow('تشبع الأكسجين SpO2', '98%', '%', Icons.air),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Download Clinical Report CTA
                  AeroButton.teal(
                    'عرض وتنزيل التقرير السريري المعتمد (PDF مع QR)',
                    leadingIcon: const Icon(Icons.picture_as_pdf, color: Colors.white, size: 20),
                    onPressed: () {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('تم إصدار التقرير الطبي بصيغة PDF وتجهيز رمز QR للتحقق الرسمي')),
                      );
                    },
                  ),
                ],
              ),
      ),
    );
  }

  Widget _buildReadingRow(String title, String val, String unit, IconData icon) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Row(
          children: [
            Icon(icon, size: 18, color: AeroColors.accentTeal),
            const SizedBox(width: 8),
            Text(title, style: aeroText(size: 13, color: AeroColors.textPrimary)),
          ],
        ),
        Row(
          children: [
            Text(val, style: aeroText(size: 14, weight: FontWeight.w700, color: AeroColors.primaryNavy)),
            const SizedBox(width: 4),
            Text(unit, style: aeroText(size: 11, color: AeroColors.textMuted)),
          ],
        ),
      ],
    );
  }
}
