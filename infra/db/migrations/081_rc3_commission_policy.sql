-- The assigned policy and eligibility calculation use the same whole-unit
-- commercial rounding employed by final invoicing. No existing migration changes.
CREATE FUNCTION resolve_nurse_commission(p_nurse_id uuid,p_base_bps integer,p_price numeric)
RETURNS TABLE(base_bps integer,applied_bps integer,tier_id uuid,tier_policy_signature text,reservation_amount numeric)
LANGUAGE sql STABLE AS $$
  WITH global_rating AS (
    SELECT coalesce(avg(stars),4) AS mean FROM visit_reviews WHERE reviewer_role='PATIENT'
  ), nurse_rating AS (
    SELECT count(*) AS reviews,coalesce(sum(vr.stars),0) AS stars
    FROM visit_reviews vr JOIN visits v ON v.id=vr.visit_id
    JOIN request_assignments a ON a.id=v.assignment_id
    WHERE a.nurse_id=p_nurse_id AND vr.reviewer_role='PATIENT'
  )
  SELECT p_base_bps,least(p_base_bps,coalesce(t.commission_bps,p_base_bps)),t.id,
    CASE WHEN t.id IS NOT NULL THEN concat_ws(':',t.id,t.min_reputation,t.min_reviews,t.commission_bps) END,
    round(p_price*least(p_base_bps,coalesce(t.commission_bps,p_base_bps))/10000,0)
  FROM global_rating g CROSS JOIN nurse_rating n
  LEFT JOIN LATERAL (
    SELECT id,commission_bps,min_reputation,min_reviews FROM commission_tiers
    WHERE active AND min_reviews<=n.reviews AND min_reputation<=(5*g.mean+n.stars)/(5+n.reviews)
    ORDER BY min_reputation DESC,min_reviews DESC,commission_bps ASC,id LIMIT 1
  ) t ON true
$$;

-- A zero estimate still owns a reservation so final time-based commission is reconciled.
ALTER TABLE financial_reservations DROP CONSTRAINT financial_reservations_amount_check;
ALTER TABLE financial_reservations ADD CONSTRAINT financial_reservations_amount_check
  CHECK(amount>0 OR (amount=0 AND currency_account_id IS NOT NULL AND nurse_id IS NOT NULL));

-- One policy for API acceptance and worker discovery. Redis snapshots are input,
-- never an assignment authority: the function reads current relational facts.
CREATE OR REPLACE FUNCTION nurse_eligibility_reasons(
 p_nurse_id uuid,p_request_id uuid,p_context text,p_start timestamptz DEFAULT NULL,
 p_end timestamptz DEFAULT NULL,p_live jsonb DEFAULT NULL,p_radius double precision DEFAULT NULL,
 p_guardian boolean DEFAULT false
) RETURNS text[] LANGUAGE plpgsql STABLE AS $$
DECLARE n record; r record; a record; loc record; reasons text[] := '{}';
 live_required boolean; future_reservation boolean; current_dues numeric; held_prepaid numeric;
 held_credit numeric; estimated numeric; prepaid_available numeric; credit_available numeric;
