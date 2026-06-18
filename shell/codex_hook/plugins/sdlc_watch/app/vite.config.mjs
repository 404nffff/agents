import { defineConfig } from "vite";
import react from "@vitejs/plugin-react";
import tailwindcss from "@tailwindcss/vite";

export default defineConfig({
  root: import.meta.dirname,
  base: "./",
  plugins: [react(), tailwindcss()],
  build: {
    outDir: "dist",
    emptyOutDir: true,
    rollupOptions: {
      output: {
        manualChunks(id) {
          if (id.includes("node_modules/@mui") || id.includes("node_modules/@emotion")) return "mui";
          if (id.includes("node_modules/react") || id.includes("node_modules/react-dom")) return "react";
          if (id.includes("node_modules/gsap")) return "gsap";
          return undefined;
        },
      },
    },
  },
  server: {
    host: "127.0.0.1",
    port: 5178,
    strictPort: false,
  },
});
