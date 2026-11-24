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
| 13. طلب الخدمة الآن أو لاحقًا | NOT_STARTED | |
| 14. شاشة البحث عن ممرض | NOT_STARTED | |
| 15. شاشة تتبع الممرض | NOT_STARTED | |
| 16. سياسة الإلغاء المعتمدة | NOT_STARTED | |
| 17. سجل الزيارات | NOT_STARTED | |
| 18. المحفظة | IN_PROGRESS | Existing server status shown in production, retry tested. Authoritative ledger unavailable. |
| 19. الملف الشخصي والإعدادات | NOT_STARTED | |
| 20. تصميم تطبيق الممرض | NOT_STARTED | |
| 21. Tamreedy Guardian — المعمارية الأساسية | NOT_STARTED | |
| 22. شاشة الطوارئ والسلامة | NOT_STARTED | |
| 23. زر SOS العائم | NOT_STARTED | |
| 24. الاستغاثة الصامتة — Silent SOS | NOT_STARTED | |
| 25. حالات الاستغاثة | NOT_STARTED | |
| 26. المناوبات ومركز السلامة | NOT_STARTED | |
| 27. نظام إدارة المناوبات | NOT_STARTED | |
| 28. جهات الاتصال الموثوقة | NOT_STARTED | |
| 29. دليل أرقام الطوارئ | NOT_STARTED | |
| 30. تتبع مسارات الزيارات — Safety Location Evidence | NOT_STARTED | |
| 31. تخزين نقاط GPS | NOT_STARTED | |
| 32. العمل عند ضعف الإنترنت | NOT_STARTED | |
| 33. التحقق الدوري من السلامة — Safety Check-In | NOT_STARTED | |
| 34. سياسة الممرضات والعمل الليلي | NOT_STARTED | |
| 35. توثيق المريض والحد من إساءة الاستخدام | NOT_STARTED | |
| 36. Safety PIN والتحقق من الزيارة | NOT_STARTED | |
| 37. الإنهاء الآمن للزيارة | NOT_STARTED | |
| 38. نظام الحوادث الأمنية | NOT_STARTED | |
| 39. ملف الأدلة الرقمية | NOT_STARTED | |
| 40. منع التسجيل السري للصوت والصورة | NOT_STARTED | |
| 41. قاعدة البيانات | NOT_STARTED | |
| 42. حماية البيانات وسياسة الاحتفاظ | NOT_STARTED | |
| 43. الصلاحيات | NOT_STARTED | |
| 44. واجهات API | NOT_STARTED | |
| 45. الإشعارات والتصعيد | NOT_STARTED | |
| 46. مشاركة الزيارة مع شخص موثوق | NOT_STARTED | |
| 47. Google Play Compliance | NOT_STARTED | |
| 48. الأداء وسرعة التطبيق | NOT_STARTED | |
| 49. الاختبارات الإلزامية للتصميم | NOT_STARTED | |
| 50. الاختبارات الإلزامية لنظام Guardian | NOT_STARTED | |
| 51. مراحل التنفيذ | IN_PROGRESS | Phase 0 recorded. Phase 1 implemented locally, external verification pending. Phase 2 login implemented. Phase 3 patient home slice started. |
| 52. شروط اكتمال المشروع | NOT_STARTED | |
| 53. التقرير النهائي | NOT_STARTED | |
