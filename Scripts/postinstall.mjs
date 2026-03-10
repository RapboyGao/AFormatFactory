#!/usr/bin/env node
import { spawnSync } from "node:child_process";

if (process.env.SKIP_FFMPEG_POSTINSTALL === "1") {
  console.log("[postinstall] Skip requested by SKIP_FFMPEG_POSTINSTALL=1");
  process.exit(0);
}

if (!["darwin", "linux", "win32"].includes(process.platform)) {
  console.log("[postinstall] Unsupported platform for auto build, skipping.");
  process.exit(0);
}

console.log(`[postinstall] ${process.platform} detected, preparing FFmpeg artifacts...`);
const result = spawnSync("bash", ["./Scripts/build_ffmpeg_libs.sh"], {
  stdio: "inherit",
  cwd: process.cwd(),
});

if (result.error && result.error.code === "ENOENT") {
  console.warn("[postinstall] bash not found. Install bash/MSYS2 and run ./Scripts/build_ffmpeg_libs.sh manually.");
  process.exit(0);
}

if (result.status !== 0) {
  process.exit(result.status ?? 1);
}

console.log("[postinstall] FFmpeg artifacts are ready.");
