# Tamreedy Guardian implementation matrix

Source: safety.md. Statuses: NOT_STARTED, IN_PROGRESS, IMPLEMENTED, VERIFIED, BLOCKED. Existing Open Dispatch functionality requires evidence against the new requirements before promotion.

| Specification section | Status | Evidence or remaining work |
| --- | --- | --- |
| 1. تعريف المهمة الرئيسية | IN_PROGRESS | |
| 2. تعليمات غير قابلة للتفاوض | IN_PROGRESS | |
| 3. استمرارية التنفيذ بين نماذج الذكاء الاصطناعي | IMPLEMENTED | Git baseline, matrix and checkpoint recorded. |
| 4. الهوية البصرية الإلزامية | IN_PROGRESS | Shared Aero login is implemented. Physical accessibility review pending. |
| 5. فلسفة تجربة الاستخدام — Map-First | IN_PROGRESS | Patient home map, draggable service sheet and RTL drawer implemented. Physical device review pending. |
| 6. الشاشة الرئيسية للمريض | IN_PROGRESS | Patient home map, draggable service sheet and RTL drawer implemented. Physical device review pending. |
| 7. القائمة الجانبية للمريض | IN_PROGRESS | Patient home map, draggable service sheet and RTL drawer implemented. Physical device review pending. |
| 8. تسجيل الدخول وإنشاء الحساب واستعادة كلمة المرور | IN_PROGRESS | Manual recovery and owner-bound sessions exercised in password.test.mjs and device-session.test.mjs. Production DNS, configured support and device verification pending. |
| 9. محرك اختيار العناوين — Location Experience | IN_PROGRESS | Home address selection, local draft and booking handoff covered by patient flow tests. Physical GPS and structured address fields pending. |
| 10. الأماكن المحفوظة | IMPLEMENTED | Migration 026, owner-scoped API, mobile editor and picker. PGlite lifecycle and Flutter selection tested. Physical verification pending. |
| 11. رحلة إنشاء الطلب | IN_PROGRESS | Booking review and selected beneficiary are covered by patient flow and submission tests. Scheduling and tracking review pending. |
| 12. طريقة الدفع | NOT_STARTED | |
| 13. طلب الخدمة الآن أو لاحقًا | IMPLEMENTED | Migration 027 and feature-gated scheduling. Worker release and expiry tested in PGlite. Android and live verification pending. |
| 14. شاشة البحث عن ممرض | NOT_STARTED | |
| 15. شاشة تتبع الممرض | IN_PROGRESS | Active request recovery and coalesced tracking verified in Flutter. Physical tracking pending. |
| 16. سياسة الإلغاء المعتمدة | NOT_STARTED | |
| 17. سجل الزيارات | IN_PROGRESS | Visit history refresh, error and invoice actions implemented. Pagination and device verification pending. |
| 18. المحفظة | IN_PROGRESS | Existing server status shown in production, retry tested. Authoritative ledger unavailable. |
| 19. الملف الشخصي والإعدادات | NOT_STARTED | |
| 20. تصميم تطبيق الممرض | NOT_STARTED | |
| 21. Tamreedy Guardian — المعمارية الأساسية | NOT_STARTED | |
| 22. شاشة الطوارئ والسلامة | IN_PROGRESS | Nurse safety sheet and server receipt states implemented behind a build flag. Offline persistence, emergency access on nested screens, and physical tests pending. |
| 23. زر SOS العائم | IN_PROGRESS | Nurse safety sheet and server receipt states implemented behind a build flag. Offline persistence, emergency access on nested screens, and physical tests pending. |
| 24. الاستغاثة الصامتة — Silent SOS | IN_PROGRESS | Nurse safety sheet and server receipt states implemented behind a build flag. Offline persistence, emergency access on nested screens, and physical tests pending. |
| 25. حالات الاستغاثة | IN_PROGRESS | Migration 028 and nurse tracking/SOS foundation tested with PGlite. Lifecycle, operations and real PostGIS verification pending. |
| 26. المناوبات ومركز السلامة | NOT_STARTED | |
| 27. نظام إدارة المناوبات | NOT_STARTED | |
| 28. جهات الاتصال الموثوقة | IN_PROGRESS | Migration 032, shared editor, auditable staff verification and scope reset tested. Recipient portal and automatic escalation pending. |
| 29. دليل أرقام الطوارئ | IN_PROGRESS | Migration 034, supervisor admin UI and app directory. No actual numbers verified or published. |
| 30. تتبع مسارات الزيارات — Safety Location Evidence | IN_PROGRESS | Migration 028 and nurse tracking/SOS foundation tested with PGlite. Lifecycle, operations and real PostGIS verification pending. |
| 31. تخزين نقاط GPS | IN_PROGRESS | Migration 028 and nurse tracking/SOS foundation tested with PGlite. Lifecycle, operations and real PostGIS verification pending. |
| 32. العمل عند ضعف الإنترنت | IN_PROGRESS | Account-scoped SOS and foreground GPS queue implemented. Mocked replay verified. Physical secure storage and offline emergency directory pending. |
| 33. التحقق الدوري من السلامة — Safety Check-In | IN_PROGRESS | Migration 029, server policy and worker prompt/reminder/alert tested. Mobile and human workflows pending. |
| 34. سياسة الممرضات والعمل الليلي | NOT_STARTED | |
| 35. توثيق المريض والحد من إساءة الاستخدام | NOT_STARTED | |
| 36. Safety PIN والتحقق من الزيارة | NOT_STARTED | |
| 37. الإنهاء الآمن للزيارة | IN_PROGRESS | Migration 033 and safe abort tested with neutral patient payload and open SOS. Staff workflow and physical validation pending. |
| 38. نظام الحوادث الأمنية | IN_PROGRESS | Migration 030 and restricted staff case actions tested. Shift scoping, dashboard and evidence access pending. |
| 39. ملف الأدلة الرقمية | NOT_STARTED | |
| 40. منع التسجيل السري للصوت والصورة | NOT_STARTED | |
| 41. قاعدة البيانات | IN_PROGRESS | Migration 028 and nurse tracking/SOS foundation tested with PGlite. Lifecycle, operations and real PostGIS verification pending. |
| 42. حماية البيانات وسياسة الاحتفاظ | NOT_STARTED | |
| 43. الصلاحيات | IN_PROGRESS | Migration 030 and restricted staff case actions tested. Shift scoping, dashboard and evidence access pending. |
| 44. واجهات API | IN_PROGRESS | Migration 028 and nurse tracking/SOS foundation tested with PGlite. Lifecycle, operations and real PostGIS verification pending. |
| 45. الإشعارات والتصعيد | NOT_STARTED | |
| 46. مشاركة الزيارة مع شخص موثوق | NOT_STARTED | |
| 47. Google Play Compliance | NOT_STARTED | |
| 48. الأداء وسرعة التطبيق | NOT_STARTED | |
| 49. الاختبارات الإلزامية للتصميم | NOT_STARTED | |
| 50. الاختبارات الإلزامية لنظام Guardian | NOT_STARTED | |
| 51. مراحل التنفيذ | IN_PROGRESS | Phase 0 recorded. Phase 1 implemented locally, external verification pending. Phase 2 login implemented. Phase 3 patient home slice started. |
| 52. شروط اكتمال المشروع | NOT_STARTED | |
| 53. التقرير النهائي | NOT_STARTED | |
