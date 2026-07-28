const fs = require("fs");
const path = require("path");

const rootDir = path.resolve(__dirname, "..");
const distDir = path.join(rootDir, "dist");
const indexPath = path.join(distDir, "index.html");
const logoPath = path.join(distDir, "FU-BookKeeping.png");

const BRIDGE_MARKER = "<!-- FU-Bookkeeping Mobile Bridge (Capacitor) -->";
const PNG_SIGNATURE = Buffer.from([137, 80, 78, 71, 13, 10, 26, 10]);

const errors = [];

function addError(message) {
  errors.push(message);
}

function isIgnoredReference(reference) {
  const value = String(reference || "").trim().toLowerCase();

  if (!value) return true;

  return [
    "http:",
    "https:",
    "data:",
    "blob:",
    "#",
    "mailto:",
    "tel:",
    "javascript:"
  ].some((prefix) => value.startsWith(prefix));
}

function normalizeLocalReference(reference) {
  let value = String(reference || "").trim();

  value = value.split("#")[0];
  value = value.split("?")[0];
  value = decodeURIComponent(value);

  while (value.startsWith("./")) {
    value = value.slice(2);
  }

  if (value.startsWith("/")) {
    value = value.slice(1);
  }

  return value;
}

if (!fs.existsSync(indexPath)) {
  addError(`Missing file: ${indexPath}`);
} else {
  const stats = fs.statSync(indexPath);

  if (!stats.isFile() || stats.size === 0) {
    addError("dist/index.html exists but is empty.");
  }
}

let html = "";

if (fs.existsSync(indexPath)) {
  html = fs.readFileSync(indexPath, "utf8");

  if (!/const\s+APP_VERSION\s*=\s*["'][^"']+["']/.test(html)) {
    addError("APP_VERSION declaration was not found in dist/index.html.");
  }

  if (!/const\s+APP_SEMVER\s*=\s*["'][^"']+["']/.test(html)) {
    addError("APP_SEMVER declaration was not found in dist/index.html.");
  }

  const bridgeCount = html.split(BRIDGE_MARKER).length - 1;

  if (bridgeCount !== 1) {
    addError(`Mobile bridge marker occurs ${bridgeCount} times; expected exactly once.`);
  }

  const referencePattern = /\b(?:src|href)\s*=\s*["']([^"']+)["']/gi;
  const checkedReferences = new Set();

  let match;

  while ((match = referencePattern.exec(html)) !== null) {
    const originalReference = match[1];

    if (isIgnoredReference(originalReference)) {
      continue;
    }

    const localReference = normalizeLocalReference(originalReference);

    if (
      !localReference ||
      localReference.includes("${") ||
      localReference.includes("{{") ||
      localReference.includes("}}") ||
      localReference.includes("<%") ||
      localReference.includes("%>")
    ) {
      continue;
    }

    if (checkedReferences.has(localReference)) {
      continue;
    }

    checkedReferences.add(localReference);

    const resolvedPath = path.resolve(distDir, localReference);

    if (!resolvedPath.startsWith(`${distDir}${path.sep}`) && resolvedPath !== distDir) {
      addError(`Unsafe local reference outside dist: ${originalReference}`);
      continue;
    }

    if (!fs.existsSync(resolvedPath)) {
      addError(`Missing local asset referenced by HTML: ${originalReference}`);
    }
  }
}

if (!fs.existsSync(logoPath)) {
  addError(`Missing logo: ${logoPath}`);
} else {
  const logoStats = fs.statSync(logoPath);

  if (!logoStats.isFile() || logoStats.size < PNG_SIGNATURE.length) {
    addError("dist/FU-BookKeeping.png is empty or invalid.");
  } else {
    const handle = fs.openSync(logoPath, "r");
    const signature = Buffer.alloc(PNG_SIGNATURE.length);

    try {
      fs.readSync(handle, signature, 0, signature.length, 0);
    } finally {
      fs.closeSync(handle);
    }

    if (!signature.equals(PNG_SIGNATURE)) {
      addError("dist/FU-BookKeeping.png does not have a valid PNG signature.");
    }
  }
}

if (errors.length > 0) {
  console.error("[verify:web] Verification failed:");

  for (const error of errors) {
    console.error(`[verify:web] - ${error}`);
  }

  process.exit(1);
}

console.log("[verify:web] Verification passed");
console.log("[verify:web] dist/index.html: OK");
console.log("[verify:web] mobile bridge: exactly once");
console.log("[verify:web] APP_VERSION and APP_SEMVER: found");
console.log("[verify:web] FU-BookKeeping.png: valid PNG");
console.log("[verify:web] local asset references: OK");
