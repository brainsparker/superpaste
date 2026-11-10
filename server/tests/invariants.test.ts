import { test, expect, afterEach, vi } from "vitest";
import worker, { type Env } from "../src/index.ts";
import { validatePasteRequest } from "../src/paste.ts";
import { readJsonBody, validImage } from "../src/request.ts";
import { authEnv, token, accountPrincipal, withIdentity } from "./auth-fixture.ts";
import { quotaNamespace } from "./quota-harness.ts";
import { PNG, JPEG, WEBP } from "./image-fixtures.ts";
import { campaignFixture } from "./helpers.ts";
import { finalizeShareCopy } from "../src/smartshare/prompt.ts";
import { parseCampaignDraft } from "../src/smartshare/schema.ts";
const day=new Date().toISOString().slice(0,10);
const realFetch=globalThis.fetch;
afterEach(()=>{globalThis.fetch=realFetch;});
function environment(quota=quotaNamespace(), overrides:Partial<Env>={}) {
  const store=new Map<string,string>();
  return { ANTHROPIC_API_KEY:"stub", POLAR_ACCESS_TOKEN:"stub", POLAR_ORGANIZATION_ID:"stub",
    QUOTA_LEDGER:quota.namespace, ...authEnv,
    SUPERPASTE_KV:{get:async(k:string)=>store.get(k)??null,put:async(k:string,v:string)=>{store.set(k,v);}} as unknown as KVNamespace,
    IP_LIMITER:{limit:async()=>({success:true})},VALIDATE_LIMITER:{limit:async()=>({success:true})},...overrides } as Env;
}
function call(env:Env,device="device",license?:string,body:unknown={image:{data:PNG,media_type:"image/png"}},path="/v1/messages") {
  const headers:Record<string,string>={"Authorization":"Bearer "+token,"Content-Type":"application/json","CF-Connecting-IP":"192.0.2.10","X-Device-ID":device};
  if(license)headers["X-License-Key"]=license;
  return worker.fetch(new Request("https://test.example"+path,{method:"POST",headers,body:JSON.stringify(body)}),env,{} as ExecutionContext);
}
const success=()=>new Response(JSON.stringify({content:[{type:"text",text:"hello"}],stop_reason:"end_turn"}));

