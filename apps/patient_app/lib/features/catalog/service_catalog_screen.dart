import 'package:flutter/material.dart';
import 'package:tamreedy_core/tamreedy_core.dart';
import '../../app/patient_router.dart';
import '../../core/patient_session_coordinator.dart';
import 'catalog_store.dart';

class ServiceCatalogScreen extends StatefulWidget {
  final PatientSessionCoordinator session;

  const ServiceCatalogScreen({super.key, required this.session});

  @override
  State<ServiceCatalogScreen> createState() => _ServiceCatalogScreenState();
}

class _ServiceCatalogScreenState extends State<ServiceCatalogScreen> {
  late final TextEditingController _searchCtrl;

  @override
  void initState() {
    super.initState();
    _searchCtrl = TextEditingController(text: widget.session.catalog.searchQuery);
    widget.session.catalog.load();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tc = context.tamColors;
    final session = widget.session;

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: tc.background,
        appBar: AppBar(
          backgroundColor: tc.surface,
          elevation: 0,
          title: Text(
            'دليل الخدمات التمريضية',
            style: aeroText(size: 16, weight: FontWeight.w800, color: tc.textPrimary),
          ),
        ),
        body: ListenableBuilder(
          listenable: Listenable.merge([session.catalog, session.bookingDraft]),
          builder: (context, _) {
            final cats = session.catalog.categories;
            final list = session.catalog.filteredServices;
            final cartCount = session.bookingDraft.serviceQuantities.values
                .fold<int>(0, (sum, q) => sum + q);

            return Column(
              children: [
                Container(
                  color: tc.surface,
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                  child: Column(
                    children: [
                      TextField(
                        controller: _searchCtrl,
                        onChanged: session.catalog.setSearchQuery,
                        decoration: InputDecoration(
                          hintText: 'ابحث باسم الخدمة أو الوصف...',
                          prefixIcon: Icon(Icons.search_rounded, color: tc.primary),
                          suffixIcon: _searchCtrl.text.isEmpty
                              ? null
                              : IconButton(
                                  tooltip: 'مسح البحث',
                                  icon: const Icon(Icons.close_rounded),
                                  onPressed: () {
                                    _searchCtrl.clear();
                                    session.catalog.setSearchQuery('');
                                  },
                                ),
                          isDense: true,
                          filled: true,
                          fillColor: tc.background,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(14),
                            borderSide: BorderSide(color: tc.border),
                          ),
                        ),
                      ),
                      if (cats.isNotEmpty) ...[
                        const SizedBox(height: 10),
                        SizedBox(
                          height: 38,
                          child: ListView(
                            scrollDirection: Axis.horizontal,
                            children: [
                              ChoiceChip(
                                label: const Text('الكل'),
                                selected: session.catalog.selectedCategoryId == null,
                                onSelected: (_) => session.catalog.setCategory(null),
                              ),
                              const SizedBox(width: 8),
                              for (final cat in cats) ...[
                                ChoiceChip(
                                  label: Text(cat.titleAr),
                                  selected: session.catalog.selectedCategoryId == cat.id,
                                  onSelected: (_) => session.catalog.setCategory(
                                    session.catalog.selectedCategoryId == cat.id ? null : cat.id,
                                  ),
                                ),
                                const SizedBox(width: 8),
                              ],
                            ],
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                Expanded(
                  child: session.catalog.loading && list.isEmpty
                      ? const Padding(
                          padding: EdgeInsets.all(16),
                          child: Column(
                            children: [
                              TamSkeleton.card(height: 92),
                              SizedBox(height: 10),
                              TamSkeleton.card(height: 92),
                            ],
                          ),
                        )
                      : session.catalog.error != null && list.isEmpty
                          ? Center(
                              child: Padding(
                                padding: const EdgeInsets.all(16),
                                child: TamErrorState(
                                  title: 'تعذر تحميل الخدمات',
                                  message: session.catalog.error!,
                                  onRetry: () => session.catalog.load(forceRefresh: true),
                                ),
                              ),
                            )
                          : list.isEmpty
                              ? const Center(
                                  child: Padding(
                                    padding: EdgeInsets.all(16),
                                    child: TamEmptyState(
                                      icon: Icons.search_off_rounded,
                                      title: 'لا توجد نتائج مطابقة',
                                      message: 'جرّب كلمة بحث أخرى أو اختر تصنيف الكل.',
                                    ),
                                  ),
                                )
                              : ListView.builder(
                                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 96),
                                  itemCount: list.length,
                                  itemBuilder: (context, index) {
                                    final svc = list[index];
                                    final qty = session.bookingDraft.serviceQuantities[svc.id] ?? 0;
                                    return _CatalogServiceCard(
                                      svc: svc,
                                      quantity: qty,
                                      onChanged: (nextQty) =>
                                          session.bookingDraft.setServiceQuantity(svc, nextQty),
                                    );
                                  },
                                ),
                ),
                if (cartCount > 0)
                  SafeArea(
                    top: false,
                    child: Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: tc.surface,
                        border: Border(top: BorderSide(color: tc.border)),
                        boxShadow: tc.cardShadow,
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  '$cartCount خدمة محددة',
                                  style: aeroText(
                                    size: 13.5,
                                    weight: FontWeight.w800,
                                    color: tc.textPrimary,
                                  ),
                                ),
                                Text(
                                  session.bookingDraft.estimate != null
                                      ? 'التقديري ${formatMoney(session.bookingDraft.estimate!.expectedEstimate)}'
                                      : 'رسوم توصيل واحدة لجميع الخدمات',
                                  style: aeroText(size: 12, color: tc.primary, weight: FontWeight.w700),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 10),
                          ElevatedButton(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: tc.primary,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 13),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                            ),
                            onPressed: () {
                              Navigator.of(context).pop();
                              PatientRouter.openBookingWizard(context, session);
                            },
                            child: Text(
                              'متابعة الحجز',
                              style: aeroText(size: 14, weight: FontWeight.w800, color: Colors.white),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _CatalogServiceCard extends StatelessWidget {
  final PatientService svc;
  final int quantity;
  final ValueChanged<int> onChanged;

  const _CatalogServiceCard({
    required this.svc,
    required this.quantity,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final tc = context.tamColors;
    final selected = quantity > 0;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: selected ? tc.primaryTint.withValues(alpha: tc.isDark ? 0.25 : 0.45) : tc.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: selected ? tc.primary : tc.border,
          width: selected ? 1.5 : 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      svc.titleAr,
                      style: aeroText(size: 15, weight: FontWeight.w800, color: tc.textPrimary),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      svc.descriptionAr,
                      style: aeroText(size: 12.5, color: tc.textSecondary, height: 1.45),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(
                      formatMoney(svc.priceAmount),
                      style: aeroText(size: 14, weight: FontWeight.w800, color: tc.primary),
                    ),
                    Text(
                      '${svc.expectedMinutes} دقيقة',
                      style: aeroText(size: 12, color: tc.textSecondary),
                    ),
                    if (svc.requiresPrescription)
                      const TamStatusBadge(
                        labelOverride: 'وصفة طبية',
                        compact: true,
                      ),
                  ],
                ),
              ),
              if (quantity == 0)
                OutlinedButton.icon(
                  onPressed: () => onChanged(1),
                  icon: const Icon(Icons.add_rounded, size: 18),
                  label: const Text('إضافة'),
                )
              else
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      tooltip: 'تقليل',
                      onPressed: () => onChanged(quantity - 1),
                      icon: Icon(Icons.remove_circle_outline, color: tc.primary),
                    ),
                    Text(
                      '$quantity',
                      style: aeroText(size: 15, weight: FontWeight.w800, color: tc.textPrimary),
                    ),
                    IconButton(
                      tooltip: 'زيادة',
                      onPressed: quantity >= 10 ? null : () => onChanged(quantity + 1),
                      icon: Icon(Icons.add_circle_outline, color: tc.primary),
                    ),
                  ],
                ),
            ],
          ),
        ],
      ),
    );
  }
}
