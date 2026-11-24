import {useCallback, useEffect, useState, type FormEvent} from 'react';
import {api, getJson, msgOf, sendJson} from './session';
import {Chip, Notice, Panel, Table} from './ui';
import {CalendarCheck, Clock, Plus, RefreshCw, UserCheck, Users} from 'lucide-react';

type Coverage = {
  id: string;
  shift_kind: 'DAY' | 'NIGHT';
  starts_at: string;
  ends_at: string;
  primary_name: string | null;
  backup_name: string | null;
  governorate_name: string | null;
  primary_present: boolean;
  backup_present: boolean;
};

type Shift = Coverage & {
  governorate_id: string | null;
  primary_user_id: string;
  backup_user_id: string;
  can_check_in: boolean;
};

type Roster = {
  shifts: Shift[];
  staff?: {id: string; display_name: string | null}[];
  regions?: {id: string; name_ar: string}[];
};

type Form = {
  shiftKind: Shift['shift_kind'];
  startsAt: string;
  endsAt: string;
  primaryUserId: string;
  backupUserId: string;
  governorateId: string;
};

const blank: Form = {
  shiftKind: 'DAY',
  startsAt: '',
  endsAt: '',
  primaryUserId: '',
  backupUserId: '',
  governorateId: '',
};

const path = '/v1/admin/safety/shifts';
const calendar = new Intl.DateTimeFormat('en-CA', {
  timeZone: 'Asia/Damascus',
  year: 'numeric',
  month: '2-digit',
  day: '2-digit',
  hour: '2-digit',
  minute: '2-digit',
  hourCycle: 'h23',
});
const labelTime = new Intl.DateTimeFormat('ar-SY', {
  timeZone: 'Asia/Damascus',
  dateStyle: 'medium',
  timeStyle: 'short',
});

function damascusInput(date: Date) {
  const parts = Object.fromEntries(calendar.formatToParts(date).map(part => [part.type, part.value]));
  return `${parts.year}-${parts.month}-${parts.day}T${parts.hour}:${parts.minute}`;
}

function fromDamascus(input: string) {
  const wall = Date.parse(`${input}:00Z`);
  if (!Number.isFinite(wall)) throw new Error('أدخل وقت بدء وانتهاء صالحين.');
  const day = 86400000;
  const candidates = new Set(
    [-day, 0, day]
      .map(dayOffset => {
        const probe = wall + dayOffset;
        const local = Date.parse(`${damascusInput(new Date(probe))}:00Z`);
        return wall - (local - probe);
      })
      .filter(instant => damascusInput(new Date(instant)) === input),
  );
  if (candidates.size !== 1) throw new Error('اختر وقتًا آخر بسبب تغير التوقيت المحلي.');
  return new Date([...candidates][0]).toISOString();
}

export type ShiftCoverageProps = {
  coverage: 'UNCOVERED' | 'PARTIAL' | 'COVERED';
  shifts: Coverage[];
};

export function ShiftCoverage({coverage, shifts}: ShiftCoverageProps) {
  const tone = coverage === 'COVERED' ? 'success' : coverage === 'PARTIAL' ? 'warn' : 'danger';
  const label = {
    UNCOVERED: 'تنبيه: لا يوجد حضور مؤكد حالياً لمشرفي السلامة',
    PARTIAL: 'تغطية جزئية: أحد المناوبين متصل والآخر غير مسجل',
    COVERED: 'حالة التغطية ممتازة: المناوبات المجدولة حالياً مغطاة بالكامل',
  }[coverage];

  return (
    <div style={{marginBottom: 16}}>
      <Notice tone={tone}>
        <div style={{display: 'flex', flexDirection: 'column', gap: 6}}>
          <strong>{label}</strong>
          {shifts.map(shift => (
            <div key={shift.id} style={{fontSize: 12}}>
              {shift.governorate_name ?? 'التغطية العامة'}: المناوب الأساسي{' '}
              <strong>{shift.primary_name ?? 'غير محدد'}</strong> ({shift.primary_present ? 'متصل ومسجل' : 'غير متصل'}) ·
              المناوب الاحتياطي <strong>{shift.backup_name ?? 'غير محدد'}</strong> ({shift.backup_present ? 'متصل' : 'غير متصل'})
            </div>
          ))}
        </div>
      </Notice>
    </div>
  );
}

