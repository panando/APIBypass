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
      const resp = await fetch(codexPlusBackendBase() + "/settings/get");
      if (resp.ok) {
        const data = await resp.json();
        codexPlusBackendSettings = data;
        codexPlusBackendSettingsLoaded = true;
        window.__codexPlusBackendSettings = data;
        sendCodexPlusDiagnostic("settings_loaded", {
          modelProvider: data.modelProvider || "",
          enhancementsEnabled: data.enhancementsEnabled,
        });
      }
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
    codexModelCatalogPromise = fetch(codexPlusBackendBase() + "/codex-model-catalog")
      .then((resp) => resp.json())
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
  function codexPlusModelDescriptor(modelName) {
    return {
      model: modelName,
      id: modelName,
      slug: modelName,
      name: modelName,
      displayName: modelName,
      description: "Custom model",
      hidden: false,
      isDefault: false,
      defaultReasoningEffort: "medium",
      supportedReasoningEfforts: ["minimal", "low", "medium", "high", "xhigh"],
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

  function patchModelArray(models, allowEmpty) {
    try {
      if (!modelArrayLooksPatchable(models, allowEmpty)) return false;
      const customModels = codexPlusModelNames();
      if (!customModels.length) return false;
      let changed = false;
      const existing = new Map(models.map((item) => [item.model, item]));
      models.forEach((item) => {
        if (customModels.includes(item.model) && item.hidden !== false) {
          item.hidden = false;
          changed = true;
        }
      });
      customModels.forEach((modelName) => {
        if (!existing.has(modelName)) {
          models.push(codexPlusModelDescriptor(modelName));
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
      if (patchModelArray(value.models, "defaultModel" in value || "availableModels" in value)) changed = true;
      if (patchModelNameArray(value.models)) changed = true;
      if (patchModelArray(value.data)) changed = true;
      if (patchModelArray(value.result)) changed = true;
      if (patchModelArray(value.pages?.[0]?.data)) changed = true;
      if (patchModelArray(value.result?.data)) changed = true;
      if (patchModelArray(value.result?.models)) changed = true;
      if (patchModelArray(value.message?.result?.data)) changed = true;
      if (patchModelArray(value.message?.result?.models)) changed = true;
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
      if (Array.isArray(value.hiddenModels)) {
        const before = value.hiddenModels.length;
        value.hiddenModels = value.hiddenModels.filter((name) => !names.includes(name));
        if (value.hiddenModels.length !== before) changed = true;
      }
      if (Array.isArray(value.hidden_models)) {
        const before = value.hidden_models.length;
        value.hidden_models = value.hidden_models.filter((name) => !names.includes(name));
        if (value.hidden_models.length !== before) changed = true;
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

  // ── Statsig SDK patch ─────────────────────────────────────────────
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
      let clientCount = 0;
      statsigClients().forEach((client) => {
        if (typeof client.getDynamicConfig !== "function") return;
        clientCount += 1;
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
      if (clientCount > 0) {
        sendCodexPlusDiagnostic("statsig_patch_installed", { clientCount: clientCount });
      }
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
    if (method !== "list-models-for-host" && method !== "model/list") return result;
    try {
      if (!shouldPatchModels()) return result;
      if (Array.isArray(result)) patchModelArray(result, true);
      if (Array.isArray(result?.data)) patchModelArray(result.data, true);
      if (Array.isArray(result?.models)) patchModelArray(result.models, true);
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
      for (const node of nodes.slice(0, 220)) {
        if (!node) continue;
        for (const key of Object.keys(node).filter((k) => k.startsWith("__reactFiber") || k.startsWith("__reactInternalInstance") || k.startsWith("__reactProps"))) {
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
    sendCodexPlusDiagnostic("model_whitelist_refresh_scheduled", { durationMs: durationMs });
    if (codexModelWhitelistRefreshTimer) return;
    const tick = () => {
      codexModelWhitelistRefreshTimer = 0;
      runCodexModelWhitelistRefreshPass();
      if (Date.now() < codexModelWhitelistRefreshUntil) {
        codexModelWhitelistRefreshTimer = window.setTimeout(tick, 120);
      }
    };
    tick();
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
      fetch(codexPlusBackendBase() + "/cdp/diagnostic", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify(payload),
        keepalive: true,
      }).catch(() => {});
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
