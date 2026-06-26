/**
 * Model patching logic extracted from CDPInjectionScript.swift
 * for testing. After testing, sync changes back to the Swift file.
 */

/**
 * Creates a model patcher with injected dependencies.
 * @param {Object} deps - Dependencies
 * @param {Object} deps.catalog - Model catalog with models array
 * @param {Function} deps.shouldPatchModels - Returns true if patching enabled
 * @param {Function} deps.logDiagnostic - Diagnostic logging function
 * @returns {Object} Model patching functions
 */
function createModelPatcher(deps) {
  const { catalog = { models: [] }, shouldPatchModels = () => true, logDiagnostic = () => {} } = deps;

  // ── Model descriptor + array patching ─────────────────────────────
  function modelReasoningEfforts() {
    return ["minimal", "low", "medium", "high", "xhigh"].map((reasoningEffort) => ({
      reasoningEffort,
      description: `${reasoningEffort} effort`,
    }));
  }

  function findModelEntry(modelName) {
    const models = Array.isArray(catalog.models) ? catalog.models : [];
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
      description: catalog.provider_name || catalog.model_provider || "Custom model",
      hidden: false,
      isDefault: (catalog.default_model || catalog.model) === modelName,
      defaultReasoningEffort: "medium",
      supportedReasoningEfforts: reasoningEfforts,
    };
  }

  function modelArrayLooksPatchable(value, allowEmpty) {
    return (
      Array.isArray(value) &&
      (allowEmpty || value.length > 0) &&
      value.every((item) => item && typeof item === "object" && typeof item.model === "string")
    );
  }

  function stringArrayLooksPatchable(value) {
    return Array.isArray(value) && value.every((item) => typeof item === "string");
  }

  function codexPlusModelNames() {
    const models = Array.isArray(catalog.models) ? catalog.models : [];
    // Config uses "slug" field as model ID; fall back to "model" for compatibility
    return Array.from(
      new Set(
        models
          .map((entry) => entry?.slug || entry?.model)
          .filter((name) => typeof name === "string" && name.length > 0)
      )
    );
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

  function patchModelContainer(value) {
    try {
      if (!value || typeof value !== "object") return false;
      const names = codexPlusModelNames();
      if (!names.length) return false;
      let changed = false;

      if (patchModelArray(value.models, "defaultModel" in value || "availableModels" in value)) changed = true;
      if (patchModelNameArray(value.models)) changed = true; // CPP-aligned: also patch string arrays
      if (patchModelArray(value.data)) changed = true;
      if (patchModelArray(value.result)) changed = true;
      if (patchModelArray(value.pages?.[0]?.data)) changed = true;
      if (patchModelArray(value.result?.data)) changed = true;
      if (patchModelArray(value.result?.models)) changed = true;
      if (patchModelArray(value.message?.result?.data)) changed = true;
      if (patchModelArray(value.message?.result?.models)) changed = true;

      // Create models array if container has model-related fields but no models array
      // This handles the case where Codex returns { defaultModel: {...} } without models array
      if (
        value.models == null &&
        (value.defaultModel != null || value.availableModels != null || value.available_models != null) &&
        names.length > 0
      ) {
        value.models = names.map((name) => codexPlusModelDescriptor(name));
        changed = true;
      }

      // availableModels / available_models (CPP-aligned: patch these)
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
        if (value.hiddenModels.length !== before) changed = true;
      }
      if (Array.isArray(value.hidden_models)) {
        const before = value.hidden_models.length;
        value.hidden_models = value.hidden_models.filter((name) => !names.includes(name));
        if (value.hidden_models.length !== before) changed = true;
      }

      // CPP-aligned: set defaultModel if not present
      // Only set if container already has model-related fields
      const hasModelFields =
        value.models != null ||
        value.availableModels != null ||
        value.available_models != null ||
        value.defaultModel != null ||
        value.model != null;
      if (value.defaultModel == null && names.length > 0 && hasModelFields) {
        value.defaultModel = codexPlusModelDescriptor(names[0]);
        changed = true;
      } else if (
        typeof value.defaultModel === "string" &&
        names.includes(value.defaultModel) &&
        value.model == null
      ) {
        value.model = value.defaultModel;
        changed = true;
      }

      return changed;
    } catch {
      return false;
    }
  }

  function patchObjectGraphForModels(root, visited, depth = 0) {
    try {
      if (!root || typeof root !== "object" || visited.has(root) || depth > 5) return false;
      visited.add(root);
      let changed = patchModelContainer(root);
      if (
        root instanceof Element ||
        root === (typeof window !== "undefined" ? window : null) ||
        root === (typeof document !== "undefined" ? document : null) ||
        root === (typeof document !== "undefined" ? document.body : null) ||
        root === (typeof document !== "undefined" ? document.documentElement : null)
      )
        return changed;
      for (const key of Object.keys(root)) {
        if (
          key === "ownerDocument" ||
          key === "parentElement" ||
          key === "parentNode" ||
          key === "children" ||
          key === "childNodes"
        )
          continue;
        let value;
        try {
          value = root[key];
        } catch {
          continue;
        }
        if (value && typeof value === "object" && patchObjectGraphForModels(value, visited, depth + 1))
          changed = true;
      }
      return changed;
    } catch {
      return false;
    }
  }

  function patchMcpModelResponseData(data, requestIds = new Set()) {
    try {
      if (data?.type !== "mcp-response") return false;
      const message = data.message || data.response;
      const requestId = message?.id != null ? String(message.id) : "";
      if (requestIds.size > 0 && !requestIds.has(requestId)) return false;
      requestIds.delete(requestId);
      return (
        patchModelContainer(data) ||
        patchModelContainer(message) ||
        patchModelContainer(message?.result) ||
        patchModelContainer(message?.result?.data)
      );
    } catch {
      return false;
    }
  }

  function patchAppServerModelResult(method, result) {
    // CPP-aligned: only handle "list-models-for-host"
    if (method !== "list-models-for-host") return result;
    try {
      if (!shouldPatchModels()) return result;
      if (Array.isArray(result)) patchModelArray(result, true);
      if (Array.isArray(result?.data)) patchModelArray(result.data, true);
      if (Array.isArray(result?.models)) patchModelArray(result.models, true);
      patchModelContainer(result);
      patchObjectGraphForModels(result, new WeakSet(), 0);
      logDiagnostic("model_app_server_result_patched", {
        method,
        modelCount: Array.isArray(result?.data)
          ? result.data.length
          : Array.isArray(result?.models)
            ? result.models.length
            : Array.isArray(result)
              ? result.length
              : null,
      });
    } catch (error) {
      logDiagnostic("model_patch_error", { error: String(error?.stack || error) });
    }
    return result;
  }

  return {
    modelReasoningEfforts,
    codexPlusModelDescriptor,
    modelArrayLooksPatchable,
    stringArrayLooksPatchable,
    codexPlusModelNames,
    patchModelNameArray,
    patchModelArray,
    patchModelContainer,
    patchObjectGraphForModels,
    patchMcpModelResponseData,
    patchAppServerModelResult,
  };
}

module.exports = { createModelPatcher };