export function SafetyShifts({onPresence}: {onPresence: () => Promise<void>}) {
  const [roster, setRoster] = useState<Roster>();
  const [activeShift, setActiveShift] = useState<string>();
  const [error, setError] = useState('');
  const [busy, setBusy] = useState(false);
  const [form, setForm] = useState<Form>(blank);
  const [editing, setEditing] = useState<string>();

  const load = useCallback(async () => {
    try {
      setRoster(await getJson(path));
      setError('');
    } catch (err) {
      setError(msgOf(err));
    }
  }, []);

  useEffect(() => {
    void load();
  }, [load]);

  async function mutate(f: () => Promise<void>) {
    if (busy) return;
    setBusy(true);
    try {
      await f();
      await load();
      await onPresence();
    } catch (err) {
      setError(msgOf(err));
    } finally {
      setBusy(false);
    }
  }

  function save(event: FormEvent) {
    event.preventDefault();
    void mutate(async () => {
      const dto = {
        ...form,
        governorateId: form.governorateId || undefined,
        startsAt: fromDamascus(form.startsAt),
        endsAt: fromDamascus(form.endsAt),
      };
      await sendJson(editing ? 'PUT' : 'POST', editing ? `${path}/${editing}` : path, dto);
      setForm(blank);
      setEditing(undefined);
    });
  }

  function edit(shift: Shift) {
    setEditing(shift.id);
    setForm({
      shiftKind: shift.shift_kind,
      startsAt: damascusInput(new Date(shift.starts_at)),
      endsAt: damascusInput(new Date(shift.ends_at)),
      governorateId: shift.governorate_id ?? '',
      primaryUserId: shift.primary_user_id,
      backupUserId: shift.backup_user_id,
    });
  }

  function attendance(id: string) {
    void mutate(async () => {
      const leaving = activeShift === id;
      await sendJson('POST', `${path}/${id}/${leaving ? 'checkout' : 'checkin'}`);
      setActiveShift(leaving ? undefined : id);
    });
  }

  return (
    <div style={{marginTop: 20}}>
      {error && (
        <div style={{marginBottom: 16}}>
          <Notice tone="danger">{error}</Notice>
        </div>
      )}

      <Panel
        title={editing ? 'تعديل بيانات المناوبة' : 'جدولة مناوبة سلامة جديدة'}
        subtitle="تحديد أوقات المناوبة والمشرفين المناوبين بتوقيت دمشق"
      >
        {roster?.staff && (
          <form onSubmit={save} className="form">
            <label>
              المحافظة
              <select
                value={form.governorateId}
                onChange={e => setForm({...form, governorateId: e.currentTarget.value})}
              >
                <option value="">تغطية عامة (كافة المحافظات)</option>
                {roster.regions?.map(row => (
                  <option key={row.id} value={row.id}>
                    {row.name_ar}
                  </option>
                ))}
              </select>
            </label>

            <label>
              فترة المناوبة
              <select
                value={form.shiftKind}
                onChange={e => setForm({...form, shiftKind: e.currentTarget.value as Form['shiftKind']})}
              >
                <option value="DAY">فترة نهارية</option>
                <option value="NIGHT">فترة ليلية</option>
              </select>
            </label>

            <label>
              توقيت البدء
              <input
                type="datetime-local"
                required
                value={form.startsAt}
                onChange={e => setForm({...form, startsAt: e.currentTarget.value})}
              />
            </label>

            <label>
              توقيت الانتهاء
              <input
                type="datetime-local"
                required
                value={form.endsAt}
                onChange={e => setForm({...form, endsAt: e.currentTarget.value})}
              />
            </label>

            <label>
              المشرف المناوب الأساسي
              <select
                required
                value={form.primaryUserId}
                onChange={e => setForm({...form, primaryUserId: e.currentTarget.value})}
              >
                <option value="">اختر موظف سلامة</option>
                {roster.staff.map(row => (
                  <option key={row.id} value={row.id}>
                    {row.display_name ?? row.id}
                  </option>
                ))}
              </select>
            </label>

            <label>
              المشرف المناوب الاحتياطي
              <select
                required
                value={form.backupUserId}
                onChange={e => setForm({...form, backupUserId: e.currentTarget.value})}
              >
                <option value="">اختر موظف سلامة احتياطي</option>
                {roster.staff.map(row => (
                  <option key={row.id} value={row.id}>
                    {row.display_name ?? row.id}
                  </option>
                ))}
              </select>
            </label>

            <div className="actions" style={{gridColumn: '1 / -1', marginTop: 8}}>
              <button className="pill on" type="submit" disabled={busy}>
                {editing ? 'حفظ تعديل المناوبة' : '+ إضافة المناوبة للجدول'}
              </button>
              {editing && (
                <button
                  className="pill"
                  type="button"
                  onClick={() => {
                    setEditing(undefined);
                    setForm(blank);
                  }}
                >
                  إلغاء التعديل
                </button>
              )}
            </div>
          </form>
        )}
      </Panel>

      <div style={{marginTop: 20}}>
        <Panel
          title="جدول المناوبات وسجل الحضور"
          subtitle={`إجمالي المناوبات المسجلة: ${roster?.shifts.length ?? 0}`}
        >
          {roster && roster.shifts.length === 0 ? (
            <div className="empty-hint">لا توجد مناوبات مجدولة حالياً.</div>
          ) : (
            <Table
              head={['النطاق', 'الفترة', 'التوقيت الزمني', 'المناوبون', 'حالة الحضور', 'الإجراءات']}
              rows={(roster?.shifts ?? []).map(shift => [
                shift.governorate_name ?? 'تغطية عامة',
                <Chip key="k" tone={shift.shift_kind === 'NIGHT' ? 'purple' : 'info'}>
                  {shift.shift_kind === 'NIGHT' ? 'ليلية' : 'نهارية'}
                </Chip>,
                <span key="time" dir="ltr" style={{fontSize: 12, fontWeight: 600}}>
                  {labelTime.format(new Date(shift.starts_at))} — {labelTime.format(new Date(shift.ends_at))}
                </span>,
                <div key="staff" style={{fontSize: 12}}>
                  <div>الأساسي: <strong>{shift.primary_name ?? 'غير محدد'}</strong></div>
                  <div style={{color: 'var(--sub)'}}>الاحتياطي: {shift.backup_name ?? 'غير محدد'}</div>
                </div>,
                <div key="att">
                  {shift.can_check_in ? (
                    <button
                      className={`pill ${activeShift === shift.id ? 'danger' : 'on'}`}
                      disabled={busy || (!!activeShift && activeShift !== shift.id)}
                      onClick={() => attendance(shift.id)}
                    >
                      {activeShift === shift.id ? 'تسجيل الانصراف' : 'تسجيل الحضور'}
                    </button>
                  ) : (
                    <Chip tone="default">خارج وقت التحضير</Chip>
                  )}
                </div>,
                <div key="acts" className="acts">
                  {roster?.staff && Date.parse(shift.starts_at) > Date.now() && (
                    <>
                      <button className="pill" disabled={busy} onClick={() => edit(shift)}>
                        تعديل
                      </button>
                      <button
                        className="pill danger"
                        disabled={busy}
                        onClick={() => {
                          if (window.confirm('هل أنت متأكد من إلغاء هذه المناوبة؟')) {
                            void mutate(async () => {
                              await sendJson('DELETE', `${path}/${shift.id}`);
                            });
                          }
                        }}
                      >
                        إلغاء
                      </button>
                    </>
                  )}
                </div>,
              ])}
            />
          )}
        </Panel>
      </div>
    </div>
  );
}
