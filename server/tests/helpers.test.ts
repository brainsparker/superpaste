import { PNG, JPEG, WEBP } from './image-fixtures.ts';
import { describe, it, expect } from 'vitest';

import { UNCLEAR_SENTINEL, MAX_IMAGE_BASE64_CHARS, buildSystemPrompt, todayUTC, validatePasteRequest } from '../src/paste.ts';

// ─────────────────────────────────────────────────────
// Tests
// ─────────────────────────────────────────────────────

describe('buildSystemPrompt', () => {
  it('includes the SuperPaste identity and key terms', () => {
    const prompt = buildSystemPrompt({});
    expect(prompt).toContain('SuperPaste');
    expect(prompt).toContain('active-window context');
    expect(prompt).toContain(UNCLEAR_SENTINEL);
  });

  it('uses matchContext tone by default', () => {
    const prompt = buildSystemPrompt({});
    expect(prompt).toContain('Match the tone');
  });

  it('respects explicit tone', () => {
    const casual = buildSystemPrompt({ tone: 'casual' });
    const professional = buildSystemPrompt({ tone: 'professional' });
    expect(casual).not.toBe(professional);
    expect(casual).toContain('casual');
    expect(professional).toContain('professional');
  });

  it('falls back to matchContext for unknown tone', () => {
    const prompt = buildSystemPrompt({ tone: 'aggressive' });
    expect(prompt).toContain('Match the tone');
  });

  it('respects explicit length', () => {
    const concise = buildSystemPrompt({ length: 'concise' });
    const detailed = buildSystemPrompt({ length: 'detailed' });
    expect(concise).not.toBe(detailed);
    expect(concise).toContain("short");
    expect(detailed).toContain('thorough');
  });

  it('falls back to balanced for unknown length', () => {
    const prompt = buildSystemPrompt({ length: 'infinite' });
    expect(prompt).toContain('natural');
  });

  it('appends personal context when provided', () => {
    const prompt = buildSystemPrompt({ personal_context: 'I am a product manager at Acme.' });
    expect(prompt).toContain('product manager');
    expect(prompt).toContain('Acme');
  });

  it('omits personal context section when empty', () => {
    const withEmpty = buildSystemPrompt({ personal_context: '' });
    const withSpaces = buildSystemPrompt({ personal_context: '   ' });
    expect(withEmpty).toBe(withSpaces);
    expect(withEmpty).not.toContain('## About the user');
  });

  it('truncates personal context at 2000 chars', () => {
    const long = buildSystemPrompt({ personal_context: 'x'.repeat(3000) });
    // Should contain 2000 chars of context, not 3000
    const match = long.match(/## About the user\n(.+)/);
    expect(match).not.toBeNull();
    expect(match![1].length).toBe(2000);
  });

  it('output section mentions raw text', () => {
    const prompt = buildSystemPrompt({});
    expect(prompt).toContain('Raw text');
  });
});

describe('todayUTC', () => {
  it('returns YYYY-MM-DD format', () => {
    const today = todayUTC();
    expect(today).toMatch(/^\d{4}-\d{2}-\d{2}$/);
  });

  it('returns a valid date', () => {
    const today = todayUTC();
    const parsed = new Date(today);
    expect(parsed.toISOString().slice(0, 10)).toBe(today);
  });
});

describe('validatePasteRequest', () => {
  it('rejects non-object body', () => {
    expect(validatePasteRequest('hello').ok).toBe(false);
    expect(validatePasteRequest(null).ok).toBe(false);
    expect(validatePasteRequest(42).ok).toBe(false);
  });

  it('rejects missing image', () => {
    expect(validatePasteRequest({}).ok).toBe(false);
  });

  it('rejects unsupported media type', () => {
    const result = validatePasteRequest({
      image: { data: 'abc123', media_type: 'image/gif' },
    });
    expect(result.ok).toBe(false);
    if (!result.ok) expect(result.error).toContain('unsupported');
  });

  it('rejects empty image data', () => {
    const result = validatePasteRequest({
      image: { data: '', media_type: 'image/jpeg' },
    });
    expect(result.ok).toBe(false);
  });

  it('rejects oversized image data', () => {
    const large = 'a'.repeat(MAX_IMAGE_BASE64_CHARS + 1);
    const result = validatePasteRequest({
      image: { data: large, media_type: 'image/jpeg' },
    });
    expect(result.ok).toBe(false);
  });

  it('rejects non-string metadata fields', () => {
    const result = validatePasteRequest({
      image: { data: JPEG, media_type: 'image/jpeg' },
      app_name: 42,
    });
    expect(result.ok).toBe(false);
  });

  it('accepts valid minimal request', () => {
    const result = validatePasteRequest({
      image: { data: JPEG, media_type: 'image/jpeg' },
    });
    expect(result.ok).toBe(true);
    if (result.ok) {
      expect(result.req.image.data).toBe(JPEG);
      expect(result.req.image.media_type).toBe('image/jpeg');
    }
  });

  it('accepts valid full request', () => {
    const result = validatePasteRequest({
      image: { data: PNG, media_type: 'image/png' },
      app_name: 'Mail',
      window_title: 'Inbox',
      tone: 'professional',
      length: 'concise',
      personal_context: 'I am a lawyer.',
    });
    expect(result.ok).toBe(true);
    if (result.ok) {
      expect(result.req.app_name).toBe('Mail');
      expect(result.req.window_title).toBe('Inbox');
      expect(result.req.tone).toBe('professional');
      expect(result.req.length).toBe('concise');
      expect(result.req.personal_context).toBe('I am a lawyer.');
    }
  });

  it('truncates long app_name and window_title', () => {
    const longString = 'x'.repeat(500);
    const result = validatePasteRequest({
      image: { data: JPEG, media_type: 'image/jpeg' },
      app_name: longString,
      window_title: longString,
    });
    expect(result.ok).toBe(true);
    if (result.ok) {
      expect(result.req.app_name?.length).toBe(200);
      expect(result.req.window_title?.length).toBe(200);
    }
  });

  it('accepts webp images', () => {
    const result = validatePasteRequest({
      image: { data: WEBP, media_type: 'image/webp' },
    });
    expect(result.ok).toBe(true);
  });
});
import { textBlocksOnly } from '../src/paste.ts';

describe('textBlocksOnly', () => {
  it('drops thinking blocks so content[0] is text', () => {
    const body = JSON.stringify({
      content: [
        { type: 'thinking', thinking: '' },
        { type: 'text', text: 'hello' },
      ],
      stop_reason: 'end_turn',
    });
    const out = JSON.parse(textBlocksOnly(body, true));
    expect(out.content).toEqual([{ type: 'text', text: 'hello' }]);
    expect(out.stop_reason).toBe('end_turn');
  });

  it('passes error and non-JSON bodies through unchanged', () => {
    expect(textBlocksOnly('{"error":{}}', false)).toBe('{"error":{}}');
    expect(textBlocksOnly('not json', true)).toBe('not json');
  });
});
