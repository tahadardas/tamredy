import {useCallback, useEffect, useState, type FormEvent} from 'react';
import {api, getJson, msgOf, sendJson} from './session';

type Coverage = {
  id: string; shift_kind: 'DAY' | 'NIGHT'; starts_at: string; ends_at: string;
  primary_name: string | null; backup_name: string | null; governorate_name: string | null;
  primary_present: boolean; backup_present: boolean;
};
type Shift = Coverage & {
  governorate_id: string | null; primary_user_id: string; backup_user_id: string; can_check_in: boolean;
};
type Roster = {shifts: Shift[]; staff?: {id: string; display_name: string | null}[]; regions?: {id: string; name_ar: string}[]};
type Form = {shiftKind: Shift['shift_kind']; startsAt: string; endsAt: string; primaryUserId: string; backupUserId: string; governorateId: string};
const blank: Form = {shiftKind: 'DAY', startsAt: '', endsAt: '', primaryUserId: '', backupUserId: '', governorateId: ''};
const path = '/v1/admin/safety/shifts';
const calendar = new Intl.DateTimeFormat('en-CA', {
  timeZone: 'Asia/Damascus', year: 'numeric', month: '2-digit', day: '2-digit',
  hour: '2-digit', minute: '2-digit', hourCycle: 'h23',
});
const labelTime = new Intl.DateTimeFormat('ar-SY', {timeZone: 'Asia/Damascus', dateStyle: 'medium', timeStyle: 'short'});

function damascusInput(date: Date) {
  const parts = Object.fromEntries(calendar.formatToParts(date).map(part => [part.type, part.value]));
  return `${parts.year}-${parts.month}-${parts.day}T${parts.hour}:${parts.minute}`;
}

function fromDamascus(input: string) {
  const wall = Date.parse(`${input}:00Z`);
  if (!Number.isFinite(wall)) throw new Error('أدخل وقت بدء وانتهاء صالحين.');
  const day = 86400000;
  // Derive both adjacent offsets so nonexistent or repeated local times are rejected.
  const candidates = new Set([-day, 0, day].map(dayOffset => {
    const probe = wall + dayOffset;
    const local = Date.parse(`${damascusInput(new Date(probe))}:00Z`);
    return wall - (local - probe);
  }).filter(instant => damascusInput(new Date(instant)) === input));
  if (candidates.size !== 1) throw new Error('اختر وقتًا آخر بسبب تغير التوقيت المحلي.');
  return new Date([...candidates][0]).toISOString();
}

export type ShiftCoverageProps = {coverage: 'UNCOVERED' | 'PARTIAL' | 'COVERED'; shifts: Coverage[]};

export function ShiftCoverage({coverage, shifts}: ShiftCoverageProps) {
  return <>
    <p><strong>تغطية المناوبات الآن:</strong> {{UNCOVERED: 'لا يوجد حضور مؤكد', PARTIAL: 'تغطية جزئية', COVERED: 'المناوبات المجدولة حاليًا مغطاة'}[coverage]}</p>
    {shifts.map(shift => <p key={shift.id}>
      {shift.governorate_name ?? 'التغطية العامة'} · الأساسي {shift.primary_name ?? 'المناوب'} ({shift.primary_present ? 'متصل' : 'غير متصل'})
      {' · '}الاحتياطي {shift.backup_name ?? 'المناوب'} ({shift.backup_present ? 'متصل' : 'غير متصل'})
    </p>)}
  </>;
}

