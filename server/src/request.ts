export class RequestError extends Error {
    constructor(readonly status: number, message: string) { super(message); }
}
/** Stops chunked and multibyte requests before they exceed the byte budget. */
export async function readJsonBody(request: Request, maxBytes: number, deadline = Date.now() + 35000): Promise<unknown> {
    const declared = Number(request.headers.get("Content-Length"));
    if (Number.isFinite(declared) && declared > maxBytes)
        throw new RequestError(413, "Request body is too large.");
    const reader = request.body?.getReader();
    if (!reader)
        throw new RequestError(400, "Body must be JSON.");
    const chunks: Uint8Array[] = [];
    let size = 0;
    try {
        for (;;) {
            let timer: ReturnType<typeof setTimeout> | undefined;
            const remaining = deadline - Date.now();
            if (remaining <= 0)
                throw new RequestError(408, "Request timed out.");
            const result = await Promise.race([reader.read(), new Promise<never>((_, reject) => {
                    timer = setTimeout(() => reject(new RequestError(408, "Request timed out.")), remaining);
                })]).finally(() => { if (timer !== undefined)
                clearTimeout(timer); });
            if (result.done)
                break;
            size += result.value.byteLength;
            if (size > maxBytes)
                throw new RequestError(413, "Request body is too large.");
            chunks.push(result.value);
        }
        const bytes = new Uint8Array(size);
        let offset = 0;
        for (const chunk of chunks) {
            bytes.set(chunk, offset);
            offset += chunk.byteLength;
        }
        try {
            return JSON.parse(new TextDecoder("utf-8", { fatal: true, ignoreBOM: false }).decode(bytes));
        }
        catch {
            throw new RequestError(400, "Body must be JSON.");
        }
    }
    catch (error) {
        void reader.cancel().catch(() => { });
        throw error;
    }
    finally {
        reader.releaseLock();
    }
}
/** Header/type/pixel checks bound decoding; the provider still verifies compressed pixels. */
export function validImage(data: string, mediaType: string): boolean {
    if (!data.length || data.length % 4 !== 0 || /[^A-Za-z0-9+/=]/.test(data))
        return false;
    let binary: string;
    try {
        binary = atob(data);
    }
    catch {
        return false;
    }
    const b = Uint8Array.from(binary, char => char.charCodeAt(0));
    const v = new DataView(b.buffer);
    const bounded = (w: number, h: number) => w > 0 && h > 0 && w <= 16384 && h <= 16384 && w * h <= 32000000;
    if (mediaType === "image/png")
        return b.length >= 33 && [137, 80, 78, 71, 13, 10, 26, 10].every((n, i) => b[i] === n)
            && v.getUint32(8) === 13 && binary.slice(12, 16) === "IHDR" && bounded(v.getUint32(16), v.getUint32(20));
    if (mediaType === "image/jpeg") {
        if (b.length < 12 || b[0] !== 255 || b[1] !== 216 || b[b.length - 2] !== 255 || b[b.length - 1] !== 217)
            return false;
        let offset = 2;
        while (offset + 8 < b.length) {
            if (b[offset++] !== 255)
                return false;
            while (b[offset] === 255)
                offset++;
            const marker = b[offset++]!;
            if (marker === 0xda || marker === 0xd9)
                return false;
            if (marker === 1 || (marker >= 0xd0 && marker <= 0xd7))
                continue;
            if (offset + 2 > b.length)
                return false;
            const length = v.getUint16(offset);
            if (length < 2 || offset + length > b.length)
                return false;
            if ([0xc0, 0xc1, 0xc2, 0xc3, 0xc5, 0xc6, 0xc7, 0xc9, 0xca, 0xcb, 0xcd, 0xce, 0xcf].includes(marker))
                return length >= 8 && bounded(v.getUint16(offset + 5), v.getUint16(offset + 3));
            offset += length;
        }
        return false;
    }
    if (mediaType === "image/webp") {
        if (b.length < 25 || binary.slice(0, 4) !== "RIFF" || binary.slice(8, 12) !== "WEBP" || v.getUint32(4, true) + 8 !== b.length)
            return false;
        const kind = binary.slice(12, 16);
        const u24 = (i: number) => b[i]! + (b[i + 1]! << 8) + (b[i + 2]! << 16);
        if (kind === "VP8X" && b.length >= 30)
            return bounded(u24(24) + 1, u24(27) + 1);
        if (kind === "VP8 " && b.length >= 30 && b[23] === 0x9d && b[24] === 1 && b[25] === 0x2a)
            return bounded(v.getUint16(26, true) & 0x3fff, v.getUint16(28, true) & 0x3fff);
        if (kind === "VP8L" && b[20] === 0x2f) {
            const bits = v.getUint32(21, true);
            return bounded((bits & 0x3fff) + 1, ((bits >>> 14) & 0x3fff) + 1);
        }
    }
    return false;
}
