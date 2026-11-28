import {useCallback, useEffect, useRef, useState} from 'react';
import {getJson,sendJson} from './session';
import {Table} from './ui';

const models = ['RECEIVABLES','PREPAID','HYBRID'] as const;
type Model=typeof models[number];
type Account={
  currency_code:string;financial_model:Model;credit_limit:string;prepaid_balance:string;
  reserved_balance:string;balance:string;settlement_required:boolean;version:number;
  administratively_restricted:boolean;restriction_reason:string|null;
};
type Statement={items:Account[];legacyStatus:string|null;legacy:{evidence_reference:string|null}|null};
const currencyPattern=/^[A-Z][A-Z0-9_]{2,15}$/;
const moneyPattern=/^\d{1,16}(?:\.\d{1,2})?$/;

export function NurseFinancialAccounts({nurseId}:{nurseId:string}) {
  const endpoint=`/v1/admin/nurses/${nurseId}/financial-accounts`;
  const [statement,setStatement]=useState<Statement|null>(null);
  const [currency,setCurrency]=useState('');
  const [model,setModel]=useState<Model>('RECEIVABLES');
  const [limit,setLimit]=useState('');
  const [selected,setSelected]=useState<Account|null>(null);
  const [restricted,setRestricted]=useState(false);
  const [reason,setReason]=useState('');
  const [proof,setProof]=useState('');
  const [evidence,setEvidence]=useState('');
  const [error,setError]=useState('');
  const [busy,setBusy]=useState(false);
  const inFlight=useRef(false);
  const attempts=useRef(new Map<string,string>());
  const load=useCallback(async()=>{setStatement(await getJson(endpoint));},[endpoint]);
  useEffect(()=>{void load().catch((e:Error)=>setError(e.message));},[load]);
  function select(account:Account|null) {
    setSelected(account);
    setCurrency(account?.currency_code ?? '');
    setModel(account?.financial_model ?? 'RECEIVABLES');
    setLimit(account?.credit_limit ?? '');
    setRestricted(account?.administratively_restricted ?? false);
    setReason(account?.restriction_reason ?? '');
    setProof('');setEvidence('');
  }
  async function mutate(method:string,path:string,body:unknown) {
    if(inFlight.current)return;
    inFlight.current=true;setBusy(true);setError('');
    const attempt=JSON.stringify({method,path,body});
    const key=attempts.current.get(attempt) ?? crypto.randomUUID();
    attempts.current.set(attempt,key);
    try {
      await sendJson(method,path,body,{'Idempotency-Key':key});
      attempts.current.delete(attempt);
      await load();
      select(null);
    } catch(e) {setError((e as Error).message);}
    finally {inFlight.current=false;setBusy(false);}
  }
  function save() {
    if(!currencyPattern.test(currency)||!moneyPattern.test(limit)||(restricted&&!reason.trim()))return;
    if(!selected){
      void mutate('POST',endpoint,{currencyCode:currency,financialModel:model,creditLimit:limit});
      return;
    }
    void mutate('PATCH',`${endpoint}/${encodeURIComponent(currency)}`,{
      expectedVersion:selected.version,financialModel:model,creditLimit:limit,
      administrativelyRestricted:restricted,restrictionReason:reason.trim()||undefined,
    });
  }
  return <section>
    <h4>الحساب المالي</h4>
    {error && <p role="alert" className="hint err">{error}</p>}
    {statement?.legacyStatus && <p className="hint">يتطلب الحساب التاريخي تسوية موثقة وإثبات العملة.</p>}
    {statement?.legacy?.evidence_reference && <p className="hint">مرجع التسوية التاريخية: {statement.legacy.evidence_reference}</p>}
    {statement && !statement.items.length && <p className="hint">يحتاج الممرض إلى استكمال الإعداد المالي.</p>}
    {statement && !!statement.items.length && <Table head={['العملة','النموذج','حد الائتمان','الرصيد المسبق','المحجوز','المستحقات','الحالة','']}
      rows={statement.items.map(a=>[a.currency_code,a.financial_model,a.credit_limit,a.prepaid_balance,a.reserved_balance,a.balance,
        a.settlement_required?'موقوف ماليًا':'مهيأ',<button className="pill" onClick={()=>select(a)}>السياسة / التسوية</button>])}/>}
    <div className="form">
      <label>العملة<input dir="ltr" disabled={!!selected} value={currency} onChange={e=>setCurrency(e.target.value.trim().toUpperCase())}/></label>
      <label>النموذج المالي<select value={model} onChange={e=>setModel(e.target.value as Model)}>{models.map(m=><option key={m}>{m}</option>)}</select></label>
      <label>حد الائتمان<input dir="ltr" inputMode="decimal" value={limit} onChange={e=>setLimit(e.target.value)}/></label>
      {selected && <>
        <label><input type="checkbox" checked={restricted} onChange={e=>setRestricted(e.target.checked)}/> حظر مالي إداري</label>
        {restricted && <label>سبب الحظر<input value={reason} maxLength={200} onChange={e=>setReason(e.target.value)}/></label>}
      </>}
    </div>
    <div className="actions">
      <button className="pill on" disabled={busy||!currencyPattern.test(currency)||!moneyPattern.test(limit)||(restricted&&!reason.trim())} onClick={save}>{selected?'حفظ السياسة':'تهيئة الحساب'}</button>
      {selected && <button className="pill" disabled={busy} onClick={()=>select(null)}>حساب جديد</button>}
    </div>
    {selected && statement?.legacyStatus && <>
      <div className="form">
        <label>مرجع إثبات العملة<input value={evidence} maxLength={200} onChange={e=>setEvidence(e.target.value)}/></label>
        <label>معرّف القيد المثبت للرصيد غير الصفري<input dir="ltr" value={proof} onChange={e=>setProof(e.target.value)}/></label>
      </div>
      <button className="pill" disabled={busy||evidence.trim().length<4} onClick={()=>void mutate('POST',
        `/v1/admin/nurses/${nurseId}/financial-reconciliation`,
        {currencyCode:selected.currency_code,expectedVersion:selected.version,evidenceReference:evidence.trim(),proofTransactionId:proof.trim()||undefined})}>توثيق التسوية التاريخية</button>
    </>}
  </section>;
}
