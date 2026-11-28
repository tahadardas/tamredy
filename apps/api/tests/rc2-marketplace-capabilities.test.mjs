import {test} from 'node:test';
import assert from 'node:assert/strict';
import {ProposalsService} from '../dist/marketplace/proposals.service.js';
import {AssignmentService} from '../dist/marketplace/assignment.service.js';
import {MarketplaceController} from '../dist/marketplace/marketplace.controller.js';
import {ProposalsController} from '../dist/marketplace/proposals.controller.js';

test('RC2-028 disabled OPEN marketplace rejects submission and acceptance before any mutation',async()=>{
  const previous=process.env.OPEN_MARKETPLACE_ENABLED;
  process.env.OPEN_MARKETPLACE_ENABLED='false';
  let databaseCalls=0;
  const db={async query(){databaseCalls++;throw new Error('disabled feature reached database');},
    async transaction(){databaseCalls++;throw new Error('disabled feature opened transaction');}};
  try {
    const proposals=new ProposalsService(db,undefined);
    const assignments=new AssignmentService(db,undefined,undefined);
    const nurseEndpoint=new MarketplaceController(undefined,proposals);
    const patientEndpoint=new ProposalsController(proposals,assignments);
    const disabled=error=>error.getStatus()===503&&error.getResponse().code==='OPEN_MARKETPLACE_DISABLED';
    await assert.rejects(nurseEndpoint.submitProposal({user:{id:'nurse',role:'NURSE'}},'request',{arrivalMinutes:20}),disabled);
    // Submission is an upsert: retry/update attempts use the same guarded seam.
    await assert.rejects(nurseEndpoint.submitProposal({user:{id:'nurse',role:'NURSE'}},'request',{arrivalMinutes:30,note:'تحديث الموعد'}),disabled);
    await assert.rejects(patientEndpoint.acceptProposal({user:{id:'patient',role:'PATIENT'}},'request','proposal',{},'same-key'),disabled);
    assert.equal(databaseCalls,0);
  }finally{if(previous===undefined)delete process.env.OPEN_MARKETPLACE_ENABLED;else process.env.OPEN_MARKETPLACE_ENABLED=previous;}
});

test('RC2-028 disabled marketplace preserves proposal withdrawal and history access',async()=>{
  const previous=process.env.OPEN_MARKETPLACE_ENABLED;
  process.env.OPEN_MARKETPLACE_ENABLED='false';
  let withdrawals=0;
  const db={async query(sql){
    if(sql.startsWith('SELECT id FROM nurses'))return {rows:[{id:'nurse-profile'}],rowCount:1};
    if(sql.includes('UPDATE marketplace_proposals')){withdrawals++;return {rows:[{id:'proposal',request_id:'request'}],rowCount:1};}
    if(sql.includes('SELECT requester_user_id'))return {rows:[],rowCount:0};
    if(sql.includes('SELECT'))return {rows:[{id:'proposal',status:'WITHDRAWN'}],rowCount:1};
    throw new Error('unexpected operation');
  }};
  try{
    const proposals=new ProposalsService(db,undefined);
    assert.equal((await proposals.withdrawProposal('nurse','proposal')).withdrawn,true);
    assert.equal(withdrawals,1);
    assert.equal((await proposals.listNurseProposals('nurse'))[0].id,'proposal');
  }finally{if(previous===undefined)delete process.env.OPEN_MARKETPLACE_ENABLED;else process.env.OPEN_MARKETPLACE_ENABLED=previous;}
});