BEGIN
 SELECT nn.*,u.status AS account_status INTO n FROM nurses nn JOIN users u ON u.id=nn.user_id WHERE nn.id=p_nurse_id;
 SELECT * INTO r FROM care_requests WHERE id=p_request_id;
 IF n.id IS NULL OR r.id IS NULL THEN RETURN ARRAY['NURSE_OR_REQUEST_NOT_FOUND']; END IF;
 IF n.account_status<>'ACTIVE' THEN reasons:=array_append(reasons,'NURSE_ACCOUNT_INACTIVE'); END IF;
 IF NOT n.verified THEN reasons:=array_append(reasons,'NURSE_NOT_VERIFIED'); END IF;
 IF NOT EXISTS(SELECT 1 FROM nurse_credentials WHERE nurse_id=n.id AND approved AND expires_at>statement_timestamp())
 THEN reasons:=array_append(reasons,'LICENSE_MISSING_OR_EXPIRED'); END IF;
 IF NOT EXISTS(SELECT 1 FROM nurse_skills WHERE nurse_id=n.id AND service_id=r.service_id AND approved)
 OR EXISTS(SELECT 1 FROM care_request_items i WHERE i.request_id=r.id AND NOT EXISTS(
 SELECT 1 FROM nurse_skills sk WHERE sk.nurse_id=n.id AND sk.service_id=i.service_id AND sk.approved))
 THEN reasons:=array_append(reasons,'MISSING_REQUIRED_SKILLS'); END IF;
 IF EXISTS(SELECT 1 FROM user_blocks b WHERE b.revoked_at IS NULL AND
 ((b.blocker_user_id=n.user_id AND b.blocked_user_id=r.requester_user_id) OR
 (b.blocker_user_id=r.requester_user_id AND b.blocked_user_id=n.user_id)))
 THEN reasons:=array_append(reasons,'USER_BLOCKED'); END IF;
 IF r.clinical_approval_status NOT IN ('NOT_REQUIRED','APPROVED') THEN reasons:=array_append(reasons,'CLINICAL_APPROVAL_REQUIRED'); END IF;
 future_reservation:=p_context<>'START' AND p_start IS NOT NULL AND p_end>p_start AND p_start>statement_timestamp();
 live_required:=p_context IN ('OFFER','START') OR (r.booking_mode='INSTANT' AND p_context IN ('ACCEPT','ASSIGN'));
 IF EXISTS(SELECT 1 FROM request_assignments aa JOIN care_requests ar ON ar.id=aa.request_id
 WHERE aa.nurse_id=n.id AND aa.status='ACTIVE' AND aa.request_id<>r.id
 AND ar.status IN ('ASSIGNED','EN_ROUTE','ARRIVED','IN_SERVICE')
 AND (NOT future_reservation OR aa.planned_end_at IS NULL OR aa.planned_end_at<=statement_timestamp() OR
 aa.planned_end_at+aa.travel_buffer_after_minutes*interval '1 minute'>p_start-interval '30 minutes'))
 THEN reasons:=array_append(reasons,'NURSE_HAS_ACTIVE_EXECUTION'); END IF;
 IF live_required THEN
   IF n.availability_intent<>'AVAILABLE' OR
    (p_context='START' AND n.work_status NOT IN ('EN_ROUTE','IN_SERVICE')) OR
    (p_context<>'START' AND n.work_status<>'AVAILABLE') THEN reasons:=array_append(reasons,'NURSE_NOT_AVAILABLE'); END IF;
   IF n.last_heartbeat_at IS NULL OR n.last_heartbeat_at<statement_timestamp()-coalesce(r.search_max_heartbeat_seconds,120)*interval '1 second'
   THEN reasons:=array_append(reasons,'HEARTBEAT_STALE'); END IF;
   IF p_live IS NULL THEN
     SELECT location,coalesce(captured_at,recorded_at) AS captured_at,coalesce(received_at,recorded_at) AS received_at,accuracy_m,session_id
       INTO loc FROM nurse_locations WHERE nurse_id=n.id;
   ELSE
     SELECT CASE WHEN p_live->>'latitude' IS NOT NULL THEN ST_SetSRID(ST_MakePoint((p_live->>'longitude')::float8,(p_live->>'latitude')::float8),4326)::geography END AS location,
       (p_live->>'capturedAt')::timestamptz AS captured_at,(p_live->>'receivedAt')::timestamptz AS received_at,
       (p_live->>'accuracyMeters')::numeric AS accuracy_m,(p_live->>'sessionId')::uuid AS session_id INTO loc;
   END IF;
   IF loc.location IS NULL OR loc.session_id IS NULL OR NOT EXISTS(SELECT 1 FROM device_sessions ds WHERE ds.id=loc.session_id AND ds.user_id=n.user_id AND ds.revoked_at IS NULL) THEN reasons:=array_append(reasons,'LOCATION_REQUIRED');
   ELSE
     IF loc.captured_at IS NULL OR loc.received_at IS NULL OR
       least(loc.captured_at,loc.received_at)<statement_timestamp()-coalesce(r.search_max_location_seconds,120)*interval '1 second'
       OR loc.captured_at>statement_timestamp()+interval '30 seconds'
       THEN reasons:=array_append(reasons,'LOCATION_STALE'); END IF;
     IF loc.accuracy_m IS NULL OR loc.accuracy_m<0 OR loc.accuracy_m>coalesce(r.search_max_accuracy_meters,100)
       THEN reasons:=array_append(reasons,'LOCATION_INACCURATE'); END IF;
     IF NOT ST_DWithin(loc.location,r.location,coalesce(p_radius,r.search_radius_meters,10000))
       THEN reasons:=array_append(reasons,'OUTSIDE_SERVICE_RADIUS'); END IF;
   END IF;
 END IF;
 IF p_start IS NOT NULL AND p_end IS NOT NULL AND p_end>p_start AND
 nurse_has_schedule_conflict(n.id,p_start-interval '30 minutes',p_end+interval '30 minutes',r.id)
 THEN reasons:=array_append(reasons,'NURSE_SCHEDULE_CONFLICT'); END IF;
 IF p_context<>'START' THEN
   SELECT * INTO a FROM nurse_financial_currency_accounts WHERE nurse_id=n.id AND currency_code=r.currency_code;
   SELECT reservation_amount INTO estimated FROM resolve_nurse_commission(n.id,r.commission_bps,r.price_amount);
   IF a.id IS NULL THEN reasons:=array_append(reasons,'FINANCIAL_SETUP_REQUIRED');
   ELSE
     SELECT greatest(coalesce(sum(debit_amount-credit_amount),0),0) INTO current_dues
       FROM financial_ledger_entries WHERE currency=r.currency_code AND account_id IN
       ('CASH_HELD_BY_NURSE:'||n.id::text,'NURSE_PAYABLE:'||n.id::text);
     SELECT coalesce(sum(prepaid_amount),0),coalesce(sum(credit_amount),0) INTO held_prepaid,held_credit
       FROM financial_reservations WHERE nurse_id=n.id AND currency_code=r.currency_code AND status='HELD';
     IF a.settlement_required OR (a.credit_limit>0 AND current_dues>a.credit_limit)
       THEN reasons:=array_append(reasons,'SETTLEMENT_REQUIRED'); END IF;
     prepaid_available:=CASE WHEN a.financial_model='RECEIVABLES' THEN 0 ELSE greatest(0,a.prepaid_balance-held_prepaid) END;
     credit_available:=CASE WHEN a.financial_model='PREPAID' THEN 0 ELSE greatest(0,a.credit_limit-current_dues-held_credit) END;
     IF estimated>prepaid_available+credit_available THEN reasons:=array_append(reasons,
       CASE WHEN a.financial_model='PREPAID' THEN 'INSUFFICIENT_PREPAID_BALANCE' ELSE 'FINANCIAL_LIMIT_REACHED' END); END IF;
   END IF;
 END IF;
 IF p_guardian AND p_context<>'BROWSE' THEN
   IF guardian_dispatch_denial(n.id,r.id,coalesce(p_start,statement_timestamp())) IS NOT NULL
   THEN reasons:=array_append(reasons,'SAFETY_POLICY_RESTRICTED'); END IF;
 END IF;
 RETURN reasons;
END $$;
