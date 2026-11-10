const { Miniflare } = require('miniflare');
const { mkdtempSync, rmSync } = require('node:fs');
const { tmpdir } = require('node:os');
const { join, resolve } = require('node:path');
const { execFileSync } = require('node:child_process');
const assert = require('node:assert/strict');
(async()=>{
 const build=mkdtempSync(join(tmpdir(),'superpaste-sqlite-'));
 execFileSync(process.execPath,[resolve(__dirname,'../node_modules/wrangler/bin/wrangler.js'),'deploy','--dry-run','--outdir',build],{
   cwd:resolve(__dirname,'..'),env:{...process.env,WRANGLER_SEND_METRICS:'false',WRANGLER_LOG_PATH:join(build,'wrangler.log')},stdio:'pipe',
 });
 const options={modules:true,modulesRoot:build,scriptPath:join(build,'index.js'),compatibilityDate:'2024-01-01',
   durableObjects:{QUOTA_LEDGER:{className:'QuotaLedger',useSQLite:true}},durableObjectsPersist:join(build,'state')};
 let mf=new Miniflare(options);
 try {
  const ns=await mf.getDurableObjectNamespace('QUOTA_LEDGER');
  const stub=ns.get(ns.idFromName('test-tier'));
  const reserve=principal=>stub.fetch('https://quota/reserve',{method:'POST',body:JSON.stringify({principal,tier:'trial',globalLimit:300})});
  const principal='a'.repeat(64);
  for(let i=0;i<14;i++)assert.equal((await reserve(principal)).status,200);
  const batch=await Promise.all(Array.from({length:10},()=>reserve(principal)));
  assert.equal(batch.filter(r=>r.status===200).length,1);
  assert.equal(batch.filter(r=>r.status===429).length,9);
  console.log('Real SQLite Durable Object: exactly 1 of 10 concurrent requests reserved the last principal slot.');
  const second=ns.get(ns.idFromName('global-test'));
  const globalBatch=await Promise.all(Array.from({length:10},(_,i)=>second.fetch('https://quota/reserve',{method:'POST',body:JSON.stringify({principal:i.toString(16).padStart(64,'0'),tier:'trial',globalLimit:1})})));
  assert.equal(globalBatch.filter(r=>r.status===200).length,1);
  console.log('Real SQLite Durable Object: exactly 1 of 10 distinct principals reserved the last global slot.');
  await mf.dispose();
  mf=new Miniflare(options);
  const restored=await mf.getDurableObjectNamespace('QUOTA_LEDGER');
  const persisted=await restored.get(restored.idFromName('test-tier')).fetch('https://quota/reserve',{
   method:'POST',body:JSON.stringify({principal,tier:'trial',globalLimit:300}),
  });
  assert.equal(persisted.status,429);
  console.log('Real SQLite Durable Object: reservations survive runtime restart.');
 } finally { await mf.dispose(); rmSync(build,{recursive:true,force:true}); }
})().catch(error=>{console.error(error);process.exitCode=1;});
