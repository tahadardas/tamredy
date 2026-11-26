import 'package:flutter/material.dart';
import 'package:tamreedy_core/tamreedy_core.dart';
import '../../core/nurse_session_coordinator.dart';
import '../../features/visit/visit_store.dart';

Future<void> openGuardianSheet(
  BuildContext context,
  NurseSessionCoordinator session,
) async {
  final guardian = session.guardian;
  guardian.refreshSession();
  guardian.refreshSos();
  guardian.location.sync();

  await showModalBottomSheet<void>(
    context: context,
    useSafeArea: true,
    isScrollControlled: true,
    builder: (_) => _GuardianSheetBody(session: session),
  );
}

class _GuardianSheetBody extends StatelessWidget {
  final NurseSessionCoordinator session;

  const _GuardianSheetBody({required this.session});

  static const _responses = {
    'OK': 'أنا بخير',
    'MORE_TIME': 'أحتاج وقتاً إضافياً',
    'HELP': 'أحتاج مساعدة',
    'SAFE_EXIT': 'أطلب الخروج الآمن',
  };

  @override
  Widget build(BuildContext context) {
    final safety = session.guardian;
    final visit = session.visit;

    return ListenableBuilder(
      listenable: Listenable.merge([visit, safety, safety.location]),
      builder: (context, _) {
        final onVisit = visit.phase == NurseVisitPhase.assigned ||
            visit.phase == NurseVisitPhase.enRoute ||
            visit.phase == NurseVisitPhase.arrived ||
            visit.phase == NurseVisitPhase.inService;

        return Container(
          color: context.tamColors.surface,
          child: SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const SectionTitle('مركز الأمان والاستغاثة Guardian'),
                  if (safety.event == null || safety.eventClosed)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: TamEmergencyCard(
                        title: 'استغاثة فورية صامتة (SOS)',
                        subtitle: 'تنبيه عاجل لغرفة العمليات وجهات الاتصال الموثوقة فوراً',
                        actionLabel: safety.sendingSos ? 'جارٍ الإرسال...' : 'إرسال SOS',
                        onAction: safety.sendingSos ? () {} : safety.sendSos,
                      ),
                    ),
                  if (safety.event?['state'] != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: StatusChip('حالة بلاغ SOS: ${safety.event!['state']}'),
                    ),
                  OutlinedButton.icon(
                    onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => TrustedContactsScreen(api: session.api),
                      ),
                    ),
                    icon: const Icon(Icons.contact_phone_outlined),
                    label: const Text('جهات الاتصال الموثوقة'),
                  ),
                  OutlinedButton.icon(
                    onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => EmergencyDirectoryScreen(api: session.api),
                      ),
                    ),
                    icon: const Icon(Icons.phone_outlined),
                    label: const Text('دليل أرقام الطوارئ'),
                  ),
                  const SizedBox(height: 10),
                  _NightPreferenceTile(api: session.api),
                  _VisitCompanionsTile(api: session.api),
                  const SizedBox(height: 12),
                  if (visit.assignmentId != null && onVisit)
                    AeroButton.danger(
                      'إنهاء المهمة فوراً لأسباب السلامة',
                      onPressed: safety.busy
                          ? null
                          : () async {
                              final ok = await showDialog<bool>(
                                context: context,
                                builder: (ctx) => AlertDialog(
                                  title: const Text('تأكيد الخروج الآمن'),
                                  content: const Text(
                                    'سيتم إغلاق الزيارة وتسجيل بلاغ سلامة فوري للفريق المناوب.',
                                  ),
                                  actions: [
                                    TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('رجوع')),
                                    TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('تأكيد الخروج الآمن')),
                                  ],
                                ),
                              );
                              if (ok == true) {
                                await visit.safeAbort(safety);
                              }
                            },
                    ),
                  if (safety.sessionId != null) ...[
                    const SizedBox(height: 8),
                    const StatusChip('جلسة السلامة مفتوحة'),
                    if (safety.checkin?['status'] == 'SENT' || safety.checkin?['status'] == 'MISSED')
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          for (final e in _responses.entries)
                            OutlinedButton(
                              onPressed: safety.busy ? null : () => safety.respond(e.key),
                              child: Text(e.value),
                            ),
                        ],
                      ),
                    const SizedBox(height: 8),
                    if (!safety.location.capturing)
                      OutlinedButton(
                        onPressed: safety.location.starting ? null : safety.startLocation,
                        child: const Text('تفعيل مشاركة موقع السلامة'),
                      ),
                    OutlinedButton(
                      onPressed: safety.busy ? null : safety.checkout,
                      child: const Text('إنهاء جلسة السلامة'),
                    ),
                  ] else if (onVisit && visit.assignmentId != null)
                    OutlinedButton(
                      onPressed: safety.busy ? null : () => safety.start(visit.assignmentId!),
                      child: const Text('تفعيل جلسة السلامة لهذه الزيارة'),
                    ),
                  if (safety.error != null) NoticeBox(safety.error!),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _NightPreferenceTile extends StatefulWidget {
  final TamreedyApi api;
  const _NightPreferenceTile({required this.api});

  @override
  State<_NightPreferenceTile> createState() => _NightPreferenceTileState();
}

class _NightPreferenceTileState extends State<_NightPreferenceTile> {
  static const _path = '/v1/nurse/safety/night-preference';
  bool _enabled = false;
  bool _optedIn = false;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load([bool? next]) async {
    setState(() => _busy = true);
    try {
      final res = next == null
          ? await widget.api.getMap(_path)
          : await widget.api.put(_path, {'optedIn': next});
      if (mounted) {
        setState(() {
          _enabled = res['enabled'] == true;
          _optedIn = res['optedIn'] == true;
        });
      }
    } catch (_) {}
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    if (!_enabled) return const SizedBox.shrink();
    return SwitchListTile.adaptive(
      contentPadding: EdgeInsets.zero,
      title: const Text('استقبال عروض العمل الليلي'),
      subtitle: const Text('وفق ضوابط الأهلية والسلامة الليلية'),
      value: _optedIn,
      onChanged: _busy ? null : (v) => _load(v),
    );
  }
}

class _VisitCompanionsTile extends StatefulWidget {
  final TamreedyApi api;
  const _VisitCompanionsTile({required this.api});

  @override
  State<_VisitCompanionsTile> createState() => _VisitCompanionsTileState();
}

class _VisitCompanionsTileState extends State<_VisitCompanionsTile> {
  static const _path = '/v1/nurse/safety/companions';
  List<Map<String, dynamic>> _pending = [];
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load([Map<String, dynamic>? confirm]) async {
    setState(() => _busy = true);
    try {
      if (confirm != null) {
        await widget.api.post('$_path/${confirm['request_id']}/confirm', {
          'nurseId': confirm['nurse_id'],
        });
      }
      final res = await widget.api.getList(_path);
      if (mounted) {
        setState(() {
          _pending = res.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
        });
      }
    } catch (_) {}
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    if (_pending.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SectionTitle('طلبات المرافقة المهنية'),
        for (final row in _pending)
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: Text('${row['service_title'] ?? 'زيارة'}'),
            subtitle: const Text('أكّد فقط في حال استعدادك لمرافقة الزيارة'),
            trailing: TextButton(
              onPressed: _busy ? null : () => _load(row),
              child: const Text('تأكيد المرافقة'),
            ),
          ),
      ],
    );
  }
}
