import { defineConfig } from '@playwright/test';

export default defineConfig({
  testDir: './e2e',
  use: {
    baseURL: process.env.CI ? 'http://localhost:80' : 'http://localhost:5173',
},
});