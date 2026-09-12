// Author: @danzelexp2713 (danzel)
// Last updated: 11/9/2026

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
