/** Phrases are matched as normalized word sequences, including short entries. */
export function normalizePhrase(text: string): string {
    return text.normalize("NFKC").toLowerCase().replace(/[\u200b-\u200f\u202a-\u202e\u2060-\u2069\ufeff]/g, "")
        .replace(/[^\p{L}\p{N}]+/gu, " ").trim();
}
export function containsPhrase(text: string, phrase: string): boolean {
    const needle = normalizePhrase(phrase);
    return needle.length > 0 && ` ${normalizePhrase(text)} `.includes(` ${needle} `);
}
export function containsRequiredUrl(text: string, url: string): boolean {
    return (text.match(/https?:\/\/[^\s<>"']+/giu) ?? []).some(token => token === url || token.replace(/[),.!?;:\]]+$/, "") === url);
}
