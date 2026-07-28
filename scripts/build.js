const fs = require("fs");
const path = require("path");

const rootDir = path.resolve(__dirname, "..");
const srcDir = path.join(rootDir, "src");
const sourceHtml = path.join(srcDir, "fu-bookkeeping.html");
const distDir = path.join(rootDir, "dist");
const outputHtml = path.join(distDir, "index.html");

const BRIDGE_START = "<!-- FU-Bookkeeping Mobile Bridge (Capacitor) -->";
const BRIDGE_END = "<!-- /FU-Bookkeeping Mobile Bridge (Capacitor) -->";

const bridge = `
${BRIDGE_START}
<script>
(function(){
  const isCap = !!(
    window.Capacitor &&
    window.Capacitor.isNativePlatform &&
    window.Capacitor.isNativePlatform()
  );

  window.FU_MOBILE = {
    isNative: () => isCap,

    openWorkspace: async () => {
      if (!isCap) {
        alert("Open workspace is available in the mobile app only.");
        return null;
      }

      const plugin = window.Capacitor?.Plugins?.WorkspaceFile;
      if (!plugin) {
        throw new Error("WorkspaceFile native plugin is not available.");
      }

      return await plugin.openFile();
    },

    saveWorkspace: async (jsonString) => {
      if (!isCap) {
        alert("Save workspace is available in the mobile app only.");
        return null;
      }

      const plugin = window.Capacitor?.Plugins?.WorkspaceFile;
      if (!plugin) {
        throw new Error("WorkspaceFile native plugin is not available.");
      }

      return await plugin.saveFile({ json: String(jsonString ?? "") });
    },

    saveWorkspaceAs: async (jsonString) => {
      if (!isCap) {
        alert("Save As is available in the mobile app only.");
        return null;
      }

      const plugin = window.Capacitor?.Plugins?.WorkspaceFile;
      if (!plugin) {
        throw new Error("WorkspaceFile native plugin is not available.");
      }

      return await plugin.saveAs({ json: String(jsonString ?? "") });
    }
  };
})();
</script>
${BRIDGE_END}
`.trim();

function fail(message) {
  console.error(`[build] ERROR: ${message}`);
  process.exitCode = 1;
  throw new Error(message);
}

function copyDirectoryContents(source, destination, copiedFiles) {
  for (const entry of fs.readdirSync(source, { withFileTypes: true })) {
    if (entry.name === "fu-bookkeeping.html") {
      continue;
    }

    const sourcePath = path.join(source, entry.name);
    const destinationPath = path.join(destination, entry.name);

    if (entry.isDirectory()) {
      fs.mkdirSync(destinationPath, { recursive: true });
      copyDirectoryContents(sourcePath, destinationPath, copiedFiles);
      continue;
    }

    if (entry.isFile()) {
      fs.mkdirSync(path.dirname(destinationPath), { recursive: true });
      fs.copyFileSync(sourcePath, destinationPath);
      copiedFiles.push(path.relative(rootDir, destinationPath));
    }
  }
}

function removeExistingBridge(html) {
  const escapedStart = BRIDGE_START.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
  const escapedEnd = BRIDGE_END.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");

  const completeBridgePattern = new RegExp(
    `${escapedStart}[\\s\\S]*?${escapedEnd}\\s*`,
    "g"
  );

  return html.replace(completeBridgePattern, "");
}

function injectBridge(html) {
  const cleanHtml = removeExistingBridge(html);

  if (cleanHtml.includes("</head>")) {
    return cleanHtml.replace("</head>", `${bridge}\n</head>`);
  }

  return `${bridge}\n${cleanHtml}`;
}

function main() {
  if (!fs.existsSync(srcDir)) {
    fail(`Source directory is missing: ${srcDir}`);
  }

  if (!fs.existsSync(sourceHtml)) {
    fail(`Required source HTML is missing: ${sourceHtml}`);
  }

  const sourceStats = fs.statSync(sourceHtml);
  if (!sourceStats.isFile() || sourceStats.size === 0) {
    fail(`Source HTML is empty or invalid: ${sourceHtml}`);
  }

  fs.rmSync(distDir, { recursive: true, force: true });
  fs.mkdirSync(distDir, { recursive: true });

  const copiedFiles = [];
  copyDirectoryContents(srcDir, distDir, copiedFiles);

  const html = fs.readFileSync(sourceHtml, "utf8");
  const builtHtml = injectBridge(html);

  fs.writeFileSync(outputHtml, builtHtml, "utf8");

  const bridgeCount = builtHtml.split(BRIDGE_START).length - 1;
  if (bridgeCount !== 1) {
    fail(`Mobile bridge was injected ${bridgeCount} times; expected exactly once.`);
  }

  console.log("[build] Web build completed");
  console.log(`[build] HTML: ${path.relative(rootDir, outputHtml)}`);
  console.log(`[build] Assets copied: ${copiedFiles.length}`);

  for (const file of copiedFiles) {
    console.log(`[build]   ${file}`);
  }
}

try {
  main();
} catch (error) {
  if (!process.exitCode) {
    process.exitCode = 1;
  }

  console.error(error instanceof Error ? error.stack : error);
}
