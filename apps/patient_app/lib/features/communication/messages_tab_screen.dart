import 'package:flutter/material.dart';
import 'package:tamreedy_core/tamreedy_core.dart';
import '../../core/patient_session_coordinator.dart';
import 'visit_chat_screen.dart';

class MessagesTabScreen extends StatelessWidget {
  final PatientSessionCoordinator session;

  const MessagesTabScreen({super.key, required this.session});

  @override
  Widget build(BuildContext context) {
    final tc = context.tamColors;
    final store = session.conversations;

    return ListenableBuilder(
      listenable: Listenable.merge([store, session.requests]),
      builder: (context, _) {
        final convs = store.conversations;
        final activeReq = session.requests.primaryActiveRequest;

        return Scaffold(
          backgroundColor: tc.background,
          body: SafeArea(
            bottom: false,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Container(
                  color: tc.surface,
                  padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          'المحادثات والتواصل',
                          style: aeroText(size: 18, weight: FontWeight.w800, color: tc.textPrimary),
                        ),
                      ),
                      if (activeReq != null && activeReq.hasAssignedNurse)
                        TextButton.icon(
                          onPressed: () => Navigator.of(context).push(
                            MaterialPageRoute<void>(
                              builder: (_) => VisitChatScreen(
                                session: session,
                                requestId: activeReq.id,
                                peerName: activeReq.nurseName ?? 'الممرض المعتمد',
                              ),
                            ),
                          ),
                          icon: const Icon(Icons.chat_outlined, size: 18),
                          label: const Text('محادثة الزيارة الحالية'),
                        ),
                    ],
                  ),
                ),
                Expanded(
                  child: RefreshIndicator(
                    onRefresh: () => store.loadConversations(),
                    child: store.loading && convs.isEmpty
                        ? ListView(
                            padding: const EdgeInsets.all(16),
                            children: const [
                              TamSkeleton.card(height: 82),
                              SizedBox(height: 10),
                              TamSkeleton.card(height: 82),
                            ],
                          )
                        : store.error != null && convs.isEmpty
                            ? ListView(
                                padding: const EdgeInsets.all(16),
                                children: [
                                  TamErrorState(
                                    title: 'تعذر تحميل المحادثات',
                                    message: store.error!,
                                    onRetry: () => store.loadConversations(),
                                  ),
                                ],
                              )
                            : convs.isEmpty
                                ? ListView(
                                    padding: const EdgeInsets.all(16),
                                    children: [
                                      const TamEmptyState(
                                        icon: Icons.forum_outlined,
                                        title: 'لا توجد محادثات بعد',
                                        message: 'عند إسناد أي زيارة لممرض يمكنك مراسلته والاتصال به بأمان داخل التطبيق.',
                                      ),
                                    ],
                                  )
                                : ListView.builder(
                                    padding: const EdgeInsets.all(16),
                                    itemCount: convs.length,
                                    itemBuilder: (context, idx) {
                                      final c = convs[idx];
                                      return Container(
                                        margin: const EdgeInsets.only(bottom: 10),
                                        decoration: BoxDecoration(
                                          color: tc.surface,
                                          borderRadius: BorderRadius.circular(16),
                                          border: Border.all(color: tc.border),
                                        ),
                                        child: ListTile(
                                          contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                                          leading: CircleAvatar(
                                            backgroundColor: tc.primaryTint,
                                            child: Icon(Icons.person_outline_rounded, color: tc.primary),
                                          ),
                                          title: Row(
                                            children: [
                                              Expanded(
                                                child: Text(
                                                  c.peerName,
                                                  style: aeroText(
                                                    size: 14.5,
                                                    weight: FontWeight.w800,
                                                    color: tc.textPrimary,
                                                  ),
                                                ),
                                              ),
                                              if (c.unreadCount > 0)
                                                Container(
                                                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                                                  decoration: BoxDecoration(
                                                    color: tc.primary,
                                                    borderRadius: BorderRadius.circular(99),
                                                  ),
                                                  child: Text(
                                                    '${c.unreadCount}',
                                                    style: aeroText(
                                                      size: 11,
                                                      weight: FontWeight.w800,
                                                      color: Colors.white,
                                                    ),
                                                  ),
                                                ),
                                            ],
                                          ),
                                          subtitle: Text(
                                            c.lastMessage ?? c.peerRoleLabel,
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: aeroText(size: 12.5, color: tc.textSecondary),
                                          ),
                                          trailing: Icon(Icons.chevron_left_rounded, color: tc.textSecondary),
                                          onTap: () {
                                            if (c.requestId != null && c.requestId!.isNotEmpty) {
                                              Navigator.of(context).push(
                                                MaterialPageRoute<void>(
                                                  builder: (_) => VisitChatScreen(
                                                    session: session,
                                                    requestId: c.requestId!,
                                                    conversationId: c.id,
                                                    peerName: c.peerName,
                                                  ),
                                                ),
                                              );
                                            }
                                          },
                                        ),
                                      );
                                    },
                                  ),
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
