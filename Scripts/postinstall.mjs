#!/usr/bin/env node
import { spawnSync } from "node:child_process";

if (process.env.SKIP_FFMPEG_POSTINSTALL === "1") {
  console.log("[postinstall] Skip requested by SKIP_FFMPEG_POSTINSTALL=1");
  process.exit(0);
}

if (process.platform !== "darwin") {
  console.log("[postinstall] Non-macOS detected, skipping FFmpeg local build.");
  process.exit(0);
}

console.log("[postinstall] macOS detected, preparing FFmpeg artifacts...");
const result = spawnSync("bash", ["./Scripts/build_ffmpeg_libs.sh"], {
  stdio: "inherit",
  cwd: process.cwd(),
});

if (result.status !== 0) {
  process.exit(result.status ?? 1);
}

console.log("[postinstall] FFmpeg artifacts are ready.");
