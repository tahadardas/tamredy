import {useCallback, useEffect, useState} from 'react';
import {getJson, msgOf, sendJson} from './session';
import {openProtected} from './widgets';
import {Panel} from './ui';

type Review = {
  request_id: string;
  required_prescription: boolean;
  evidence_count: number;
  services: string[];
  created_at: string;
};
type Evidence = {id: string; evidence_type: string; original_filename: string; created_at: string};

export function ClinicalReviews() {
  const [items,setItems]=useState<Review[]>([]);
  const [evidence,setEvidence]=useState<Record<string,Evidence[]>>({});
  const [notes,setNotes]=useState<Record<string,string>>({});
  const [error,setError]=useState('');
  const load=useCallback(async()=>{
    try { setItems(await getJson('/v1/clinical-reviews/pending')); setError(''); }
    catch(e) { setError(msgOf(e)); }
  },[]);
  useEffect(()=>{void load();},[load]);

  async function loadEvidence(requestId:string) {
    try { setEvidence(current=>({...current,[requestId]:[]}));
      const rows=await getJson(`/v1/clinical-reviews/${requestId}/evidence`);
      setEvidence(current=>({...current,[requestId]:rows}));
    } catch(e) { setError(msgOf(e)); }
  }
  async function decide(requestId:string,decision:'APPROVE'|'REJECT') {
    const note=(notes[requestId]??'').trim();
    if(note.length<3) return setError('اكتب ملاحظة القرار (3 أحرف على الأقل)');
    try { await sendJson('POST',`/v1/clinical-reviews/${requestId}/decision`,{decision,note}); await load(); }
    catch(e) { setError(msgOf(e)); }
  }

  return <Panel title="المراجعات السريرية" subtitle="صلاحية مستقلة ومحدودة للطلبات التي تتطلب وصفة أو اعتمادًا سريريًا">
    {error&&<p className="hint err" role="alert">{error}</p>}
    {!items.length?<p className="hint">لا توجد مراجعات معلّقة.</p>:items.map(item=><div className="card" key={item.request_id}>
      <h3>{item.services.join('، ')}</h3>
      <p className="hint">المعرف: <span dir="ltr">{item.request_id}</span> — المرفقات: {item.evidence_count}</p>
      <button className="pill" onClick={()=>void loadEvidence(item.request_id)}>عرض قائمة المرفقات</button>
      {(evidence[item.request_id]??[]).map(file=><button className="pill" key={file.id}
        onClick={()=>void openProtected(`/v1/clinical-reviews/evidence/${file.id}`).catch(e=>setError(msgOf(e)))}>
        {file.original_filename} ({file.evidence_type})
      </button>)}
      <label>ملاحظة القرار
        <textarea value={notes[item.request_id]??''} maxLength={2000}
          onChange={e=>setNotes(current=>({...current,[item.request_id]:e.target.value}))}/>
      </label>
      <div className="actions">
        <button className="pill on" onClick={()=>void decide(item.request_id,'APPROVE')}>اعتماد</button>
        <button className="pill danger" onClick={()=>void decide(item.request_id,'REJECT')}>رفض</button>
      </div>
    </div>)}
  </Panel>;
}
