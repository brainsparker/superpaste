const { Miniflare, Response: RuntimeResponse } = require('miniflare');
const { mkdtempSync, rmSync, readFileSync } = require('node:fs');
const { tmpdir } = require('node:os');
const { join, resolve } = require('node:path');
const { execFileSync } = require('node:child_process');
const assert = require('node:assert/strict');
(async()=>{
 const build=mkdtempSync(join(tmpdir(),'superpaste-sqlite-'));
 execFileSync(process.execPath,[resolve(__dirname,'../node_modules/wrangler/bin/wrangler.js'),'deploy','--dry-run','--outdir',build],{
   cwd:resolve(__dirname,'..'),env:{...process.env,WRANGLER_SEND_METRICS:'false',WRANGLER_LOG_PATH:join(build,'wrangler.log')},stdio:'pipe',
 });
 const {generateKeyPair,exportJWK,SignJWT}=await import('jose');
 const key=await generateKeyPair('RS256');
 const jwk={...await exportJWK(key.publicKey),kid:'runtime-key',alg:'RS256',use:'sig'};
 const issuer='https://identity.runtime.test', client='native-runtime';
 const jwt=verified=>new SignJWT({email:'runtime@example.test',email_verified:verified,nonce:'runtime-nonce-123456'})
  .setProtectedHeader({alg:'RS256',kid:'runtime-key'}).setIssuer(issuer).setAudience(client).setSubject('runtime-account')
  .setIssuedAt().setExpirationTime('1h').sign(key.privateKey);
 let inference=0;
 const json=value=>new RuntimeResponse(JSON.stringify(value),{headers:{'Content-Type':'application/json'}});
 const options={modules:true,modulesRoot:build,scriptPath:join(build,'index.js'),compatibilityDate:'2024-01-01',
   durableObjects:{QUOTA_LEDGER:{className:'QuotaLedger',useSQLite:true}},durableObjectsPersist:join(build,'state'),
   bindings:{TRIAL_OIDC_ISSUER:issuer,TRIAL_OIDC_CLIENT_ID:client,ANTHROPIC_API_KEY:'runtime-stub'},
   ratelimits:{IP_LIMITER:{simple:{limit:1000,period:60}},VALIDATE_LIMITER:{simple:{limit:1000,period:60}}},
   outboundService:async request=>{
    const url=new URL(request.url);
    if(url.origin===issuer&&url.pathname==='/.well-known/openid-configuration')return json({issuer,authorization_endpoint:issuer+'/authorize',token_endpoint:issuer+'/token',jwks_uri:issuer+'/jwks'});
    if(url.origin===issuer&&url.pathname==='/jwks')return json({keys:[jwk]});
    if(url.origin==='https://api.anthropic.com'){inference++;return json({content:[{type:'text',text:'runtime reply'}],stop_reason:'end_turn'});}
    throw new Error('Unexpected outbound request in isolated test: '+url.origin);
   },
 };
 let mf=new Miniflare(options);
 try {
  const png=readFileSync(resolve(__dirname,'image-fixtures.ts'),'utf8').match(/export const PNG = "([^"]+)"/)[1];
  const call=async(token,path='/v1/messages',body={image:{data:png,media_type:'image/png'}})=>mf.dispatchFetch('https://runtime.test'+path,{
   method:'POST',headers:{'Content-Type':'application/json',...(token?{Authorization:'Bearer '+token}:{})},body:JSON.stringify(body),
  });
  assert.equal((await call(null)).status,401);
  assert.equal((await call(await jwt(false))).status,403);
  assert.equal(inference,0);
  const token=await jwt(true);
  const verification=await call(token,'/v1/trial-auth/verify',{nonce:'runtime-nonce-123456'});
  assert.equal(verification.status,200,await verification.clone().text());
  assert.equal((await verification.json()).trial_expires_at,null);
  for(let i=0;i<15;i++){
   const response=await call(token);assert.equal(response.status,200,await response.clone().text());
   assert.ok(Number(response.headers.get('X-SuperPaste-Trial-Expires-At'))>Date.now());
  }
  assert.equal((await call(token)).status,429);assert.equal(inference,15);
  console.log('Real Worker: signed verified accounts pass, anonymous/unverified accounts fail, account trial permits exactly 15 model dispatches.');
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
