import 'package:flutter/material.dart';
import 'package:tamreedy_core/tamreedy_core.dart';
import '../controller.dart';
import '../main.dart';
import 'home.dart';

/// Normalizes Arabic text for tolerant search (Alef, Teh Marbuta, Alef Maksura, diacritics).
String normalizeArabicSearch(String input) {
  var s = input.trim().toLowerCase();
  s = s.replaceAll(RegExp(r'[\u064B-\u065F\u0670\u0640]'), '');
  s = s
      .replaceAll('أ', 'ا')
      .replaceAll('إ', 'ا')
      .replaceAll('آ', 'ا')
      .replaceAll('ى', 'ي')
      .replaceAll('ة', 'ه');
  return s;
}

String serviceCategoryLabel(ServiceItem s) {
  final code = s.code.toUpperCase();
  if (code.contains('INJ') || code.contains('MED') || code.contains('VACC')) {
    return 'الحقن والأدوية';
  }
  if (code.contains('WOUND') || code.contains('DRESS') || code.contains('SUTURE')) {
    return 'العناية بالجروح';
  }
  if (code.contains('VITAL') || code.contains('MONITOR') || code.contains('PRESSURE')) {
    return 'القياسات الحيوية';
  }
  if (code.contains('CATH') || code.contains('PROC')) {
    return 'القساطر والإجراءات';
  }
  if (code.contains('ELDER') || code.contains('HOME') || code.contains('CARE')) {
    return 'الرعاية المنزلية';
  }
  return switch (s.iconCode) {
    0 => 'الحقن والأدوية',
    1 => 'العناية بالجروح',
    2 => 'القياسات الحيوية',
    _ => 'الرعاية المنزلية',
  };
}

IconData serviceCategoryIcon(int iconCode) => switch (iconCode) {
  0 => Icons.vaccines_outlined,
  1 => Icons.healing_outlined,
  2 => Icons.monitor_heart_outlined,
  _ => Icons.elderly_outlined,
};

Tone serviceCategoryTone(int iconCode) => switch (iconCode) {
  0 => Tone.teal,
  1 => Tone.blue,
  2 => Tone.teal,
  _ => Tone.orange,
};

/// Full Service Catalog + Multi-Service Cart inside the booking journey.
class ServiceCatalogScreen extends StatefulWidget {
  final PatientController c;
  const ServiceCatalogScreen({super.key, required this.c});

  @override
  State<ServiceCatalogScreen> createState() => _ServiceCatalogScreenState();
}

class _ServiceCatalogScreenState extends State<ServiceCatalogScreen> {
  final _search = TextEditingController();
  String _query = '';
  String _selectedCategory = 'الكل';