export function SafetyShifts({onPresence}: {onPresence: () => Promise<void>}) {
  const [roster, setRoster] = useState<Roster>();
  const [activeShift, setActiveShift] = useState<string>();
  const [error, setError] = useState('');
  const [busy, setBusy] = useState(false);
  const [form, setForm] = useState<Form>(blank);
  const [editing, setEditing] = useState<string>();

  const reload = useCallback(async () => {
    try { setRoster(await getJson(path)); }
    catch (error) { setError(msgOf(error)); }
  }, []);

  useEffect(() => {
    void reload();
    const timer = window.setInterval(() => {
      if (document.visibilityState === 'visible') void reload();
    }, 60000);
    return () => window.clearInterval(timer);
  }, [reload]);

  useEffect(() => {
    if (!activeShift) return;
    const timer = window.setInterval(async () => {
      if (document.visibilityState !== 'visible') return;
      try {
        const response = await api(`${path}/${activeShift}/heartbeat`, {method: 'POST'});
        if (!response.ok) {
          setActiveShift(undefined);
          setError('انتهت جلسة الحضور أو تعذر تأكيدها. راجع المناوبة وسجّل الحضور من جديد.');
        }
      } catch {
        setError('تعذر إرسال نبضة الحضور. تحقق من الاتصال.');
      }
    }, 30000);
    return () => window.clearInterval(timer);
  }, [activeShift]);

  async function mutate(work: () => Promise<void>) {
    setBusy(true);
    setError('');
    try {
      await work();
      await reload();
      await onPresence();
    } catch (error) {
      setError(msgOf(error));
    } finally {
      setBusy(false);
    }
  }

  function save(event: FormEvent) {
    event.preventDefault();
    void mutate(async () => {
      const dto = {
        ...form, governorateId: form.governorateId || undefined,
        startsAt: fromDamascus(form.startsAt), endsAt: fromDamascus(form.endsAt),
      };
      await sendJson(editing ? 'PUT' : 'POST', editing ? `${path}/${editing}` : path, dto);
      setForm(blank);
      setEditing(undefined);
    });
  }

  function edit(shift: Shift) {
    setEditing(shift.id);
    setForm({
      shiftKind: shift.shift_kind, startsAt: damascusInput(new Date(shift.starts_at)),
      endsAt: damascusInput(new Date(shift.ends_at)), governorateId: shift.governorate_id ?? '',
      primaryUserId: shift.primary_user_id, backupUserId: shift.backup_user_id,
    });
  }

  function attendance(id: string) {
    void mutate(async () => {
      const leaving = activeShift === id;
      await sendJson('POST', `${path}/${id}/${leaving ? 'checkout' : 'checkin'}`);
      setActiveShift(leaving ? undefined : id);
    });
  }

  return <details className="card">
    <summary>جدول المناوبات وتسجيل الحضور</summary>
    <p>تُعرض المواعيد بتوقيت دمشق. أبقِ صفحة مركز السلامة ظاهرة لإرسال نبضات الحضور.</p>
    {error && <p role="alert">{error}</p>}
    {roster?.staff && <form onSubmit={save}>
      <fieldset disabled={busy}>
        <legend>{editing ? 'تعديل مناوبة قادمة' : 'إضافة مناوبة'}</legend>
        <label>المحافظة <select value={form.governorateId} onChange={e => setForm({...form,governorateId:e.currentTarget.value})}>
          <option value="">تغطية عامة</option>
          {roster.regions?.map(row => <option key={row.id} value={row.id}>{row.name_ar}</option>)}
        </select></label>
        <label>الفترة <select value={form.shiftKind} onChange={e => setForm({...form,shiftKind:e.currentTarget.value as Form['shiftKind']})}>
          <option value="DAY">نهارية</option><option value="NIGHT">ليلية</option>
        </select></label>
        <label>البداية <input type="datetime-local" required value={form.startsAt} onChange={e => setForm({...form,startsAt:e.currentTarget.value})} /></label>
        <label>النهاية <input type="datetime-local" required value={form.endsAt} onChange={e => setForm({...form,endsAt:e.currentTarget.value})} /></label>
        {(['primaryUserId','backupUserId'] as const).map(field => <label key={field}>{field === 'primaryUserId' ? 'المناوب الأساسي' : 'المناوب الاحتياطي'}
          <select required value={form[field]} onChange={e => setForm({...form,[field]:e.currentTarget.value})}>
            <option value="">اختر موظف سلامة</option>
            {roster.staff!.map(row => <option key={row.id} value={row.id}>{row.display_name ?? row.id}</option>)}
          </select>
        </label>)}
        <button className="pill" type="submit">حفظ المناوبة</button>
        {editing && <button className="pill" type="button" onClick={() => {setEditing(undefined); setForm(blank);}}>إلغاء التعديل</button>}
      </fieldset>
    </form>}
    <ul>{roster?.shifts.map(shift => <li key={shift.id}>
      {shift.governorate_name ?? 'التغطية العامة'} · {shift.shift_kind === 'NIGHT' ? 'ليلية' : 'نهارية'} · {labelTime.format(new Date(shift.starts_at))} — {labelTime.format(new Date(shift.ends_at))}
      {shift.can_check_in && <button className="pill" disabled={busy || (!!activeShift && activeShift !== shift.id)} onClick={() => attendance(shift.id)}>
        {activeShift === shift.id ? 'إنهاء الحضور' : 'تسجيل الحضور'}
      </button>}
      {roster.staff && Date.parse(shift.starts_at) > Date.now() && <>
        <button className="pill" disabled={busy} onClick={() => edit(shift)}>تعديل</button>
        <button className="pill" disabled={busy} onClick={() => {
          if (window.confirm('إلغاء المناوبة القادمة؟')) void mutate(async () => { await sendJson('DELETE', `${path}/${shift.id}`); });
        }}>إلغاء المناوبة</button>
      </>}
    </li>)}</ul>
    {roster && roster.shifts.length === 0 && <p>لا توجد مناوبات في هذا الجدول.</p>}
  </details>;
}
