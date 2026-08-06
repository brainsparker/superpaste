/**
 * Smart Share Links — campaign storage abstraction.
 *
 * Everything above this interface is storage-agnostic. The MVP provider keeps
 * the campaign inside the link itself, so the open-source build needs no
 * database and no hosted service to be fully functional.
 *
 * A hosted provider slots in later without touching schema, prompts, or UI:
 * implement `SmartShareCampaignProvider` against KV or an HTTP API, have
 * `createCampaign` mint a short opaque id, and pass the new instance where
 * `EncodedLinkCampaignProvider` is constructed in ./routes.ts. Callers only
 * know `getCampaign(id)` / `createCampaign(draft)`.
 */

import { buildShareLink, decodeCampaignToken, encodeCampaignToken } from "./codec.ts";
import {
  SMART_SHARE_SCHEMA_VERSION,
  SmartShareError,
  isCampaignExpired,
  type SmartShareCampaign,
  type SmartShareCampaignDraft,
} from "./schema.ts";

export interface SmartShareCampaignProvider {
  /** Resolve a campaign by id. Throws SmartShareError when unusable. */
  getCampaign(id: string): Promise<SmartShareCampaign>;
  /** Persist (or encode) a new campaign and return the stored form. */
  createCampaign(campaign: SmartShareCampaignDraft): Promise<SmartShareCampaign>;
  /** Shareable URL for a campaign this provider produced. */
  shareLinkFor(campaign: SmartShareCampaign, baseUrl: string): string;
}

/**
 * Local-first provider: the campaign travels inside the link, so the id *is*
 * the encoded payload. Stateless, nothing stored, nothing to expire server-side
 * beyond the campaign's own `expiresAt`.
 *
 * Tradeoff: a published link cannot be edited or revoked, because there is no
 * server-side record to change. Fixing that is what a hosted provider is for.
 */
export class EncodedLinkCampaignProvider implements SmartShareCampaignProvider {
  async getCampaign(id: string): Promise<SmartShareCampaign> {
    const decoded = decodeCampaignToken(id);
    if (!decoded.ok) {
      throw new SmartShareError(
        "invalid_link",
        "This Smart Share link isn't valid.",
        decoded.errors,
      );
    }
    if (isCampaignExpired(decoded.value)) {
      throw new SmartShareError("campaign_expired", "This Smart Share link has expired.");
    }
    return decoded.value;
  }

  async createCampaign(campaign: SmartShareCampaignDraft): Promise<SmartShareCampaign> {
    const createdAt = new Date().toISOString();
    const withMeta: SmartShareCampaign = {
      ...campaign,
      version: campaign.version || SMART_SHARE_SCHEMA_VERSION,
      createdAt,
      // Placeholder: the real id is the token, which needs createdAt to exist
      // first. Replaced immediately below.
      id: "",
    };
    // encodeCampaignToken throws SmartShareError("payload_too_large") when the
    // campaign cannot fit in a link.
    withMeta.id = encodeCampaignToken(withMeta);
    return withMeta;
  }

  shareLinkFor(campaign: SmartShareCampaign, baseUrl: string): string {
    return buildShareLink(campaign, baseUrl);
  }
}
