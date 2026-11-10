import { readJsonBody } from "./request.ts";
export interface Reservation {
    principal: string;
    tier: "trial" | "licensed";
    globalLimit: number;
    operation?: "reserve" | "status";
}
/** A coordinator per tier atomically owns principal and global capacity. */
export class QuotaLedger {
    constructor(private readonly state: DurableObjectState) { }
    async fetch(request: Request): Promise<Response> {
        const input = await readJsonBody(request, 2048) as Reservation;
        if (!input || !["trial", "licensed"].includes(input.tier) || !/^[a-f0-9]{64}$/.test(input.principal)
            || !Number.isSafeInteger(input.globalLimit) || input.globalLimit < 1
            || (input.operation !== undefined && !["reserve", "status"].includes(input.operation)))
            return Response.json({ error: "bad_reservation" }, { status: 400 });
        const now = Date.now(), day = new Date(now).toISOString().slice(0, 10);
        const limit = input.tier === "trial" ? 15 : 100;
        const result = await this.state.storage.transaction(async (txn) => {
            const firstKey = `trial:${input.principal}`;
            const first = input.tier === "trial" ? await txn.get<number>(firstKey) : undefined;
            const trialExpiresAt = first === undefined ? null : first + 7*86400_000;
            if (input.operation === "status") return { status: 200, trial_expires_at: trialExpiresAt };
            if (trialExpiresAt !== null && trialExpiresAt <= now)
                return { status: 402, error: "trial_expired", message: "Your 7-day free trial has ended.", trial_expires_at: trialExpiresAt };
            const globalKey = `global:${day}`, principalKey = `usage:${day}:${input.principal}`;
            const global = (await txn.get<number>(globalKey)) ?? 0, count = (await txn.get<number>(principalKey)) ?? 0;
            if (global >= input.globalLimit || count >= limit)
                return { status: 429, error: "rate_limited", message: "Daily limit reached. Resets at midnight UTC." };
            if (input.tier === "trial" && first === undefined)
                await txn.put(firstKey, now);
            await txn.put({ [globalKey]: global + 1, [principalKey]: count + 1 });
            return { status: 200, trial_expires_at: input.tier === "trial" ? (trialExpiresAt ?? now+7*86400_000) : null };
        });
        // Once reserved, failures remain charged: dispatch does not prove whether inference began.
        return Response.json(result, { status: result.status });
    }
}
