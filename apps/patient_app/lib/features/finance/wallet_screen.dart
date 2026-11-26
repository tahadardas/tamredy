import 'package:flutter/material.dart';
import 'package:tamreedy_core/tamreedy_core.dart';
import '../../core/patient_session_coordinator.dart';

class PatientWalletScreen extends StatefulWidget {
  final PatientSessionCoordinator session;

  const PatientWalletScreen({super.key, required this.session});

  @override
  State<PatientWalletScreen> createState() => _PatientWalletScreenState();
}

class _PatientWalletScreenState extends State<PatientWalletScreen> {
  @override
  void initState() {
    super.initState();
    widget.session.finance.loadWallet();
  }

  @override
  Widget build(BuildContext context) {
    final tc = context.tamColors;
    final finance = widget.session.finance;

    return TamScaffold(
      title: 'المحفظة وطرق الدفع',
      subtitle: 'الوضع المالي المعتمد في حسابك',
      showBack: true,
      onRefresh: finance.loadWallet,
      children: [
        ListenableBuilder(
          listenable: finance,
          builder: (context, _) {
            if (finance.loadingWallet && finance.walletStatus == null) {
              return const Column(
                children: [
                  TamSkeleton.card(height: 120),
                  SizedBox(height: 10),
                  TamSkeleton.card(height: 80),
                ],
              );
            }
            if (finance.walletError != null && finance.walletStatus == null) {
              return TamErrorState(
                title: 'تعذر عرض حالة المحفظة',
                message: finance.walletError!,
                onRetry: finance.loadWallet,
              );
            }

            final mode = '${finance.walletStatus?['mode'] ?? 'DISABLED'}';
            final reason = '${finance.walletStatus?['reason'] ?? ''}';
            final isDisabled = mode == 'DISABLED';

            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TamCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      TamStatusBadge(
                        labelOverride: isDisabled ? 'الدفع النقدي مفعّل' : 'المحفظة مفعّلة',
                        iconOverride: Icons.payments_outlined,
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'طريقة التسوية المعتمدة',
                        style: aeroText(size: 15.5, weight: FontWeight.w800, color: tc.textPrimary),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        reason == 'LICENSED_PAYMENT_PROVIDER_REQUIRED' || isDisabled
                            ? 'الشحن والدفع الإلكتروني عبر المحفظة غير مفعل حالياً بانتظار ربط مزود دفع مرخص. تتم جميع التسويات نقداً للممرض عند إكمال الزيارة مع إيصال فاتورة رقمي فوري.'
                            : 'يمكنك استخدام رصيد المحفظة أو الدفع النقدي المباشر للممرض.',
                        style: aeroText(size: 13, color: tc.textSecondary, height: 1.55),
                      ),
                    ],
                  ),
                ),
                const NoticeBox('لا تتوفر عمليات شحن أو سحب رصيد داخل التطبيق في الإصدار الحالي.'),
              ],
            );
          },
        ),
      ],
    );
  }
}
