// RMIT University Vietnam
// Course: COSC2767|COSC2805 Systems Deployment and Operations
// Semester: 2026B
// Assessment: Assignment 2
// Author: Le Nguyen Thanh Trung - 4123479
// Created date: 22/08/2026
// Last modified: 11/09/2026
// Acknowledgement: None

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
