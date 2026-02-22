#!/usr/bin/env node
import { spawnSync } from "node:child_process";

const args = process.argv.slice(2);
const target = (args[0] || "tauri").toLowerCase();
const dryRun = args.includes("--dry-run");
const platform = process.platform;

const run = (command) => {
  if (dryRun) {
    console.log(`[dry-run] ${command}`);
    return;
  }
  const result = spawnSync(command, {
    stdio: "inherit",
    shell: true,
  });
  if (result.status !== 0) {
    process.exit(result.status ?? 1);
  }
};

const usage = () => {
  console.log("Usage: node Scripts/build_target.mjs [tauri|swiftui|all] [--dry-run]");
};

if (!["tauri", "swiftui", "all"].includes(target)) {
  usage();
  process.exit(2);
}

if (target === "tauri") {
  run("pnpm tauri:build");
  process.exit(0);
}

if (target === "swiftui") {
  if (platform !== "darwin") {
    console.error("SwiftUI build is only supported on macOS.");
    process.exit(1);
  }
  run("bash ./Scripts/swiftui_build.sh");
  process.exit(0);
}

if (platform === "darwin") {
  run("pnpm tauri:build");
  run("bash ./Scripts/swiftui_build.sh");
} else {
  console.log("Non-macOS detected; 'all' resolves to tauri only.");
  run("pnpm tauri:build");
}
