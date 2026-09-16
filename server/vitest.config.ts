import { defineConfig } from 'vitest/config';

export default defineConfig({
  test: {
    include: ['tests/**/*.test.ts'],
    // Workers integration tests would need @cloudflare/vitest-pool-workers;
    // these tests exercise pure logic only and don't need it.
  },
});