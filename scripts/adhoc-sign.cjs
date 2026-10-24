// electron-builder afterSign hook: re-signs Pulso.app ad-hoc, after the fuses are set and before the dmg.
// Renaming Electron breaks its signature, and a broken one reads as "damaged" once
// downloaded. Remove this hook once the app is signed with a Developer ID.
const { execFileSync } = require("node:child_process");
const { join } = require("node:path");

exports.default = async function adhocSign(context) {
  if (context.electronPlatformName !== "darwin") return;
  const app = join(context.appOutDir, `${context.packager.appInfo.productFilename}.app`);
  execFileSync("codesign", ["--force", "--deep", "--sign", "-", app], { stdio: "inherit" });
  execFileSync("codesign", ["--verify", "--deep", "--strict", app], { stdio: "inherit" });
};
