import { generateKeyPair, exportJWK, SignJWT, type JWTPayload } from "jose";
export const issuer = "https://identity.example.test";
export const clientId = "superpaste-native-test";
export const authEnv = { TRIAL_OIDC_ISSUER: issuer, TRIAL_OIDC_CLIENT_ID: clientId };
const pair = await generateKeyPair("RS256");
const jwk = { ...await exportJWK(pair.publicKey), kid: "test-key", alg: "RS256", use: "sig" };
export async function accountToken(overrides: JWTPayload = {}) {
  return new SignJWT({ email: "person@example.test", email_verified: true, nonce: "test-nonce-at-least-16", ...overrides })
    .setProtectedHeader({ alg: "RS256", kid: "test-key" })
    .setIssuer(typeof overrides.iss === "string" ? overrides.iss : issuer)
    .setAudience(overrides.aud ?? clientId).setSubject(overrides.sub ?? "account-one")
    .setIssuedAt(typeof overrides.iat === "number" ? overrides.iat : Math.floor(Date.now()/1000))
    .setExpirationTime(overrides.exp ?? Math.floor(Date.now()/1000)+3600).sign(pair.privateKey);
}
export const token = await accountToken();
export async function accountPrincipal(sub = "account-one") {
  const digest = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(`verified-account-v1\0${issuer}\0${sub}`));
  return [...new Uint8Array(digest)].map(b => b.toString(16).padStart(2,"0")).join("");
}
export function identityResponse(url: string | URL | Request): Response | undefined {
  const value = url instanceof Request ? url.url : String(url);
  if (value === issuer+"/.well-known/openid-configuration") return Response.json({ issuer, authorization_endpoint: issuer+"/authorize", token_endpoint: issuer+"/token", jwks_uri: issuer+"/jwks", scopes_supported: ["openid","email","offline_access"] });
  if (value === issuer+"/jwks") return Response.json({ keys: [jwk] });
}
export function withIdentity(handler: typeof fetch): typeof fetch {
  return ((url, init) => { const response = identityResponse(url); return response ? Promise.resolve(response) : handler(url, init); }) as typeof fetch;
}
export async function signClaims(claims: JWTPayload) {
  return new SignJWT(claims).setProtectedHeader({ alg: "RS256", kid: "test-key" }).sign(pair.privateKey);
}