test("concurrent requests reserve only the last principal slot",async()=>{
  const principal=await accountPrincipal();
  const quota=quotaNamespace({[`usage:${day}:${principal}`]:14});
  let calls=0;globalThis.fetch=withIdentity(async()=>{calls++;return success();});
  const env=environment(quota);
  const results=await Promise.all(Array.from({length:10},(_,i)=>call(env,"rotated-"+i)));
  expect(results.filter(r=>r.status===200)).toHaveLength(1);
  expect(calls).toBe(1);expect(quota.store.get(`usage:${day}:${principal}`)).toBe(15);
});
test("concurrent distinct principals reserve only the last global slot",async()=>{
  const quota=quotaNamespace({[`global:${day}`]:299});
  const results=await Promise.all(Array.from({length:10},(_,i)=>quota.ledger.fetch(new Request("https://quota/reserve",{
    method:"POST",body:JSON.stringify({principal:i.toString(16).padStart(64,"0"),tier:"trial",globalLimit:300}),
  }))));
  expect(results.filter(r=>r.ok)).toHaveLength(1);expect(quota.store.get(`global:${day}`)).toBe(300);
});
test("rotating device IDs does not replenish account trials",async()=>{
  globalThis.fetch=withIdentity(async()=>success());const env=environment();
  for(let i=0;i<15;i++)expect((await call(env,"rotated-"+i)).status).toBe(200);
  expect((await call(env,"another-device")).status).toBe(429);
});
test("the same license shares quota across device IDs",async()=>{
  globalThis.fetch=withIdentity(async()=>success());const env=environment(undefined,{OWNER_LICENSE_KEY:"owner"});
  for(let i=0;i<100;i++)expect((await call(env,"rotated-"+i,"owner")).status).toBe(200);
  expect((await call(env,"new-device","owner")).status).toBe(429);
});
test("unknown keys cannot obtain outage grace",async()=>{
  let inference=0;globalThis.fetch=async(url)=>{if(String(url).includes("polar.sh"))return new Response("",{status:401});inference++;return success();};
  expect((await call(environment(),"d","unknown-key")).status).toBe(503);expect(inference).toBe(0);
});
test("a transport exception remains charged",async()=>{
  const quota=quotaNamespace();globalThis.fetch=withIdentity(async()=>{throw new Error("timeout after dispatch");});
  expect((await call(environment(quota))).status).toBe(502);expect(quota.store.get(`global:${day}`)).toBe(1);
});
test("trial expiry uses the verified account identity",async()=>{
  globalThis.fetch=withIdentity(async()=>success());
  const p=await accountPrincipal();
  expect((await call(environment(quotaNamespace({[`trial:${p}`]:Date.now()-8*86400_000})),"new-device")).status).toBe(402);
});
test("malformed license shapes are controlled 400s",async()=>{
  for(const body of [null,[],{key:42},{key:{}},{key:[]},{key:" "},{key:"x".repeat(513)}])expect((await call(environment(),"d",undefined,body,"/v1/validate-license")).status).toBe(400);
});
test("streamed multibyte bodies stop at the byte ceiling",async()=>{
  let cancelled=false;
  const stream=new ReadableStream({pull(c){c.enqueue(new TextEncoder().encode('"ééééé"'));},cancel(){cancelled=true;}});
  await expect(readJsonBody(new Request("https://test",{method:"POST",body:stream,duplex:"half"} as RequestInit),8)).rejects.toMatchObject({status:413});
  expect(cancelled).toBe(true);
});
test("all routes bound unknown fields before parsing",async()=>{
  const response=await call(environment(),"d",undefined,{key:"valid",unused:"x".repeat(5000)},"/v1/validate-license");
  expect(response.status).toBe(413);
});
test("real fixtures pass header validation, malformed and mislabeled images do not",()=>{
  expect(validImage(PNG,"image/png")).toBe(true);expect(validImage(JPEG,"image/jpeg")).toBe(true);expect(validImage(WEBP,"image/webp")).toBe(true);
  for(const data of ["AAAA","not base64",PNG.slice(1)])expect(validatePasteRequest({image:{data,media_type:"image/png"}}).ok).toBe(false);
  expect(validImage(PNG,"image/jpeg")).toBe(false);
});
test("final campaign output preserves exact facts and the actual URL",()=>{
  const c=campaignFixture({requiredFacts:["Costs $5 monthly"],requiredUrl:"https://example.com/launch",prohibitedClaims:[]});
  const out=finalizeShareCopy("Read https://example.com/launch-evil",c,"generic");
  expect(out.blocked).toBeNull();expect(out.text).toContain("Costs $5 monthly");expect(out.text).toContain("\n\nhttps://example.com/launch");
});
test("normalized short/spacing phrases and repaired contradictions are blocked",()=>{
  const base=campaignFixture({requiredFacts:[],requiredUrl:undefined});
  expect(finalizeShareCopy("It cures  cancer.",{...base,prohibitedClaims:["cures cancer"]},"generic").blocked).not.toBeNull();
  expect(finalizeShareCopy("Uses AI.",{...base,prohibitedClaims:["AI"]},"generic").blocked).not.toBeNull();
  expect(finalizeShareCopy("Hello",{...base,prohibitedClaims:["cures cancer"],requiredUrl:"https://example.com/cures-cancer"},"generic").blocked).not.toBeNull();
});
test("semantic constraints are rejected rather than truncated",()=>{
  for(const field of ["requiredFacts","prohibitedClaims"])expect(parseCampaignDraft({...campaignFixture(),[field]:["x".repeat(201)]}).ok).toBe(false);
});

test("license validation cannot consume the client's remaining inference budget",async()=>{
  const realNow=Date.now;
  let clock=realNow(), inference=0;
  Date.now=()=>clock;
  try {
    globalThis.fetch=async(url)=>{
      if(String(url).includes("polar.sh")){clock+=40_000;return new Response("{}",{status:200});}
      inference++;return success();
    };
    expect((await call(environment(),"d","valid-but-slow")).status).toBe(504);
    expect(inference).toBe(0);
  } finally { Date.now=realNow; }
});
test("only an already verified cached license survives a validation outage",async()=>{
  const env=environment();
  globalThis.fetch=async(url)=>String(url).includes("polar.sh")?new Response("{}",{status:200}):success();
  expect((await call(env,"d","known-license")).status).toBe(200);
  globalThis.fetch=async(url)=>{if(String(url).includes("polar.sh"))throw new Error("outage");return success();};
  expect((await call(env,"new-device","known-license")).status).toBe(200);
  expect((await call(env,"d","unverified-license")).status).toBe(503);
});
test("contradictory author constraints are rejected before generation",()=>{
  expect(parseCampaignDraft({...campaignFixture(),requiredFacts:["Uses AI"],prohibitedClaims:["AI"]}).ok).toBe(false);
});

test("a hung license store cannot outlive the whole request budget",async()=>{
  vi.useFakeTimers();
  try {
    const env=environment(undefined,{SUPERPASTE_KV:{get:()=>new Promise(()=>{})} as unknown as KVNamespace});
    const pending=call(env,"d","valid-shape");
    await vi.advanceTimersByTimeAsync(35_001);
    expect((await pending).status).toBe(504);
  } finally { vi.useRealTimers(); }
});
