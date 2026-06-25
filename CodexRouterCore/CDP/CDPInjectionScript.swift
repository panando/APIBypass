// MARK: - Ported injection JavaScript for plugin entry unlock and force install

/// Name of the CDP binding used by the bridge. JS calls
/// `window.{bindingName}(JSON.stringify({id, path, payload}))` which is delivered
/// as a `Runtime.bindingCalled` event to the native side.
public let cdpBridgeBindingName = "codexSessionDeleteV2"

/// Installs the CDP binding bridge on the renderer.
///
/// Defines `window.__codexSessionDeleteBridge(path, payload)` returning a Promise
/// that resolves with the response body string (or rejects on HTTP error). The
/// bridge routes through a native CDP binding instead of `fetch()`, bypassing
/// Codex's `connect-src` CSP which blocks localhost requests from the page.
///
/// Installed via `Page.addScriptToEvaluateOnNewDocument` so it survives reloads,
/// and also `Runtime.evaluate`d once for the current page. Idempotent — uses `||`
/// guards so re-evaluation after a reload is a no-op.
public let cdpBridgeScript: String = """
(function() {
  if (window.__codexSessionDeleteBridge) return;
  window.__codexSessionDeleteIdCounter = 0;
  window.__codexSessionDeletePending = new Map();
  window.__codexSessionDeleteBridge = function(path, payload) {
    return new Promise(function(resolve, reject) {
      var id = ++window.__codexSessionDeleteIdCounter;
      window.__codexSessionDeletePending.set(id, { resolve: resolve, reject: reject });
      window.\(cdpBridgeBindingName)(JSON.stringify({ id: id, path: path, payload: payload || null }));
    });
  };
  window.__codexSessionDeleteResolve = function(id, result) {
    var entry = window.__codexSessionDeletePending.get(id);
    if (!entry) return;
    window.__codexSessionDeletePending.delete(id);
    entry.resolve(result);
  };
  window.__codexSessionDeleteReject = function(id, error) {
    var entry = window.__codexSessionDeletePending.get(id);
    if (!entry) return;
    window.__codexSessionDeletePending.delete(id);
    entry.reject(new Error(typeof error === "string" ? error : String(error)));
  };
})();
"""

