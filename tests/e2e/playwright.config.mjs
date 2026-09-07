import { defineConfig, devices } from "@playwright/test";
import path from "path";
import { fileURLToPath } from "url";

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

export default defineConfig({
  testDir: ".",
  timeout: 30000,
  retries: process.env.CI ? 2 : 0,
  reporter: [
    ["line"],
    [
      "html",
      {
        outputFolder: path.resolve(__dirname, "../../reports/e2e-html-report"),
        open: "never",
      },
    ],
    [
      "junit",
      { outputFile: path.resolve(__dirname, "../../reports/junit-e2e.xml") },
    ],
  ],
  use: {
    baseURL: process.env.TARGET_URL || "http://127.0.0.1",
    trace: "on-first-retry",
    screenshot: "only-on-failure",
    video: "retain-on-failure",
    launchOptions: {
      args: ["--no-sandbox", "--disable-dev-shm-usage"],
    },
  },
  projects: [{ name: "Chromium", use: { ...devices["Desktop Chrome"] } }],
});
