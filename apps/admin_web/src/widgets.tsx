import {useState, type ReactNode} from 'react';
import {api} from './session';

export const Modal = ({title, onClose, children}: {title: string; onClose: () => void; children: ReactNode}) =>
  <div className="modal" onClick={onClose}><div className="panel modal-box wide" onClick={e => e.stopPropagation()}>
    <div className="modal-head"><h2>{title}</h2><button className="ghost" onClick={onClose} aria-label="إغلاق">✕</button></div>{children}</div></div>;

/** Shows a secret exactly once (temporary password). */
export const Secret = ({label, value, onClose}: {label: string; value: string; onClose: () => void}) =>
  <Modal title="كلمة المرور المؤقتة" onClose={onClose}>
    <p className="hint">{label} تُعرض مرة واحدة فقط. سلّمها لصاحب الحساب بشكل آمن؛ سيُطلب منه تغييرها عند أول دخول.</p>
    <p className="secret" dir="ltr">{value}</p>
    <div className="actions"><button className="pill on" onClick={() => void navigator.clipboard?.writeText(value)}>نسخ</button><button className="pill" onClick={onClose}>تم</button></div>
  </Modal>;

export function useBusy() {
  const [busy, setBusy] = useState(false); const [err, setErr] = useState('');
  async function run<T>(f: () => Promise<T>): Promise<T | undefined> {
    setBusy(true); setErr('');
    try { return await f(); } catch (e) { setErr((e as Error).message); } finally { setBusy(false); }
  }
  return {busy, err, run, setErr};
}

/** Opens a protected file: fetched with the admin token, shown from a temporary blob URL (never a public link). */
export async function openProtected(path: string) {
  const r = await api(path);
  if (!r.ok) throw new Error('تعذر فتح المستند');
  const url = URL.createObjectURL(await r.blob());
  window.open(url, '_blank', 'noopener');
  window.setTimeout(() => URL.revokeObjectURL(url), 60_000);
}
export const fmtDate = (v?: string | null) => v ? new Date(v).toLocaleDateString('ar-SY', {year: 'numeric', month: 'short', day: 'numeric'}) : '—';