/// The complete injection script, ported from CodexPlusPlus renderer-inject.js.
/// Contains only the plugin entry unlock and force plugin install features.
public let codexPluginInjectionScript: String = """
(function() {
  "use strict";

  // ── JS error capture (installed first so we catch errors from the rest of the script) ──
  // Errors are sent via a deferred diagnostic — stored on window and flushed once the
  // bridge is available, since the error handler may fire before __codexSessionDeleteBridge
  // is installed.
  window.__codexPlusJsErrors = window.__codexPlusJsErrors || [];
  function captureJsError(message, filename, lineno, stack) {
    try {
      const entry = { message: String(message || "").slice(0, 500), filename: String(filename || "").slice(0, 200), lineno: lineno || 0, stack: String(stack || "").slice(0, 500), at: Date.now() };
      window.__codexPlusJsErrors.push(entry);
      if (window.__codexPlusJsErrors.length > 20) window.__codexPlusJsErrors.shift();
      if (window.__codexSessionDeleteBridge) {
        window.__codexSessionDeleteBridge("/cdp/diagnostic", JSON.stringify({ event: "injector_js_error", detail: entry })).catch(() => {});
      }
    } catch (_) {}
  }
  window.addEventListener("error", (e) => {
    captureJsError(e?.message || "error", e?.filename, e?.lineno, e?.error?.stack || e?.stack);
  });
  window.addEventListener("unhandledrejection", (e) => {
    const reason = e?.reason;
    captureJsError("unhandledrejection: " + (reason?.message || String(reason)), "", 0, reason?.stack || "");
  });

  // ── Constants ──────────────────────────────────────────────────────
  const codexForcePluginInstallRefreshIntervalMs = 1000;
  const codexPluginLegacyEntryUnlockBeforeVersion = "26.601.2237";

  // ── Selectors ──────────────────────────────────────────────────────
  const selectors = {
    pluginNavButton: 'nav[role="navigation"] button.h-token-nav-row.w-full',
    pluginSvgPath: 'svg path[d^="M7.94562 14.0277"]',
    disabledInstallButton: 'button:disabled, button[aria-disabled="true"], [role="button"][aria-disabled="true"], button[data-disabled], [role="button"][data-disabled], button.cursor-not-allowed, [role="button"].cursor-not-allowed, button.pointer-events-none, [role="button"].pointer-events-none',
  };

  // ── Settings ───────────────────────────────────────────────────────
  let codexPlusBackendSettings = window.__codexPlusBackendSettings || {};
  let codexPlusBackendSettingsLoaded = false;

  const codexPlusBackendSettingMap = {
    pluginEntryUnlock: "codexAppPluginEntryUnlock",
    forcePluginInstall: "codexAppForcePluginInstall",
    pluginMarketplaceUnlock: "codexAppPluginMarketplaceUnlock",
    modelWhitelistUnlock: "codexAppModelWhitelistUnlock",
  };

  function defaultCodexPlusSettings() {
    return { pluginEntryUnlock: true, forcePluginInstall: true };
  }

  function backendCodexPlusSettings() {
    const settings = {};
    Object.entries(codexPlusBackendSettingMap).forEach(([localKey, backendKey]) => {
      if (typeof codexPlusBackendSettings[backendKey] === "boolean") {
        settings[localKey] = codexPlusBackendSettings[backendKey];
      }
    });
    return settings;
  }

  function codexPlusSettings() {
    const relayPatchDisabled = codexPlusBackendSettings.launchMode === "relay";
    if (codexPlusBackendSettings.enhancementsEnabled === false) {
      return { pluginEntryUnlock: false, forcePluginInstall: false };
    }
    try {
      const stored = JSON.parse(localStorage.getItem("codexPlusSettings") || "{}");
      const settings = { ...defaultCodexPlusSettings(), ...stored, ...backendCodexPlusSettings() };
      if (relayPatchDisabled) {
        settings.pluginEntryUnlock = false;
        settings.forcePluginInstall = false;
      }
      return settings;
    } catch {
      const settings = { ...defaultCodexPlusSettings(), ...backendCodexPlusSettings() };
      if (relayPatchDisabled) {
        settings.pluginEntryUnlock = false;
        settings.forcePluginInstall = false;
      }
      return settings;
    }
  }

  // ── Version comparison ────────────────────────────────────────────
  function parseCodexVersionParts(version) {
    try {
      return String(version).trim().split(".").map((part) => {
        const num = parseInt(part, 10);
        return Number.isFinite(num) ? num : null;
      });
    } catch { return []; }
  }

  function compareCodexVersions(left, right) {
    const leftParts = parseCodexVersionParts(left);
    const rightParts = parseCodexVersionParts(right);
    if (leftParts.length === 0 || rightParts.length === 0) return null;
    const len = Math.max(leftParts.length, rightParts.length);
    for (let index = 0; index < len; index++) {
      const leftPart = leftParts[index] ?? 0;
      const rightPart = rightParts[index] ?? 0;
      if (leftPart !== rightPart) return leftPart < rightPart ? -1 : 1;
    }
    return 0;
  }

  function codexPluginUnlockStrategy() {
    const version = String(codexPlusBackendSettings.codexAppVersion || "").trim();
    const comparison = compareCodexVersions(version, codexPluginLegacyEntryUnlockBeforeVersion);
    if (comparison == null) return "unknown";
    return comparison < 0 ? "legacy" : "modern";
  }

  function pluginPatchDisabledInRelayMode() {
    return !codexPlusBackendSettingsLoaded || codexPlusBackendSettings.launchMode === "relay";
  }

  // ── React Fiber helpers ───────────────────────────────────────────
  function reactFiberFrom(element) {
    const fiberKey = Object.keys(element).find((key) => key.startsWith("__reactFiber"));
    return fiberKey ? element[fiberKey] : null;
  }

  function authContextValueFrom(element) {
    for (let fiber = reactFiberFrom(element); fiber; fiber = fiber.return) {
      for (const value of [fiber.memoizedProps?.value, fiber.pendingProps?.value]) {
        if (value && typeof value === "object" && typeof value.setAuthMethod === "function" && "authMethod" in value) {
          return value;
        }
      }
    }
    return null;
  }

  function spoofChatGPTAuthMethod(element) {
    const auth = authContextValueFrom(element);
    if (!auth || auth.authMethod === "chatgpt") return false;
    auth.setAuthMethod("chatgpt");
    return true;
  }

  // ── Plugin Entry Unlock ───────────────────────────────────────────
  function pluginEntryButton() {
    const byIcon = document.querySelector(selectors.pluginNavButton + " " + selectors.pluginSvgPath)?.closest("button");
    if (byIcon) return byIcon;
    return Array.from(document.querySelectorAll(selectors.pluginNavButton))
      .find((button) => /^(插件|Plugins)(\\s+-\\s+.*)?$/i.test((button.textContent || "").trim())) || null;
  }

  function labelUnlockedPluginEntry(button) {
    const labelTextNode = Array.from(button.querySelectorAll("span, div")).reverse()
      .flatMap((node) => Array.from(node.childNodes))
      .find((node) => node.nodeType === 3 && /^(插件|Plugins)( - 已解锁| - Unlocked)?$/i.test((node.nodeValue || "").trim()));
    if (!labelTextNode) return;
    const current = (labelTextNode.nodeValue || "").trim();
    labelTextNode.nodeValue = /^Plugins/i.test(current) ? "Plugins - Unlocked" : "插件 - 已解锁";
  }

  function clearPluginEntryUnlockLabel(button) {
    const labelTextNode = Array.from(button.querySelectorAll("span, div")).reverse()
      .flatMap((node) => Array.from(node.childNodes))
      .find((node) => node.nodeType === 3 && /^(插件 - 已解锁|Plugins - Unlocked)$/i.test((node.nodeValue || "").trim()));
    if (!labelTextNode) return;
    labelTextNode.nodeValue = /^Plugins/i.test((labelTextNode.nodeValue || "").trim()) ? "Plugins" : "插件";
  }

  function enablePluginEntry() {
    if (pluginPatchDisabledInRelayMode()) return;
    if (!codexPlusSettings().pluginEntryUnlock) return;
    const pluginButton = pluginEntryButton();
    if (!pluginButton) return;
    const spoofed = spoofChatGPTAuthMethod(pluginButton);
    pluginButton.disabled = false;
    pluginButton.removeAttribute("disabled");
    pluginButton.style.display = "";
    pluginButton.querySelectorAll("*").forEach((node) => {
      node.style.display = "";
    });
    labelUnlockedPluginEntry(pluginButton);
    const reactPropsKey = Object.keys(pluginButton).find((key) => key.startsWith("__reactProps"));
    if (reactPropsKey) {
      pluginButton[reactPropsKey].disabled = false;
    }
    if (pluginButton.dataset.codexPluginEnabled !== "true") {
      pluginButton.dataset.codexPluginEnabled = "true";
      sendCodexPlusDiagnostic("plugin_entry_unlocked", { spoofed: spoofed });
      pluginButton.addEventListener("click", () => {
        spoofChatGPTAuthMethod(pluginButton);
      }, true);
    }
  }

  // ── Force Plugin Install ──────────────────────────────────────────
  function pluginInstallCandidates() {
    const nodes = Array.from(document.querySelectorAll(selectors.disabledInstallButton));
    return Array.from(new Set(nodes.map((node) => node.closest?.("button, [role='button']") || node)));
  }

  function installButtonLabel(element) {
    return (element.textContent || "").trim();
  }

  function isInstallButtonLabel(text) {
    return /^安装\\s*/.test(text) || /^Install\\s*/i.test(text) || text === "强制安装";
  }

  function patchReactDisabledProps(element) {
    Object.keys(element)
      .filter((key) => key.startsWith("__reactProps"))
      .forEach((key) => {
        const props = element[key];
        if (!props || typeof props !== "object") return;
        props.disabled = false;
        props["aria-disabled"] = false;
        props["data-disabled"] = undefined;
      });
  }

  function clearDisabledState(element) {
    if (!(element instanceof HTMLElement)) return;
    if ("disabled" in element) element.disabled = false;
    element.removeAttribute("disabled");
    element.removeAttribute("aria-disabled");
    element.removeAttribute("data-disabled");
    element.removeAttribute("inert");
    element.classList.remove("disabled", "opacity-50", "cursor-not-allowed", "pointer-events-none");
    element.classList.add("codex-force-install-unlocked");
    element.style.pointerEvents = "auto";
    element.style.opacity = "";
    element.style.cursor = "pointer";
    element.tabIndex = 0;
    patchReactDisabledProps(element);
  }

  function installButtonUnlockNodes(button) {
    const nodes = [button];
    button.querySelectorAll?.("button, [role='button'], [disabled], [aria-disabled], [data-disabled], .cursor-not-allowed, .pointer-events-none")
      .forEach((node) => nodes.push(node));
    let parent = button.parentElement;
    for (let depth = 0; parent && depth < 3; depth += 1, parent = parent.parentElement) {
      if (parent.matches?.("button, [role='button'], [disabled], [aria-disabled], [data-disabled], .cursor-not-allowed, .pointer-events-none")) {
        nodes.push(parent);
      }
    }
    return Array.from(new Set(nodes));
  }

  function installForcedInstallGuard(button) {
    if (button.dataset.codexForceInstallUnlocked === "true") return;
    button.dataset.codexForceInstallUnlocked = "true";
    const keepUnlocked = () => installButtonUnlockNodes(button).forEach(clearDisabledState);
    ["pointerdown", "mousedown", "mouseup", "click", "focus"].forEach((eventName) => {
      button.addEventListener(eventName, keepUnlocked, true);
    });
  }

  function unblockButtonElement(button) {
    installButtonUnlockNodes(button).forEach(clearDisabledState);
    installForcedInstallGuard(button);
  }

  function labelForcedInstallButton(button) {
    const walker = document.createTreeWalker(button, NodeFilter.SHOW_TEXT);
    let textNode = null;
    while (!textNode && walker.nextNode()) {
      const node = walker.currentNode;
      if (isInstallButtonLabel((node.nodeValue || "").trim())) textNode = node;
    }
    if (textNode) {
      textNode.nodeValue = "强制安装";
    }
  }

  function clearForcedInstallButtonLabel(button) {
    const walker = document.createTreeWalker(button, NodeFilter.SHOW_TEXT);
    let textNode = null;
    while (!textNode && walker.nextNode()) {
      const node = walker.currentNode;
      if ((node.nodeValue || "").trim() === "强制安装") textNode = node;
    }
    if (textNode) {
      textNode.nodeValue = "安装";
    }
  }

  function clearPluginPatchArtifacts() {
    const pluginButton = pluginEntryButton();
    if (pluginButton) {
      delete pluginButton.dataset.codexPluginEnabled;
      clearPluginEntryUnlockLabel(pluginButton);
    }
    pluginInstallCandidates().forEach(clearForcedInstallButtonLabel);
  }

  function unblockPluginInstallButtons() {
    if (pluginPatchDisabledInRelayMode()) return;
    if (!codexPlusSettings().forcePluginInstall) return;
    pluginInstallCandidates().forEach((button) => {
      const text = installButtonLabel(button);
      if (!isInstallButtonLabel(text)) return;
      unblockButtonElement(button);
      labelForcedInstallButton(button);
    });
  }

  function refreshForcePluginInstallUnlockLoop() {
    const shouldRun = !pluginPatchDisabledInRelayMode() && codexPlusSettings().forcePluginInstall;
    if (!shouldRun) {
      clearInterval(window.__codexForcePluginInstallRefreshTimer);
      window.__codexForcePluginInstallRefreshTimer = null;
      return;
    }
    if (window.__codexForcePluginInstallRefreshTimer) return;
    window.__codexForcePluginInstallRefreshTimer = setInterval(() => {
      if (!codexPlusSettings().forcePluginInstall || pluginPatchDisabledInRelayMode()) {
        clearInterval(window.__codexForcePluginInstallRefreshTimer);
        window.__codexForcePluginInstallRefreshTimer = null;
        return;
      }
      unblockPluginInstallButtons();
    }, codexForcePluginInstallRefreshIntervalMs);
  }

  // ── Scan ──────────────────────────────────────────────────────────
  function scanDeferred() {
    window.__codexPlusScanCount = (window.__codexPlusScanCount || 0) + 1;
    if (pluginPatchDisabledInRelayMode()) {
      clearPluginPatchArtifacts();
      refreshForcePluginInstallUnlockLoop();
    } else {
      const strategy = codexPluginUnlockStrategy();
      const settings = codexPlusSettings();
      if ((strategy === "legacy" || strategy === "unknown") && settings.pluginEntryUnlock) {
        enablePluginEntry();
      }
      unblockPluginInstallButtons();
      refreshForcePluginInstallUnlockLoop();
    }
  }

  function runScanStep(step) {
    try { step(); } catch (_) {}
  }

  function scan() {
    requestAnimationFrame(() => runScanStep(scanDeferred));
  }

  // ── Mutation filtering (ported from CodexPlusPlus) ────────────────
  // Only schedule scans for mutations on scan-relevant DOM (sidebar threads,
  // chat content, install buttons). Without this filter, the MutationObserver
  // fires on every React re-render — including re-renders triggered by
  // `spoofChatGPTAuthMethod` inside `enablePluginEntry` — creating a feedback
  // loop that freezes Codex on startup when `pluginEntryUnlock` is enabled.
  function scanRelevantSelector() {
    const parts = [
      '[data-message-author-role]',
      '[data-testid="conversation-turn"]',
      '[class*="user-message"]',
      '[class*="UserMessage"]',
      '.composer-footer',
    ];
    if (!pluginPatchDisabledInRelayMode()) parts.push(selectors.disabledInstallButton);
    return parts.join(", ");
  }

  function nodeSelfOrAncestorMatchesScanRelevance(node) {
    if (node.nodeType !== 1) return false;
    const relevantSelector = scanRelevantSelector();
    return !!node.matches?.(relevantSelector) || !!node.closest?.(relevantSelector);
  }

  function isScanRelevantNode(node) {
    if (node.nodeType !== 1) return false;
    return nodeSelfOrAncestorMatchesScanRelevance(node) || !!node.querySelector?.(scanRelevantSelector());
  }

  function isChatContentMutation(mutation) {
    const target = mutation.target;
    if (!target?.closest?.('[data-message-author-role], [data-testid="conversation-turn"], main .prose')) return false;
    return !Array.from(mutation.addedNodes).some((node) => node.nodeType === 1 && isScanRelevantNode(node)) &&
      !Array.from(mutation.removedNodes).some((node) => node.nodeType === 1 && isScanRelevantNode(node));
  }

  function shouldScheduleScan(mutations) {
    if (!mutations) return true;
    return mutations.some((mutation) => {
      if (isChatContentMutation(mutation)) return false;
      const target = mutation.target;
      if (target?.nodeType === 1 && nodeSelfOrAncestorMatchesScanRelevance(target)) return true;
      const changedNodes = [...Array.from(mutation.addedNodes), ...Array.from(mutation.removedNodes)];
      return changedNodes.some((node) => node.nodeType === 1 && isScanRelevantNode(node));
    });
  }

  // ── Plugin Marketplace Unlock ────────────────────────────────────
  // Patch Array.prototype.filter to bypass Codex's plugin/marketplace filtering

  function installPluginMarketplacePatch() {
    if (window.__codexPluginMarketplacePatchInstalled) return;
    if (pluginPatchDisabledInRelayMode()) return;
    if (!codexPlusSettings().pluginMarketplaceUnlock) return;

    const originalFilter = Array.prototype.__codexOriginalFilter || Array.prototype.filter;
    if (!Array.prototype.__codexOriginalFilter) {
      Object.defineProperty(Array.prototype, "__codexOriginalFilter", {
        value: originalFilter,
        configurable: true,
        writable: true,
      });
    }

    const patchedFilter = function(callback, thisArg) {
      // Detect Codex plugin filter pattern
      if (isCodexPluginFilter(callback, this)) {
        console.log("[CodexPlus] Plugin filter bypassed, returning all", this.length, "plugins");
        return Array.from(this);
      }
      // Detect Codex marketplace filter pattern
      if (isCodexMarketplaceFilter(callback, this)) {
        console.log("[CodexPlus] Marketplace filter bypassed, returning all", this.length, "marketplaces");
        return Array.from(this);
      }
      return originalFilter.call(this, callback, thisArg);
    };

    Array.prototype.filter = patchedFilter;
    window.__codexPluginMarketplacePatchInstalled = true;
    sendCodexPlusDiagnostic("plugin_marketplace_patch_installed", {});
    console.log("[CodexPlus] Plugin marketplace patch installed");
  }

  function isCodexPluginFilter(callback, sample) {
    if (!Array.isArray(sample) || sample.length === 0) return false;
    if (typeof callback !== "function") return false;

    let source = "";
    try { source = Function.prototype.toString.call(callback); } catch { return false; }

    // Known Codex filter patterns for plugins
    const knownPatterns = [
      "!u(e.marketplaceName)||e.marketplaceName===r",
      "!ne(e.marketplaceName)||e.marketplaceName===n"
    ];

    const isKnownPattern = knownPatterns.some(pattern => source.includes(pattern));
    if (!isKnownPattern) return false;

    // Verify this is actually filtering official marketplaces
    return sample.some(item => {
      const name = item?.marketplaceName || "";
      return name === "openai-bundled" || name === "openai-curated" || name === "openai-primary-runtime";
    });
  }

  function isCodexMarketplaceFilter(callback, sample) {
    if (!Array.isArray(sample) || sample.length === 0) return false;
    if (typeof callback !== "function") return false;

    let source = "";
    try { source = Function.prototype.toString.call(callback); } catch { return false; }

    // Known Codex filter pattern for marketplaces
    if (!source.includes("!t.includes(e.name)")) return false;

    // Verify this is filtering official marketplaces
    return sample.some(item => {
      const name = item?.name || "";
      return name === "openai-bundled" || name === "openai-curated" || name === "openai-primary-runtime";
    });
  }

  // ── Settings polling ──────────────────────────────────────────────
  async function fetchBackendSettings() {
    try {
      const body = await window.__codexSessionDeleteBridge("/settings/get", null);
      const data = JSON.parse(body);
      codexPlusBackendSettings = data;
      codexPlusBackendSettingsLoaded = true;
      window.__codexPlusBackendSettings = data;
      sendCodexPlusDiagnostic("settings_loaded", {
        modelProvider: data.modelProvider || "",
        enhancementsEnabled: data.enhancementsEnabled,
      });
    } catch (_) {}
  }

  // ── Model Whitelist Unlock ────────────────────────────────────────
  let codexModelCatalog = { status: "loading", models: [] };
  let codexModelCatalogLoadedAt = 0;
  let codexModelCatalogPromise = null;
  const codexModelCatalogCacheMs = 10000;
  const codexPlusModelListRequestIds = new Set();
  const codexAppServerModelRequestPatchVersion = "1";
  const codexAppModulePromises = new Map();
  let codexAppServerPatchFailedUntil = 0;

  // ── Performance counters (reported via injector_heartbeat) ────────
  // Track cumulative work done by the graph/React patchers. If these grow
  // fast while the page is frozen, the patcher is the bottleneck.
  let codexPlusGraphPatchCalls = 0;
  let codexPlusGraphPatchNodes = 0;
  let codexPlusReactNodesScanned = 0;
  let codexPlusReactFibersScanned = 0;
  let codexPlusHeartbeatInFlight = false;
  const codexPlusBootstrapTime = Date.now();

  function shouldPatchModels() {
    if (pluginPatchDisabledInRelayMode()) return false;
    if (codexPlusBackendSettings.modelProvider === "chatgpt") return false;
    return codexPlusSettings().modelWhitelistUnlock;
  }

  function codexPlusModelNames() {
    const models = Array.isArray(codexModelCatalog.models) ? codexModelCatalog.models : [];
    // Config uses "slug" field as model ID; fall back to "model" for compatibility
    return Array.from(new Set(models.map((entry) => entry?.slug || entry?.model).filter((name) => typeof name === "string" && name.length > 0)));
  }

  async function loadCodexModelCatalog(force = false) {
    if (!force && codexModelCatalogPromise) return codexModelCatalogPromise;
    if (!force && codexModelCatalogLoadedAt && Date.now() - codexModelCatalogLoadedAt < codexModelCatalogCacheMs) return codexModelCatalog;
    codexModelCatalogPromise = window.__codexSessionDeleteBridge("/codex-model-catalog", null)
      .then((body) => JSON.parse(body))
      .then((result) => {
        codexModelCatalog = result && typeof result === "object" && Array.isArray(result.models)
          ? result
          : { status: "failed", models: [] };
        codexModelCatalogLoadedAt = Date.now();
        sendCodexPlusDiagnostic("catalog_loaded", {
          modelCount: Array.isArray(codexModelCatalog.models) ? codexModelCatalog.models.length : 0,
        });
        return codexModelCatalog;
      })
      .catch((err) => {
        codexModelCatalog = { status: "failed", models: [] };
        codexModelCatalogLoadedAt = Date.now();
        sendCodexPlusDiagnostic("catalog_failed", { error: String(err?.message || err) });
        return codexModelCatalog;
      })
      .finally(() => {
        codexModelCatalogPromise = null;
      });
    return codexModelCatalogPromise;
  }

  // ── Webpack module loader (for AppServer patch) ───────────────────
  function codexAppAssetUrl(namePart) {
    try {
      const urls = [
        ...Array.from(document.scripts || []).map((script) => script.src),
        ...Array.from(document.querySelectorAll("link[href]") || []).map((link) => link.href),
        ...performance.getEntriesByType("resource").map((entry) => entry.name),
      ].filter(Boolean);
      return urls.find((url) => url.includes("/assets/") && url.includes(namePart) && url.split("?")[0].endsWith(".js")) || "";
    } catch {
      return "";
    }
  }

  async function loadCodexAppModule(namePart) {
    if (!codexAppModulePromises.has(namePart)) {
      const promise = Promise.resolve().then(async () => {
        const url = codexAppAssetUrl(namePart);
        if (!url) throw new Error("Codex App asset not found: " + namePart);
        return await import(url);
      }).catch((error) => {
        codexAppModulePromises.delete(namePart);
        throw error;
      });
      codexAppModulePromises.set(namePart, promise);
    }
    return await codexAppModulePromises.get(namePart);
  }

  // ── Model descriptor + array patching ─────────────────────────────
  function modelReasoningEfforts() {
    return ["minimal", "low", "medium", "high", "xhigh"].map((reasoningEffort) => ({ reasoningEffort, description: `${reasoningEffort} effort` }));
  }

  function findModelEntry(modelName) {
    const models = Array.isArray(codexModelCatalog.models) ? codexModelCatalog.models : [];
    // Match by slug (config format) or model (fallback)
    return models.find((entry) => (entry?.slug || entry?.model) === modelName);
  }

  function codexPlusModelDescriptor(modelName) {
    const entry = findModelEntry(modelName);
    // Config uses snake_case: display_name, supported_reasoning_levels
    const displayName = entry?.display_name || entry?.displayName || modelName;
    const rawReasoningLevels = entry?.supported_reasoning_levels || entry?.supportedReasoningEfforts;
    // Convert {effort, description} to {reasoningEffort, description} if needed
    const reasoningEfforts = rawReasoningLevels
      ? rawReasoningLevels.map((level) => ({
          reasoningEffort: level.reasoningEffort || level.effort,
          description: level.description || `${level.reasoningEffort || level.effort} effort`,
        }))
      : modelReasoningEfforts();
    return {
      model: modelName,
      id: modelName,
      slug: modelName,
      name: displayName,
      displayName: displayName,
      description: codexModelCatalog.provider_name || codexModelCatalog.model_provider || "Custom model",
      hidden: false,
      isDefault: (codexModelCatalog.default_model || codexModelCatalog.model) === modelName,
      defaultReasoningEffort: "medium",
      supportedReasoningEfforts: reasoningEfforts,
    };
  }

  function modelArrayLooksPatchable(value, allowEmpty) {
    return Array.isArray(value)
      && (allowEmpty || value.length > 0)
      && value.every((item) => item && typeof item === "object" && typeof item.model === "string");
  }

  function stringArrayLooksPatchable(value) {
    return Array.isArray(value) && value.every((item) => typeof item === "string");
  }

  function patchModelNameArray(models) {
    try {
      if (!stringArrayLooksPatchable(models)) return false;
      const customModels = codexPlusModelNames();
      if (!customModels.length) return false;
      let changed = false;
      customModels.forEach((name) => {
        if (!models.includes(name)) {
          models.push(name);
          changed = true;
        }
      });
      return changed;
    } catch {
      return false;
    }
  }

  function patchModelArray(models, allowEmpty, path = "unknown") {
    try {
      if (!modelArrayLooksPatchable(models, allowEmpty)) return false;
      const customModels = codexPlusModelNames();
      if (!customModels.length) return false;
      let changed = false;
      const beforeCount = models.length;

      // Step 1: Add custom models that don't exist
      const existing = new Map(models.map((item) => [item.model, item]));
      customModels.forEach((modelName) => {
        if (!existing.has(modelName)) {
          models.push(codexPlusModelDescriptor(modelName));
          changed = true;
        }
      });

      // Step 2: Remove non-custom models (complete replacement)
      // Filter in place to keep only custom models
      const customSet = new Set(customModels);
      let writeIndex = 0;
      for (let readIndex = 0; readIndex < models.length; readIndex++) {
        if (customSet.has(models[readIndex].model)) {
          if (writeIndex !== readIndex) {
            models[writeIndex] = models[readIndex];
            changed = true;
          }
          writeIndex++;
        } else {
          changed = true; // Removing a non-custom model
        }
      }
      models.length = writeIndex;

      return changed;
    } catch {
      return false;
    }
  }

  // One-shot diagnostic: logs the shape of the top-level model container so we
  // can see which fields (models, availableModels, defaultModel) the response
  // actually carries. Fires at most once per shape signature.
  let __codexPlusContainerShapeLogged = new Set();
  let __codexPlusContainerPatchedLogged = new Set();
  function logModelContainerShape(value) {
    try {
      if (!value || typeof value !== "object") return;
      const sig = [
        "models:" + (Array.isArray(value.models) ? "arr(" + value.models.length + ")" : typeof value.models),
        "availableModels:" + (Array.isArray(value.availableModels) ? "arr(" + value.availableModels.length + ")" : typeof value.availableModels),
        "available_models:" + (Array.isArray(value.available_models) ? "arr(" + value.available_models.length + ")" : typeof value.available_models),
        "defaultModel:" + (value.defaultModel != null ? "set" : "absent"),
        "model:" + (value.model != null ? "set" : "absent"),
      ].join(",");
      if (__codexPlusContainerShapeLogged.has(sig)) return;
      __codexPlusContainerShapeLogged.add(sig);
      sendCodexPlusDiagnostic("model_container_shape", { shape: sig });
    } catch (_) {}
  }

  function patchModelContainer(value) {
    try {
      if (!value || typeof value !== "object") return false;
      const names = codexPlusModelNames();
      if (!names.length) return false;
      let changed = false;
      const patchedPaths = [];
      if (patchModelArray(value.models, "defaultModel" in value || "availableModels" in value, "models")) { changed = true; patchedPaths.push("models"); }
      // CPP-aligned: also patch string arrays in value.models
      if (patchModelNameArray(value.models)) { changed = true; patchedPaths.push("models(strings)"); }
      if (patchModelArray(value.data, false, "data")) { changed = true; patchedPaths.push("data"); }
      if (patchModelArray(value.result, false, "result")) { changed = true; patchedPaths.push("result"); }
      if (patchModelArray(value.pages?.[0]?.data, false, "pages[0].data")) { changed = true; patchedPaths.push("pages[0].data"); }
      if (patchModelArray(value.result?.data, false, "result.data")) { changed = true; patchedPaths.push("result.data"); }
      if (patchModelArray(value.result?.models, false, "result.models")) { changed = true; patchedPaths.push("result.models"); }
      if (patchModelArray(value.message?.result?.data, false, "message.result.data")) { changed = true; patchedPaths.push("message.result.data"); }
      if (patchModelArray(value.message?.result?.models, false, "message.result.models")) { changed = true; patchedPaths.push("message.result.models"); }
      // CPP-aligned: patch availableModels / available_models (Sets and arrays)
      if (value.availableModels instanceof Set) {
        names.forEach((name) => {
          if (!value.availableModels.has(name)) {
            value.availableModels.add(name);
            changed = true;
          }
        });
      }
      if (value.available_models instanceof Set) {
        names.forEach((name) => {
          if (!value.available_models.has(name)) {
            value.available_models.add(name);
            changed = true;
          }
        });
      }
      if (Array.isArray(value.availableModels)) {
        names.forEach((name) => {
          if (!value.availableModels.includes(name)) {
            value.availableModels.push(name);
            changed = true;
          }
        });
      }
      if (Array.isArray(value.available_models)) {
        names.forEach((name) => {
          if (!value.available_models.includes(name)) {
            value.available_models.push(name);
            changed = true;
          }
        });
      }
      if (Array.isArray(value.hiddenModels)) {
        const before = value.hiddenModels.length;
        value.hiddenModels = value.hiddenModels.filter((name) => !names.includes(name));
        if (value.hiddenModels.length !== before) { changed = true; patchedPaths.push("hiddenModels"); }
      }
      if (Array.isArray(value.hidden_models)) {
        const before = value.hidden_models.length;
        value.hidden_models = value.hidden_models.filter((name) => !names.includes(name));
        if (value.hidden_models.length !== before) { changed = true; patchedPaths.push("hidden_models"); }
      }
      // CPP-aligned: set defaultModel if not present
      if (value.defaultModel == null && names.length > 0) {
        value.defaultModel = codexPlusModelDescriptor(names[0]);
        changed = true;
      } else if (typeof value.defaultModel === "string" && names.includes(value.defaultModel) && value.model == null) {
        value.model = value.defaultModel;
        changed = true;
      }
      if (changed) {
        const sig = [
          "models:" + (Array.isArray(value.models) ? "arr(" + value.models.length + ")" : typeof value.models),
          "availableModels:" + (Array.isArray(value.availableModels) ? "arr(" + value.availableModels.length + ")" : typeof value.availableModels),
          "available_models:" + (Array.isArray(value.available_models) ? "arr(" + value.available_models.length + ")" : typeof value.available_models),
          "defaultModel:" + (value.defaultModel != null ? "set" : "absent"),
        ].join(",");
        const logKey = sig + "|" + patchedPaths.join(",");
        if (!__codexPlusContainerPatchedLogged.has(logKey)) {
          __codexPlusContainerPatchedLogged.add(logKey);
          const namesSet = new Set(names);
          let customInModels = 0;
          if (Array.isArray(value.models)) {
            customInModels = value.models.filter((m) => m && namesSet.has(m.model)).length;
          }
          const availArr = Array.isArray(value.availableModels) ? value.availableModels : (Array.isArray(value.available_models) ? value.available_models : []);
          const customInAvailable = availArr.filter((n) => namesSet.has(n)).length;
          sendCodexPlusDiagnostic("model_container_patched", {
            shape: sig,
            patchedPaths: patchedPaths,
            after: {
              modelsCount: Array.isArray(value.models) ? value.models.length : 0,
              availableModelsCount: availArr.length,
              customInModels: customInModels,
              customInAvailable: customInAvailable,
            },
          });
        }
      }
      return changed;
    } catch {
      return false;
    }
  }

  function patchObjectGraphForModels(root, visited, depth) {
    try {
      if (!root || typeof root !== "object" || visited.has(root) || depth > 5) return false;
      visited.add(root);
      codexPlusGraphPatchCalls += 1;
      codexPlusGraphPatchNodes += 1;
      let changed = patchModelContainer(root);
      if (root instanceof Element || root === window || root === document || root === document.body || root === document.documentElement) return changed;
      for (const key of Object.keys(root)) {
        if (key === "ownerDocument" || key === "parentElement" || key === "parentNode" || key === "children" || key === "childNodes") continue;
        let value;
        try { value = root[key]; } catch { continue; }
        if (value && typeof value === "object" && patchObjectGraphForModels(value, visited, depth + 1)) changed = true;
      }
      return changed;
    } catch {
      return false;
    }
  }

  // ── Statsig SDK patch ─────────────────────────────────────────────
  function patchStatsigModelDynamicConfig(config, name) {
    // No-op: previously appended custom model names to `config.value.available_models`.
    // Removed because the picker renders `available_models` (string array from
    // Statsig) as a SEPARATE list from the AppServer `model/list` response
    // (object array with metadata). Patching both made each custom model appear
    // twice — once with metadata (from AppServer, reasoning controls work) and
    // once as a bare string (from Statsig, reasoning controls broken). The
    // AppServer response already carries custom models with full metadata, so
    // the Statsig patch was redundant and only caused duplication.
    //
    // The wrapper in `patchStatsigModelWhitelist` is still installed so future
    // patching can be re-enabled by restoring the function body.
    return config;
  }

  function statsigClients() {
    try {
      const root = window.__STATSIG__ || globalThis.__STATSIG__;
      if (!root || typeof root !== "object") return [];
      const clients = [root.firstInstance, typeof root.instance === "function" ? root.instance() : null];
      if (root.instances && typeof root.instances === "object") clients.push(...Object.values(root.instances));
      return clients.filter((client, index, array) => client && typeof client === "object" && array.indexOf(client) === index);
    } catch {
      return [];
    }
  }

  function patchStatsigModelWhitelist() {
    if (!shouldPatchModels()) return;
    try {
      let clientCount = 0;
      statsigClients().forEach((client) => {
        if (typeof client.getDynamicConfig !== "function") return;
        clientCount += 1;
        if (!client.__codexPlusModelWhitelistPatched) {
          const originalGetDynamicConfig = client.getDynamicConfig.bind(client);
          client.getDynamicConfig = (name, options) => {
            const result = originalGetDynamicConfig(name, options);
            return patchStatsigModelDynamicConfig(result, name);
          };
          client.__codexPlusModelWhitelistPatched = true;
          sendCodexPlusDiagnostic("statsig_patch_installed", { clientCount: 1 });
        }
        try {
          patchStatsigModelDynamicConfig(client.getDynamicConfig("107580212", { disableExposureLog: true }), "107580212");
        } catch (_) {}
      });
    } catch (e) {
      sendCodexPlusDiagnostic("statsig_patch_failed", { error: String(e?.stack || e) });
    }
  }

  // ── IPC: Intercept model/list dispatch + response ─────────────────
  function patchMcpModelResponseData(data) {
    try {
      if (data?.type !== "mcp-response") return false;
      const message = data.message || data.response;
      const requestId = message?.id != null ? String(message.id) : "";
      if (codexPlusModelListRequestIds.size > 0 && !codexPlusModelListRequestIds.has(requestId)) return false;
      codexPlusModelListRequestIds.delete(requestId);
      return patchModelContainer(data) || patchModelContainer(message) || patchModelContainer(message?.result) || patchModelContainer(message?.result?.data);
    } catch {
      return false;
    }
  }

  function patchAppServerModelMessages() {
    if (window.__codexPlusModelMessagePatchInstalled) return;
    window.__codexPlusModelMessagePatchInstalled = true;
    try {
      const originalDispatchEvent = window.dispatchEvent;
      window.dispatchEvent = function patchedCodexPlusDispatchEvent(event) {
        try {
          if (shouldPatchModels() && codexPlusModelNames().length) {
            const detail = event?.detail;
            const request = detail?.request;
            if (event?.type === "codex-message-from-view" && detail?.type === "mcp-request" && request?.method === "model/list") {
              request.params = { ...(request.params || {}), includeHidden: true };
              if (request.id != null) codexPlusModelListRequestIds.add(String(request.id));
            }
            if (event?.type === "message") patchMcpModelResponseData(event.data);
          }
        } catch (_) {}
        return originalDispatchEvent.call(this, event);
      };

      window.addEventListener("message", (event) => {
        try {
          if (shouldPatchModels() && codexPlusModelNames().length) {
            patchMcpModelResponseData(event?.data);
          }
        } catch (_) {}
      }, true);
      sendCodexPlusDiagnostic("appserver_message_patch_installed", {});
    } catch (_) {}
  }

  // ── AppServer request client patch (sendRequest interception) ─────
  function appServerModelRequestMethod(method, params) {
    if (method === "send-cli-request-for-host" && params?.method) return String(params.method);
    if (method === "vscode://codex/list-plugins") return "list-plugins";
    if (method === "vscode://codex/plugin/install") return "install-plugin";
    if (method === "vscode://codex/plugin/uninstall") return "uninstall-plugin";
    if (method === "plugin/list") return "list-plugins";
    if (method === "plugin/install") return "install-plugin";
    if (method === "plugin/uninstall") return "uninstall-plugin";
    return String(method || "");
  }

  function patchAppServerModelResult(method, result) {
    // CPP-aligned: only handle "list-models-for-host", not "model/list"
    if (method !== "list-models-for-host") return result;
    try {
      if (!shouldPatchModels()) return result;
      if (Array.isArray(result)) patchModelArray(result, true, "appserver.result");
      if (Array.isArray(result?.data)) patchModelArray(result.data, true, "appserver.result.data");
      if (Array.isArray(result?.models)) patchModelArray(result.models, true, "appserver.result.models");
      patchModelContainer(result);
      patchObjectGraphForModels(result, new WeakSet(), 0);
    } catch (_) {}
    return result;
  }

  function patchAppServerModelRequestClient(client) {
    if (!client || typeof client.sendRequest !== "function") return false;
    if (client.__codexPlusModelRequestPatch === codexAppServerModelRequestPatchVersion) return true;
    const originalSendRequest = client.__codexPlusModelOriginalSendRequest || client.sendRequest.bind(client);
    client.__codexPlusModelOriginalSendRequest = originalSendRequest;
    client.sendRequest = async function codexPlusModelPatchedSendRequest(method, params, options) {
      const result = await originalSendRequest(method, params, options);
      if (!shouldPatchModels()) return result;
      if (!codexPlusModelNames().length) await loadCodexModelCatalog();
      return patchAppServerModelResult(appServerModelRequestMethod(String(method || ""), params), result);
    };
    client.__codexPlusModelRequestPatch = codexAppServerModelRequestPatchVersion;
    return true;
  }

  function installAppServerModelRequestPatch() {
    if (window.__codexPlusAppServerModelRequestPatchInstalled === codexAppServerModelRequestPatchVersion) return;
    if (!shouldPatchModels()) return;
    // Failure cooldown: if the last attempt failed, don't retry for 30s. The
    // failure is usually "asset not loaded yet" — retrying every 120ms (via
    // the refresh loop) floods the log and stalls the renderer (white-screen
    // flash on Codex startup). The asset either loads later (success on next
    // retry) or never does (no amount of retrying helps).
    if (Date.now() < codexAppServerPatchFailedUntil) return;
    const patch = async () => {
      try {
        const module = await loadCodexAppModule("app-server-manager-signals-");
        const candidates = Object.values(module).filter((value) => value && typeof value === "object");
        let patchedCount = 0;
        for (const candidate of candidates) {
          if (patchAppServerModelRequestClient(candidate)) patchedCount += 1;
          if (typeof candidate.sendRequest !== "function" && typeof candidate.get === "function") {
            try {
              if (patchAppServerModelRequestClient(candidate.get())) patchedCount += 1;
            } catch (_) {}
          }
        }
        if (patchedCount > 0) {
          window.__codexPlusAppServerModelRequestPatchInstalled = codexAppServerModelRequestPatchVersion;
          sendCodexPlusDiagnostic("appserver_request_patch_installed", { patchedCount: patchedCount });
        } else {
          sendCodexPlusDiagnostic("appserver_request_patch_not_found", {
            exportCount: Object.keys(module || {}).length,
            candidateCount: candidates.length,
          });
        }
      } catch (e) {
        codexAppServerPatchFailedUntil = Date.now() + 30000;
        sendCodexPlusDiagnostic("appserver_request_patch_failed", { error: String(e?.stack || e) });
      }
    };
    void patch();
  }

  // ── HTTP fetch response patch (Response.prototype.json) ───────────
  async function patchModelJsonResponse(payload) {
    if (!shouldPatchModels()) return payload;
    if (!codexPlusModelNames().length) await loadCodexModelCatalog();
    if (!payload || typeof payload !== "object") return payload;
    try {
      logModelContainerShape(payload);
      patchModelContainer(payload);
      patchObjectGraphForModels(payload, new WeakSet(), 0);
    } catch (_) {}
    return payload;
  }

  function installModelJsonResponsePatch() {
    if (window.__codexPlusModelJsonResponsePatchInstalled === "1") return;
    if (!shouldPatchModels()) return;
    try {
      window.__codexPlusModelJsonResponsePatchInstalled = "1";
      const originalJson = Response.prototype.json;
      if (typeof originalJson !== "function") return;
      Response.prototype.json = async function codexPlusPatchedResponseJson(...args) {
        const payload = await originalJson.apply(this, args);
        return await patchModelJsonResponse(payload);
      };
      sendCodexPlusDiagnostic("json_response_patch_installed", {});
    } catch (_) {}
  }

  // ── React state patch (fallback) ──────────────────────────────────
  function patchReactModelState() {
    if (!shouldPatchModels()) return false;
    if (!codexPlusModelNames().length) return false;
    try {
      const selector = "[role='menu'], [role='dialog'], [role='listbox'], [data-radix-popper-content-wrapper]";
      const nodes = [document.body, ...document.querySelectorAll(selector)];
      let changed = false;
      codexPlusReactNodesScanned += nodes.length;
      for (const node of nodes.slice(0, 220)) {
        if (!node) continue;
        const fiberKeys = Object.keys(node).filter((k) => k.startsWith("__reactFiber") || k.startsWith("__reactInternalInstance") || k.startsWith("__reactProps"));
        codexPlusReactFibersScanned += fiberKeys.length;
        for (const key of fiberKeys) {
          if (patchObjectGraphForModels(node[key], new WeakSet(), 0)) changed = true;
        }
      }
      return changed;
    } catch (_) {
      return false;
    }
  }

  // ── Model whitelist orchestration ─────────────────────────────────
  function ensureCodexModelWhitelistInstalls() {
    if (!shouldPatchModels()) return;
    installModelJsonResponsePatch();
    patchAppServerModelMessages();
    installAppServerModelRequestPatch();
  }

  function runCodexModelWhitelistRefreshPass() {
    window.__codexPlusRefreshPassCount = (window.__codexPlusRefreshPassCount || 0) + 1;
    if (!shouldPatchModels() || !codexPlusModelNames().length) return false;
    let changed = false;
    try {
      patchStatsigModelWhitelist();
      if (patchReactModelState()) changed = true;
      installAppServerModelRequestPatch();
    } catch (_) {}
    return changed;
  }

  let codexModelWhitelistRefreshTimer = 0;
  let codexModelWhitelistRefreshUntil = 0;
  function scheduleCodexModelWhitelistRefresh(durationMs) {
    if (!shouldPatchModels()) return;
    durationMs = durationMs || 2500;
    codexModelWhitelistRefreshUntil = Math.max(codexModelWhitelistRefreshUntil, Date.now() + durationMs);
    if (codexModelWhitelistRefreshTimer) return;
    sendCodexPlusDiagnostic("model_whitelist_refresh_scheduled", { durationMs: durationMs });
    const tick = () => {
      const changed = runCodexModelWhitelistRefreshPass();
      if (changed && Date.now() < codexModelWhitelistRefreshUntil) {
        codexModelWhitelistRefreshTimer = window.setTimeout(tick, 1000);
      } else {
        codexModelWhitelistRefreshTimer = 0;
      }
    };
    // Always debounce via setTimeout — never call tick() synchronously. The
    // MutationObserver fires on every DOM mutation; an immediate tick() would
    // run a refresh pass per mutation under burst load (550 passes in 2s
    // observed). The bootstrap pass in `bootstrapModelWhitelist` already
    // covers the initial patch; subsequent refreshes can wait 1s.
    codexModelWhitelistRefreshTimer = window.setTimeout(tick, 1000);
  }

  let modelWhitelistMutationObserver = null;
  function startModelWhitelistObserver() {
    if (!shouldPatchModels()) return;
    if (modelWhitelistMutationObserver) return;
    try {
      modelWhitelistMutationObserver = new MutationObserver(() => {
        if (codexPlusModelNames().length) {
          scheduleCodexModelWhitelistRefresh();
        }
      });
      modelWhitelistMutationObserver.observe(document.body, { childList: true, subtree: true });
    } catch (_) {}
  }

  async function bootstrapModelWhitelist() {
    await loadCodexModelCatalog();
    if (!shouldPatchModels()) return;
    ensureCodexModelWhitelistInstalls();
    runCodexModelWhitelistRefreshPass();
    startModelWhitelistObserver();
    startInjectorHeartbeat();
  }

  // ── Injector heartbeat ───────────────────────────────────────────
  // Reports liveness + cumulative work counters every 5s. If heartbeat stops,
  // the injector is frozen (JS stuck). If counters spike, the patcher is the
  // bottleneck. `inFlight` guard prevents ticks from piling up if the CDP
  // channel is slow.
  function startInjectorHeartbeat() {
    if (window.__codexPlusHeartbeatStarted) return;
    window.__codexPlusHeartbeatStarted = true;
    const tick = () => {
      if (codexPlusHeartbeatInFlight) return;
      codexPlusHeartbeatInFlight = true;
      try {
        const detail = {
          uptimeMs: Date.now() - codexPlusBootstrapTime,
          patchStats: {
            json: window.__codexPlusModelJsonResponsePatchInstalled === "1" ? 1 : 0,
            statsig: typeof window.__STATSIG__ !== "undefined" ? 1 : 0,
            appserverMsg: window.__codexPlusModelMessagePatchInstalled ? 1 : 0,
            appserverReq: window.__codexPlusAppServerModelRequestPatchInstalled === codexAppServerModelRequestPatchVersion ? 1 : 0,
          },
          graphPatchCalls: codexPlusGraphPatchCalls,
          graphPatchNodes: codexPlusGraphPatchNodes,
          reactNodesScanned: codexPlusReactNodesScanned,
          reactFibersScanned: codexPlusReactFibersScanned,
          pendingBridgeCalls: window.__codexSessionDeletePending ? window.__codexSessionDeletePending.size : 0,
          jsErrorsCaptured: window.__codexPlusJsErrors ? window.__codexPlusJsErrors.length : 0,
        };
        window.__codexSessionDeleteBridge("/cdp/diagnostic", JSON.stringify({ event: "injector_heartbeat", detail: detail }))
          .catch(() => {})
          .finally(() => { codexPlusHeartbeatInFlight = false; });
      } catch (_) {
        codexPlusHeartbeatInFlight = false;
      }
    };
    tick();
    setInterval(tick, 5000);
  }

  // ── Bootstrap ─────────────────────────────────────────────────────
  // ── Diagnostics (ported from Codex Plus Plus) ────────────────────
  function codexPlusBackendBase() {
    const port = codexPlusBackendSettings.proxyPort || 15721;
    return "http://127.0.0.1:" + port;
  }

  function sendCodexPlusDiagnostic(event, detail) {
    try {
      const payload = {
        event: event,
        detail: detail || {},
        location: window.location?.href || "",
        userAgent: navigator.userAgent || "",
        timestamp: new Date().toISOString(),
      };
      window.__codexSessionDeleteBridge("/cdp/diagnostic", JSON.stringify(payload)).catch(() => {});
    } catch (_) {}
  }

  sendCodexPlusDiagnostic("script_loaded", { version: "apibypass-1" });

  window.__codexPlusBackendSettings = codexPlusBackendSettings;

  // Poll settings and scan
  async function bootstrap() {
    await fetchBackendSettings();
    installPluginMarketplacePatch();  // Install marketplace unlock patch
    void bootstrapModelWhitelist();   // Install model whitelist patch (async)
    scan();
    // Schedule subsequent scans via MutationObserver + debounce (matches
    // CodexPlusPlus's scheduleScan pattern). A tight requestAnimationFrame
    // loop runs scanDeferred ~60fps; combined with spoofChatGPTAuthMethod's
    // React fiber traversal this freezes Codex on startup when
    // pluginEntryUnlock is enabled.
    let scanPending = false;
    function scheduleScan(mutations) {
      if (!shouldScheduleScan(mutations)) return;
      if (scanPending) return;
      scanPending = true;
      setTimeout(() => {
        scanPending = false;
        scan();
      }, 200);
    }
    function attachObserver() {
      window.__codexPlusScanObserver?.disconnect();
      window.__codexPlusScanObserver = new MutationObserver(scheduleScan);
      window.__codexPlusScanObserver.observe(document.body, { childList: true, subtree: true });
    }
    if (document.body) {
      attachObserver();
    } else {
      document.addEventListener("DOMContentLoaded", attachObserver);
    }
  }

  // Wait for document to be ready
  if (document.readyState === "loading") {
    document.addEventListener("DOMContentLoaded", () => bootstrap());
  } else {
    bootstrap();
  }

  // ── Settings refresh via postMessage ──────────────────────────────
  window.addEventListener("message", (event) => {
    if (event.data && event.data.type === "codexPlusSettingsUpdate") {
      codexPlusBackendSettings = event.data.settings || {};
      window.__codexPlusBackendSettings = codexPlusBackendSettings;
      codexPlusBackendSettingsLoaded = true;
    }
  });
})();
"""