  PatientController get c => widget.c;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: c,
      builder: (context, _) {
        final tc = context.tamColors;
        final categories = <String>{
          'الكل',
          for (final s in c.services) serviceCategoryLabel(s),
        }.toList();

        final qNorm = normalizeArabicSearch(_query);
        final filtered = c.services.where((s) {
          final catMatch = _selectedCategory == 'الكل' ||
              serviceCategoryLabel(s) == _selectedCategory;
          if (!catMatch) return false;
          if (qNorm.isEmpty) return true;
          return normalizeArabicSearch(s.title).contains(qNorm) ||
              normalizeArabicSearch(s.note).contains(qNorm) ||
              normalizeArabicSearch(serviceCategoryLabel(s)).contains(qNorm);
        }).toList();

        final cartCount = c.selectedServiceQuantities.values.fold<int>(0, (a, b) => a + b);
        var cartTotal = 0;
        var cartMinutes = 0;
        var anyPrescription = false;
        for (final entry in c.selectedServiceQuantities.entries) {
          final item = c.services.where((s) => s.id == entry.key).firstOrNull;
          if (item != null) {
            cartTotal += item.price * entry.value;
            cartMinutes += item.expectedMinutes * entry.value;
            if (item.requiresPrescription) anyPrescription = true;
          }
        }

        return Scaffold(
          backgroundColor: tc.background,
          bottomNavigationBar: cartCount > 0
              ? _CartBottomBar(
                  count: cartCount,
                  minutes: cartMinutes,
                  totalPrice: cartTotal,
                  hasPrescription: anyPrescription,
                  onContinue: () {
                    if (c.service == null && c.selectedServiceQuantities.isNotEmpty) {
                      final firstId = c.selectedServiceQuantities.keys.first;
                      c.service = c.services.where((s) => s.id == firstId).firstOrNull;
                    }
                    Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => ServiceScreen(c: c)),
                    );
                  },
                )
              : patientNavBar(context, c, 0),
          body: SafeArea(
            child: Column(
              children: [
                Container(
                  decoration: BoxDecoration(
                    color: tc.surface,
                    border: Border(bottom: BorderSide(color: tc.border)),
                  ),
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  child: Row(
                    children: [
                      TamIconButton(
                        icon: Icons.arrow_back_rounded,
                        tooltip: 'رجوع',
                        onPressed: () => Navigator.of(context).maybePop(),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'كتالوج الخدمات التمريضية',
                              style: TamTypography.sectionTitle(color: tc.textPrimary),
                            ),
                            Text(
                              'اختر خدمة أو أكثر وحدد الكمية المناسبة',
                              style: TamTypography.supporting(color: tc.textSecondary),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                    children: [
                      TamSearchField(
                        controller: _search,
                        hint: 'ابحث باسم الخدمة أو الوصف...',
                        onChanged: (v) => setState(() => _query = v),
                      ),
                      const SizedBox(height: 8),
                      SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(
                          children: [
                            for (var i = 0; i < categories.length; i++) ...[
                              if (i > 0) const SizedBox(width: 8),
                              ChoiceChip(
                                label: Text(categories[i]),
                                selected: categories[i] == _selectedCategory,
                                onSelected: (_) =>
                                    setState(() => _selectedCategory = categories[i]),
                                selectedColor: tc.primaryTint,
                                labelStyle: aeroText(
                                  size: 13,
                                  weight: categories[i] == _selectedCategory
                                      ? FontWeight.w700
                                      : FontWeight.w500,
                                  color: categories[i] == _selectedCategory
                                      ? tc.primaryDark
                                      : tc.textSecondary,
                                ),
                                side: BorderSide(
                                  color: categories[i] == _selectedCategory
                                      ? tc.primary
                                      : tc.border,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                      const SizedBox(height: 12),
                      if (filtered.isEmpty)
                        TamEmptyState(
                          icon: Icons.search_off_rounded,
                          title: 'لا توجد خدمات مطابقة',
                          message: 'جرّب تعديل كلمة البحث أو اختيار تصنيف آخر.',
                          actionLabel: 'عرض كل الخدمات',
                          onAction: () {
                            _search.clear();
                            setState(() {
                              _query = '';
                              _selectedCategory = 'الكل';
                            });
                          },
                        )
                      else
                        for (final s in filtered)
                          _CatalogServiceCard(
                            service: s,
                            quantity: c.selectedServiceQuantities[s.id] ?? 0,
                            onOpenDetails: () {
                              if ((c.selectedServiceQuantities[s.id] ?? 0) == 0) {
                                c.setServiceQuantity(s, 1);
                              }
                              c.service = s;
                              Navigator.of(context).push(
                                MaterialPageRoute(builder: (_) => ServiceScreen(c: c)),
                              );
                            },
                            onQuantityChanged: (next) {
                              c.setServiceQuantity(s, next);
                            },
                          ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _CatalogServiceCard extends StatelessWidget {
  final ServiceItem service;
  final int quantity;
  final VoidCallback onOpenDetails;
  final ValueChanged<int> onQuantityChanged;

  const _CatalogServiceCard({
    required this.service,
    required this.quantity,
    required this.onOpenDetails,
    required this.onQuantityChanged,
  });

  @override
  Widget build(BuildContext context) {
    final tc = context.tamColors;
    final selected = quantity > 0;
    return TamCard(
      onTap: onOpenDetails,
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              IconBox(
                serviceCategoryIcon(service.iconCode),
                tone: serviceCategoryTone(service.iconCode),
                size: 46,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      service.title,
                      style: TamTypography.cardTitle(color: tc.textPrimary),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      service.note,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TamTypography.supporting(color: tc.textSecondary),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: [
              TamStatusBadge(
                labelOverride: 'من ${formatMoney(service.price)}',
                iconOverride: Icons.payments_outlined,
                compact: true,
              ),
              TamStatusBadge(
                labelOverride: '${service.expectedMinutes} دقيقة',
                iconOverride: Icons.schedule_outlined,
                compact: true,
              ),
              if (service.requiresPrescription)
                const TamStatusBadge(
                  labelOverride: 'يتطلب وصفة طبية',
                  iconOverride: Icons.medical_information_outlined,
                  compact: true,
                ),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 8,
            runSpacing: 8,
            children: [
              TextButton(
                onPressed: onOpenDetails,
                child: Text(
                  'تفاصيل الخدمة',
                  style: aeroText(
                    size: 13.5,
                    weight: FontWeight.w700,
                    color: tc.primary,
                  ),
                ),
              ),
              if (!selected)
                SizedBox(
                  height: 48,
                  child: FilledButton.icon(
                    onPressed: () => onQuantityChanged(1),
                    style: FilledButton.styleFrom(
                      backgroundColor: tc.primary,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    icon: const Icon(Icons.add_rounded, size: 18),
                    label: const Text('إضافة للسلة'),
                  ),
                )
              else
                Container(
                  decoration: BoxDecoration(
                    color: tc.primaryTint.withValues(alpha: tc.isDark ? 0.35 : 0.7),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: tc.primary),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        tooltip: 'إنقاص الكمية',
                        onPressed: () => onQuantityChanged(quantity - 1),
                        icon: Icon(
                          quantity == 1 ? Icons.delete_outline_rounded : Icons.remove_rounded,
                          color: quantity == 1 ? tc.danger : tc.primaryDark,
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 6),
                        child: Text(
                          '$quantity',
                          style: aeroText(
                            size: 15,
                            weight: FontWeight.w800,
                            color: tc.primaryDark,
                          ),
                        ),
                      ),
                      IconButton(
                        tooltip: 'زيادة الكمية',
                        onPressed: () => onQuantityChanged(quantity + 1),
                        icon: Icon(Icons.add_rounded, color: tc.primaryDark),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _CartBottomBar extends StatelessWidget {
  final int count;
  final int minutes;
  final int totalPrice;
  final bool hasPrescription;
  final VoidCallback onContinue;

  const _CartBottomBar({
    required this.count,
    required this.minutes,
    required this.totalPrice,
    required this.hasPrescription,
    required this.onContinue,
  });

  @override
  Widget build(BuildContext context) {
    final tc = context.tamColors;
    return Container(
      decoration: BoxDecoration(
        color: tc.surface,
        border: Border(top: BorderSide(color: tc.border)),
        boxShadow: tc.elevatedShadow,
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '$count خدمة • نحو $minutes دقيقة',
                      style: TamTypography.supporting(
                        color: tc.textSecondary,
                        weight: FontWeight.w700,
                      ),
                    ),
                    Text(
                      'التقدير: ${formatMoney(totalPrice)}',
                      style: TamTypography.cardTitle(color: tc.primary),
                    ),
                    if (hasPrescription)
                      Text(
                        'يشمل خدمة تتطلب وصفة طبية',
                        style: aeroText(size: 11, color: tc.warning, weight: FontWeight.w600),
                      ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              AeroButton.teal(
                'متابعة الحجز',
                width: 148,
                height: 50,
                fontSize: 14.5,
                onPressed: onContinue,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
