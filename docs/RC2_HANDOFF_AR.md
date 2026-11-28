# Tamreedy 3.1 RC2

الفرع `feature/tamreedy-rc2-regression-closure` مبني على `b1427e0f3f2afbdb468a89f343ebaaade02bfbee`. يحدد `RC2_FIX_MATRIX.json` الملفات والأسطر والـCommits وأدلة التحقق لكل بند. يتضمن الإصدار تنفيذ البنود الثلاثين، منها 22 متحققة سلوكيًا و8 ذات تحقق تشغيلي متبقٍ.

- الطلبات والجلسات والزيارات والإشعارات والمكالمات والتخزين السريري المشفر عبر تطبيقَي Flutter والمكتبة المشتركة.
- أهلية التوزيع ومواعيد الزيارات والقيود المالية بحسب العملة وفحوص الجاهزية عبر API وWorker. اقتصر تغيير لوحة الإدارة على عرض أرصدة الحسابات بحسب العملة.
- الترحيلات الجديدة `070_rc2_booking_terms.sql` و`071_rc2_currency_accounts.sql` و`072_rc2_shared_eligibility.sql` و`079_rc2_worker_heartbeat.sql`. أضيفت رسالة Socket.IO `call.signal` بإقرار استلام. لا توجد مسارات HTTP جديدة.

## أوامر التحقق

| الفحص | الأمر | النتائج المحلية |
| --- | --- | --- |
| فحص الأنواع | `pnpm typecheck` | exit 0 |
| البناء | `pnpm --filter @tamreedy/api build`، `pnpm --filter @tamreedy/worker build`، `pnpm --filter @tamreedy/admin build` | exit 0 لكل منها |
| الترحيلات | `node infra/db/migrate.mjs` على قاعدة الاختبار | 75 ترحيلًا، بما فيها الترحيلات الأربعة الجديدة، واختبار ترقية يحفظ البيانات التاريخية والنص العربي |
| API وPostgreSQL | `node --test --test-concurrency=2 apps/api/tests/*.test.mjs apps/api/tests/concurrency.integration.mjs` | 202 في الجولة المحلية المجمعة، تلتها اختبارات الجاهزية والإقلاع المتأثرة |
| Worker | `node --test --test-concurrency=2 apps/worker/tests/*.test.mjs` | 14 ناجحًا، exit 0 |
| Flutter | `flutter test --no-pub` و`flutter analyze --no-pub` في كل حزمة | المكتبة 41، المريض 24، الممرض 21، بلا مشكلات Analyze |
| ضغط الاتصالات | `RUN_RC2_SOCKET_LOAD=true node --test apps/api/tests/rc2-socket-load.integration.mjs` مع قاعدة اختبار محلية | 500 اتصال مفتوح بالتزامن و500 حدث خاص، 0 تسليم لحساب خاطئ، exit 0 |
| نسخ Android | `./scripts/build-rc2-review.ps1` | APK وAAB لكل تطبيق، الإصدار `3.1.0-rc.2` ورقم البناء `7` |

أثبت PostgreSQL إسنادًا واحدًا عند قبول 100 ممرض اصطناعي الطلب نفسه، واختُبر تنافس الحجز مع الإسناد بترتيبَي إمساك القفل. بلغت أزمنة وصول الأحداث عند 500 اتصال P50/P95/P99 ‏326.015 / 407.800 / 411.310 مللي ثانية. لم تسجل قاعدة البيانات أخطاء في جولة Socket.IO، وبلغت ذروة انتظار تجمع الاتصالات 500. القياسات تخص نسخة خادم واحدة وبدأت الاتصالات بدفعات من 25.

نسخ Android تحمل توقيع `Android Debug`، وتوجد بصمات SHA-256 في `rc2-evidence/release-artifacts.json`. استخدمت نسخة المراجعة رقم البناء التالي بعد الموجود في المستودع. لم يُتحقق من توفر الرقم في Google Play.

يتطلب اعتماد النشر توقيع المتجر، وإثبات عملة الأرصدة التاريخية وتسويتها إداريًا، والمراجعة الهندسية المستقلة. ما زالت جلسات WebRTC وICE/TURN وفقد ACK وFCM وRedis على بيئة تشغيل فعلية، واسترجاع المرفقات بعد إعادة تشغيل Android، وسيناريوهات الأجهزة متعددة المستخدمين 10+10 و50+30 بحاجة إلى اختبار. لم تتصل اختبارات الضغط ببيئة الإنتاج.
