import { afterEach, expect, test } from "vitest";
import { generateKeyPair, SignJWT } from "jose";
import worker, { type Env } from "../src/index.ts";
import { publicTrialAuthConfig, verifiedTrialAccount } from "../src/trial-auth.ts";
import { accountToken, accountPrincipal, authEnv, clientId, issuer, signClaims, token, withIdentity } from "./auth-fixture.ts";
import { quotaNamespace } from "./quota-harness.ts";
import { PNG } from "./image-fixtures.ts";
const originalFetch = globalThis.fetch;
afterEach(() => { globalThis.fetch = originalFetch; });
const deadline = () => Date.now()+10_000;
const authorized = (jwt = token) => new Request("https://api.example/v1/messages", { headers: { Authorization: "Bearer "+jwt } });
function setup() {
  const quota = quotaNamespace(); let models = 0;
  globalThis.fetch = withIdentity(async () => { models++; return Response.json({ content: [{type:"text",text:"hello"}],stop_reason:"end_turn" }); });
  const env = { ...authEnv, POLAR_ACCESS_TOKEN: "stub", POLAR_ORGANIZATION_ID: "stub", SUPERPASTE_KV: {} as KVNamespace, ANTHROPIC_API_KEY: "stub", QUOTA_LEDGER: quota.namespace,
    IP_LIMITER: { limit: async()=>({success:true}) }, VALIDATE_LIMITER: { limit: async()=>({success:true}) } } as Env;
  const call = (jwt: string | null, ip = "192.0.2.1", path = "/v1/messages", body: unknown = { image: {data:PNG,media_type:"image/png"} }, license?: string) => {
    const headers: Record<string,string> = { "Content-Type":"application/json","CF-Connecting-IP":ip,"X-Device-ID":crypto.randomUUID() };
    if (jwt !== null) headers.Authorization = "Bearer "+jwt;
    if (license) headers["X-License-Key"] = license;
    return worker.fetch(new Request("https://api.example"+path, {method:"POST",headers,body:JSON.stringify(body)}), env, {} as ExecutionContext);
  };
  return { env, quota, call, models:()=>models };
}
test("verified account identity uses issuer and subject, never email or IP", async () => {
  setup();
  const first = await verifiedTrialAccount(authorized(), authEnv, deadline());
  const renamed = await verifiedTrialAccount(authorized(await accountToken({email:"new@example.test"})), authEnv, deadline());
  expect(first.principal).toBe(await accountPrincipal()); expect(renamed.principal).toBe(first.principal);
  expect(first.principal).toMatch(/^[a-f0-9]{64}$/);
  expect((await verifiedTrialAccount(authorized(await accountToken({sub:"another-account"})), authEnv, deadline())).principal).not.toBe(first.principal);
});
const badClaims: Array<[string, Record<string, unknown>, number]> = [
  ["unverified email",{email_verified:false},403], ["string verification flag",{email_verified:"true"},403],
  ["invalid email",{email:"not-an-email"},403], ["wrong issuer",{iss:"https://attacker.test"},401],
  ["wrong audience",{aud:"another-client"},401], ["expired token",{exp:1},401],
  ["not yet valid",{nbf:4_000_000_000},401], ["future issuance",{iat:4_000_000_000},401],
  ["empty subject",{sub:""},401], ["wrong authorized party",{azp:"another-client"},401],
  ["ambiguous multiple audiences",{aud:[clientId,"another-client"]},401],
];
for (const [name, claims, status] of badClaims) test("rejects "+name+" without model dispatch or quota writes", async () => {
  const h = setup();
  expect((await h.call(await accountToken(claims))).status).toBe(status);
  expect(h.models()).toBe(0); expect(h.quota.store.size).toBe(0);
});
for (const field of ["sub","iat","exp","email","email_verified"]) test("requires signed "+field+" claim", async () => {
  setup(); const now = Math.floor(Date.now()/1000);
  const claims: Record<string,unknown> = {iss:issuer,aud:clientId,sub:"account-one",iat:now,exp:now+3600,email:"person@example.test",email_verified:true};
  delete claims[field];
  await expect(verifiedTrialAccount(authorized(await signClaims(claims)), authEnv, deadline())).rejects.toMatchObject({status:401});
});
test("forged signatures and unsigned tokens never establish a trial", async () => {
  const h = setup(); const pair = await generateKeyPair("RS256");
  const forged = await new SignJWT({email:"person@example.test",email_verified:true}).setProtectedHeader({alg:"RS256",kid:"test-key"})
    .setIssuer(issuer).setAudience(clientId).setSubject("account-one").setIssuedAt().setExpirationTime("1h").sign(pair.privateKey);
  for (const jwt of [forged,"eyJhbGciOiJub25lIn0.eyJzdWIiOiJhIn0.","malformed"]) expect((await h.call(jwt)).status).toBe(401);
  expect(h.models()).toBe(0); expect(h.quota.store.size).toBe(0);
});
test("anonymous device IDs cannot start trials", async () => {
  const h = setup(); expect((await h.call(null)).status).toBe(401);
  expect(h.models()).toBe(0); expect(h.quota.store.size).toBe(0);
});
test("same account shares quota across networks, separate accounts on one network do not share", async () => {
  const h = setup();
  for (let i=0;i<15;i++) expect((await h.call(token,"192.0.2."+(i+1))).status).toBe(200);
  expect((await h.call(token,"198.51.100.1")).status).toBe(429);
  expect((await h.call(await accountToken({sub:"account-two"}),"192.0.2.1")).status).toBe(200);
  expect(h.models()).toBe(16);
  expect([...h.quota.store.keys()].some(k=>k.includes("192.0.2") || k.includes("@"))).toBe(false);
});
test("sign-in verifies nonce and reports trial state without starting or charging it", async () => {
  const h = setup();
  const verification = await h.call(token,"192.0.2.1","/v1/trial-auth/verify",{nonce:"test-nonce-at-least-16"});
  expect(verification.status).toBe(200); expect(verification.headers.get("Cache-Control")).toBe("no-store"); expect(await verification.json()).toMatchObject({verified:true,email:"person@example.test",trial_expires_at:null});
  expect(h.quota.store.size).toBe(0); expect(h.models()).toBe(0);
  expect((await h.call(token,"192.0.2.1","/v1/trial-auth/verify",{nonce:"different-nonce-at-least-16"})).status).toBe(401);
  const first = await h.call(token); expect(first.status).toBe(200);
  const start = h.quota.store.get("trial:"+await accountPrincipal()) as number;
  expect(Number(first.headers.get("X-SuperPaste-Trial-Expires-At"))).toBe(start+7*86400_000);
  const again = await h.call(token,"192.0.2.1","/v1/trial-auth/verify",{});
  expect(await again.json()).toMatchObject({trial_expires_at:start+7*86400_000});
  expect(h.models()).toBe(1);
});
test("expired account trials cannot restart on a new network", async () => {
  const h = setup(); h.quota.store.set("trial:"+await accountPrincipal(),Date.now()-8*86400_000);
  expect((await h.call(token,"198.51.100.200")).status).toBe(402); expect(h.models()).toBe(0);
});
test("public configuration returns exact registered native callbacks and PKCE scopes", async () => {
  setup();
  expect(await publicTrialAuthConfig(authEnv,false,deadline())).toMatchObject({client_id:clientId,redirect_uri:"com.superpaste.app:/oauth/callback",scope:"openid email offline_access"});
  expect((await publicTrialAuthConfig(authEnv,true,deadline())).redirect_uri).toBe("com.superpaste.app.dev:/oauth/callback");
});
test("missing operator configuration fails closed", async () => {
  const h = setup(); delete h.env.TRIAL_OIDC_CLIENT_ID;
  expect((await h.call(token)).status).toBe(503); expect(h.models()).toBe(0); expect(h.quota.store.size).toBe(0);
});
test("valid licenses remain independent of trial accounts", async () => {
  const h = setup(); h.env.OWNER_LICENSE_KEY = "owner"; delete h.env.TRIAL_OIDC_CLIENT_ID;
  expect((await h.call(null,"192.0.2.1","/v1/messages",undefined,"owner")).status).toBe(200); expect(h.models()).toBe(1);
});
test("identity metadata is bounded and must match the configured issuer", async () => {
  const other = {TRIAL_OIDC_ISSUER:"https://bad-identity.example.test",TRIAL_OIDC_CLIENT_ID:clientId};
  globalThis.fetch = async()=>Response.json({issuer:"https://attacker.example.test"});
  await expect(publicTrialAuthConfig(other,false,deadline())).rejects.toMatchObject({status:503});
  globalThis.fetch = async()=>new Response("x".repeat(65_537));
  await expect(publicTrialAuthConfig(other,false,deadline())).rejects.toMatchObject({status:503});
});

test("identity metadata redirects are refused in the Worker-compatible manual mode", async () => {
  globalThis.fetch = async(_url,init)=>{ expect(init?.redirect).toBe("manual"); return new Response(null,{status:302,headers:{Location:"https://attacker.test"}}); };
  await expect(publicTrialAuthConfig({TRIAL_OIDC_ISSUER:"https://redirect-identity.example.test",TRIAL_OIDC_CLIENT_ID:clientId},false,deadline())).rejects.toMatchObject({status:503});
});
