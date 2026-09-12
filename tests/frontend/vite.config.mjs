// RMIT University Vietnam
// Course: COSC2767|COSC2805 Systems Deployment and Operations
// Semester: 2026B
// Assessment: Assignment 2
// Author: Le Nguyen Thanh Trung - 4123479
// Created date: 22/08/2026
// Last modified: 11/09/2026
// Acknowledgement: None

import { defineConfig } from "vite";
import vue from "@vitejs/plugin-vue";
import path from "path";

const projectRoot = path.resolve(import.meta.dirname, "../../");

export default defineConfig({
  root: projectRoot,
  plugins: [vue()],
  resolve: {
    alias: {
      "@": path.resolve(import.meta.dirname, "../../app/client/src"),
      pinia: path.resolve(import.meta.dirname, "../../node_modules/pinia"),
      vue: path.resolve(import.meta.dirname, "../../node_modules/vue"),
    },
  },
  test: {
    globals: true,
    environment: "jsdom",
    include: ["tests/frontend/**/*.spec.js"],
    reporters: ["default", "junit"],
    outputFile: {
      junit: path.resolve(
        import.meta.dirname,
        "../../reports/junit-frontend.xml",
      ),
    },
    coverage: {
      provider: "v8",
      reporter: ["text", "json", "xml", "html"],
      reportsDirectory: path.resolve(
        import.meta.dirname,
        "../../reports/coverage-frontend",
      ),
    },
  },
});
