import { createLocalJWKSet, errors, jwtVerify, type JSONWebKeySet } from "jose";
import { readJsonBody } from "./request.ts";

export interface TrialAuthEnv {
  TRIAL_OIDC_ISSUER?: string;
  TRIAL_OIDC_CLIENT_ID?: string;
}
export class TrialAuthError extends Error {
  constructor(readonly status: number, readonly code: string, message: string) { super(message); }
}
interface Metadata {
  issuer: string;
  authorization_endpoint: string;
  token_endpoint: string;
  jwks_uri: string;
  scopes_supported?: string[];
}
interface Cached<T> { value: T; loaded: number }
const metadataCache = new Map<string, Cached<Metadata>>();
const keysCache = new Map<string, Cached<JSONWebKeySet>>();
const CACHE_MS = 300_000;
const unavailable = () => new TrialAuthError(503, "trial_auth_unavailable", "Trial sign-in is unavailable. Try again later.");

function httpsUrl(value: unknown): string {
  if (typeof value !== "string") throw unavailable();
  const url = new URL(value);
  if (url.protocol !== "https:" || url.username || url.password || url.hash || url.search) throw unavailable();
  return value;
}
function settings(env: TrialAuthEnv): { issuer: string; clientId: string } {
  try {
    const issuer = httpsUrl(env.TRIAL_OIDC_ISSUER);
    const clientId = env.TRIAL_OIDC_CLIENT_ID;
    if (!clientId || clientId.length > 256 || /\s/.test(clientId)) throw unavailable();
    return { issuer, clientId };
  } catch { throw unavailable(); }
}
async function providerJson(url: string, deadline: number): Promise<unknown> {
  if (Date.now() >= deadline) throw unavailable();
  try {
    const response = await fetch(url, { redirect: "manual", signal: AbortSignal.timeout(Math.max(1, Math.min(5000, deadline-Date.now()))) });
    if (!response.ok) throw unavailable();
    return await readJsonBody(new Request("https://identity.internal/json", { method: "POST", body: response.body, duplex: "half" } as RequestInit), 64*1024, deadline);
  } catch { throw unavailable(); }
}
async function metadata(env: TrialAuthEnv, deadline: number): Promise<Metadata> {
  const config = settings(env);
  const cached = metadataCache.get(config.issuer);
  if (cached && Date.now()-cached.loaded < CACHE_MS) return cached.value;
  const value = await providerJson(config.issuer.replace(/\/$/, "")+"/.well-known/openid-configuration", deadline) as Metadata;
  try {
    if (!value || value.issuer !== config.issuer) throw unavailable();
    if (value.scopes_supported !== undefined && (!Array.isArray(value.scopes_supported) || !value.scopes_supported.every(s => typeof s === "string"))) throw unavailable();
    httpsUrl(value.authorization_endpoint); httpsUrl(value.token_endpoint); httpsUrl(value.jwks_uri);
    metadataCache.set(config.issuer, { value, loaded: Date.now() });
    return value;
  } catch { throw unavailable(); }
}
async function keys(url: string, deadline: number, refresh = false): Promise<JSONWebKeySet> {
  const cached = keysCache.get(url);
  if (cached && Date.now()-cached.loaded < CACHE_MS && (!refresh || Date.now()-cached.loaded < 30_000)) return cached.value;
  const value = await providerJson(url, deadline) as JSONWebKeySet;
  if (!value || !Array.isArray(value.keys) || !value.keys.length || value.keys.length > 64) throw unavailable();
  keysCache.set(url, { value, loaded: Date.now() });
  return value;
}

export async function publicTrialAuthConfig(env: TrialAuthEnv, development: boolean, deadline: number) {
  const config = settings(env);
  const provider = await metadata(env, deadline);
  const offline = provider.scopes_supported?.includes("offline_access") === true;
  return {
    issuer: config.issuer, client_id: config.clientId,
    authorization_endpoint: provider.authorization_endpoint, token_endpoint: provider.token_endpoint,
    redirect_uri: development ? "com.superpaste.app.dev:/oauth/callback" : "com.superpaste.app:/oauth/callback",
    scope: "openid email" + (offline ? " offline_access" : ""),
  };
}

export async function verifiedTrialAccount(request: Request, env: TrialAuthEnv, deadline: number, expectedNonce?: string) {
  const authorization = request.headers.get("Authorization");
  if (!authorization || !/^Bearer [A-Za-z0-9_.-]+$/.test(authorization) || authorization.length > 16_384) {
    throw new TrialAuthError(401, "trial_sign_in_required", "Sign in with a verified account to use the free trial.");
  }
  const token = authorization.slice(7);
  const config = settings(env);
  const provider = await metadata(env, deadline);
  let keyset = await keys(provider.jwks_uri, deadline);
  const options = { issuer: config.issuer, audience: config.clientId, algorithms: ["RS256", "ES256"], requiredClaims: ["sub", "iat", "exp", "email", "email_verified"] };
  try {
    let result;
    try { result = await jwtVerify(token, createLocalJWKSet(keyset), options); }
    catch (error) {
      if (!(error instanceof errors.JWKSNoMatchingKey)) throw error;
      keyset = await keys(provider.jwks_uri, deadline, true);
      result = await jwtVerify(token, createLocalJWKSet(keyset), options);
    }
    const claims = result.payload;
    const now = Date.now()/1000;
    if (typeof claims.sub !== "string" || !claims.sub.length || claims.sub.length > 255
      || typeof claims.iat !== "number" || !Number.isFinite(claims.iat) || claims.iat > now+60
      || typeof claims.exp !== "number" || claims.exp <= now
      || (claims.azp !== undefined && claims.azp !== config.clientId)
      || (Array.isArray(claims.aud) && claims.aud.length > 1 && claims.azp !== config.clientId)
      || (expectedNonce !== undefined && claims.nonce !== expectedNonce)) throw new Error("Invalid account claims");
    if (claims.email_verified !== true || typeof claims.email !== "string" || claims.email.length > 320
      || !claims.email.includes("@") || /\s/.test(claims.email)) {
      throw new TrialAuthError(403, "trial_email_unverified", "Verify your email with the sign-in provider, then sign in again.");
    }
    const identity = new TextEncoder().encode(`verified-account-v1\0${config.issuer}\0${claims.sub}`);
    const digest = await crypto.subtle.digest("SHA-256", identity);
    const principal = [...new Uint8Array(digest)].map(b => b.toString(16).padStart(2, "0")).join("");
    return { principal, email: claims.email, tokenExpiresAt: claims.exp*1000 };
  } catch (error) {
    if (error instanceof TrialAuthError) throw error;
    throw new TrialAuthError(401, "trial_session_invalid", "Your trial sign-in has expired or could not be verified. Sign in again.");
  }
}
