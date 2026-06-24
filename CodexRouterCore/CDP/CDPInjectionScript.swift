// MARK: - Ported injection JavaScript for plugin entry unlock and force install

/// The complete injection script, ported from CodexPlusPlus renderer-inject.js.
/// Contains only the plugin entry unlock and force plugin install features.
public let codexPluginInjectionScript: String = """
(function() {
  "use strict";

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
      const resp = await fetch("http://127.0.0.1:15721/settings/get");
      if (resp.ok) {
        const data = await resp.json();
        codexPlusBackendSettings = data;
        codexPlusBackendSettingsLoaded = true;
        window.__codexPlusBackendSettings = data;
      }
    } catch (_) {}
  }

  // ── Model Whitelist Unlock ────────────────────────────────────────
  let codexModelCatalog = { status: "loading", models: [] };
  let codexModelCatalogLoadedAt = 0;
  let codexModelCatalogPromise = null;
  const codexModelCatalogCacheMs = 10000;

  function shouldPatchModels() {
    if (pluginPatchDisabledInRelayMode()) return false;
    if (codexPlusBackendSettings.modelProvider === "chatgpt") return false;
    return codexPlusSettings().modelWhitelistUnlock;
  }

  function codexPlusModelNames() {
    const models = Array.isArray(codexModelCatalog.models) ? codexModelCatalog.models : [];
    return Array.from(new Set(models.map((entry) => entry?.displayName || entry?.model).filter((name) => typeof name === "string" && name.length > 0)));
  }

  async function loadCodexModelCatalog(force = false) {
    if (!force && codexModelCatalogPromise) return codexModelCatalogPromise;
    if (!force && codexModelCatalogLoadedAt && Date.now() - codexModelCatalogLoadedAt < codexModelCatalogCacheMs) return codexModelCatalog;
    codexModelCatalogPromise = fetch("http://127.0.0.1:15721/codex-model-catalog")
      .then((resp) => resp.json())
      .then((result) => {
        codexModelCatalog = result && typeof result === "object" && Array.isArray(result.models)
          ? result
          : { status: "failed", models: [] };
        codexModelCatalogLoadedAt = Date.now();
        return codexModelCatalog;
      })
      .catch(() => {
        codexModelCatalog = { status: "failed", models: [] };
        codexModelCatalogLoadedAt = Date.now();
        return codexModelCatalog;
      })
      .finally(() => {
        codexModelCatalogPromise = null;
      });
    return codexModelCatalogPromise;
  }

  function patchStatsigModelDynamicConfig(config) {
    try {
      const names = codexPlusModelNames();
      const value = config?.value;
      if (!names.length || !value || typeof value !== "object") return config;
      const availableModels = Array.isArray(value.available_models) ? [...value.available_models] : [];
      let changed = false;
      names.forEach((name) => {
        if (!availableModels.includes(name)) {
          availableModels.push(name);
          changed = true;
        }
      });
      if (!changed) return config;
      const nextValue = { ...value, available_models: availableModels };
      try {
        config.value = nextValue;
      } catch {
        return { ...config, value: nextValue };
      }
      return config;
    } catch {
      return config;
    }
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
      statsigClients().forEach((client) => {
        if (typeof client.getDynamicConfig !== "function") return;
        if (!client.__codexPlusModelWhitelistPatched) {
          const originalGetDynamicConfig = client.getDynamicConfig.bind(client);
          client.getDynamicConfig = (name, options) => {
            const result = originalGetDynamicConfig(name, options);
            return patchStatsigModelDynamicConfig(result);
          };
          client.__codexPlusModelWhitelistPatched = true;
        }
        try {
          patchStatsigModelDynamicConfig(client.getDynamicConfig("107580212", { disableExposureLog: true }));
        } catch (_) {}
      });
    } catch (_) {}
  }

  // ── React State Patch (fallback) ──────────────────────────────────
  function patchModelNameArray(models) {
    try {
      if (!Array.isArray(models) || models.length === 0) return false;
      if (!models.every((item) => typeof item === "string")) return false;
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

  function patchModelContainer(value) {
    try {
      if (!value || typeof value !== "object") return false;
      const names = codexPlusModelNames();
      if (!names.length) return false;
      let changed = false;
      if (value.availableModels instanceof Set) {
        names.forEach((name) => { if (!value.availableModels.has(name)) { value.availableModels.add(name); changed = true; } });
      }
      if (value.available_models instanceof Set) {
        names.forEach((name) => { if (!value.available_models.has(name)) { value.available_models.add(name); changed = true; } });
      }
      if (Array.isArray(value.availableModels)) {
        names.forEach((name) => { if (!value.availableModels.includes(name)) { value.availableModels.push(name); changed = true; } });
      }
      if (Array.isArray(value.available_models)) {
        names.forEach((name) => { if (!value.available_models.includes(name)) { value.available_models.push(name); changed = true; } });
      }
      if (Array.isArray(value.models) && value.models.length > 0 && value.models.every((item) => typeof item === "string")) {
        if (patchModelNameArray(value.models)) changed = true;
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

  function patchReactModelState() {
    if (!shouldPatchModels()) return;
    if (!codexPlusModelNames().length) return;
    try {
      const selector = "[role='menu'], [role='dialog'], [role='listbox'], [data-radix-popper-content-wrapper]";
      const nodes = [document.body, ...document.querySelectorAll(selector)];
      nodes.forEach((node) => {
        if (!node) return;
        patchObjectGraphForModels(node, new WeakSet(), 0);
      });
    } catch (_) {}
  }

  let modelWhitelistMutationObserver = null;
  function startModelWhitelistObserver() {
    if (!shouldPatchModels()) return;
    if (modelWhitelistMutationObserver) return;
    try {
      modelWhitelistMutationObserver = new MutationObserver(() => {
        patchReactModelState();
      });
      modelWhitelistMutationObserver.observe(document.body, { childList: true, subtree: true });
    } catch (_) {}
  }

  async function bootstrapModelWhitelist() {
    await loadCodexModelCatalog();
    if (!shouldPatchModels()) return;
    patchStatsigModelWhitelist();
    patchReactModelState();
    startModelWhitelistObserver();
  }

  // ── Bootstrap ─────────────────────────────────────────────────────
  window.__codexPlusBackendSettings = codexPlusBackendSettings;

  // Poll settings and scan
  async function bootstrap() {
    await fetchBackendSettings();
    installPluginMarketplacePatch();  // Install marketplace unlock patch
    void bootstrapModelWhitelist();   // Install model whitelist patch (async)
    scan();
    // Continue scanning on every animation frame
    function loop() {
      scan();
      requestAnimationFrame(loop);
    }
    requestAnimationFrame(loop);
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
