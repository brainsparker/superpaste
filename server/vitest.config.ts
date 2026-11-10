import { defineConfig } from 'vitest/config';

export default defineConfig({
  test: {
    include: ['tests/**/*.test.ts'],
    // Request tests drive the production handler with stubbed bindings.
    // test:quota-runtime separately exercises the real Worker and SQLite runtime.
  },
});