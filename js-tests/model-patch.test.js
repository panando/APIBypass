/**
 * Tests for model patching logic
 * These tests verify the CPP-aligned behavior
 */

const { createModelPatcher } = require("./model-patch.js");

describe("createModelPatcher", () => {
  let patcher;
  let catalog;
  let diagnosticLogs;

  beforeEach(() => {
    // Catalog structure matches ModelCatalog.swift
    // model = slug (unique identifier)
    // displayName = display name
    catalog = {
      models: [
        { model: "deepseek-v4-flash", displayName: "DeepSeek-Flash" },
        { model: "glm-5-qf", displayName: "GLM-5" },
      ],
      provider_name: "Test Provider",
      default_model: "deepseek-v4-flash",
    };
    diagnosticLogs = [];
    patcher = createModelPatcher({
      catalog,
      shouldPatchModels: () => true,
      logDiagnostic: (event, data) => diagnosticLogs.push({ event, data }),
    });
  });

  describe("patchAppServerModelResult", () => {
    it("should only process 'list-models-for-host' method (CPP-aligned)", () => {
      const result = { data: [{ model: "gpt-4", name: "GPT-4" }] };

      // Should NOT patch for "model/list"
      const result1 = patcher.patchAppServerModelResult("model/list", result);
      expect(result1.data.length).toBe(1); // unchanged

      // Should patch for "list-models-for-host" - replaces built-in with custom
      const result2 = patcher.patchAppServerModelResult("list-models-for-host", {
        data: [{ model: "gpt-4", name: "GPT-4" }],
      });
      expect(result2.data.length).toBe(2); // only 2 custom models (replaced gpt-4)
    });

    it("should replace built-in models with custom models", () => {
      const result = {
        data: [{ model: "gpt-4", name: "GPT-4", hidden: false }],
      };

      patcher.patchAppServerModelResult("list-models-for-host", result);

      // Should have only 2 custom models (replaced gpt-4)
      expect(result.data.length).toBe(2);
      const modelIds = result.data.map((m) => m.model);
      expect(modelIds).toContain("deepseek-v4-flash");
      expect(modelIds).toContain("glm-5-qf");
      expect(modelIds).not.toContain("gpt-4");
    });

    it("should NOT add duplicate models when called multiple times", () => {
      const result = {
        data: [{ model: "gpt-4", name: "GPT-4", hidden: false }],
      };

      // Call twice
      patcher.patchAppServerModelResult("list-models-for-host", result);
      patcher.patchAppServerModelResult("list-models-for-host", result);

      // Should still have 2 custom models, not more
      expect(result.data.length).toBe(2);
    });
  });

  describe("patchModelArray", () => {
    it("should replace built-in models with custom models", () => {
      const models = [{ model: "gpt-4", name: "GPT-4" }];

      patcher.patchModelArray(models, false);

      // Should have only 2 custom models (replaced gpt-4)
      expect(models.length).toBe(2);
      const modelIds = models.map((m) => m.model);
      expect(modelIds).toContain("deepseek-v4-flash");
      expect(modelIds).toContain("glm-5-qf");
      expect(modelIds).not.toContain("gpt-4"); // Built-in model should be removed
    });

    it("should keep only custom models", () => {
      const models = [
        { model: "gpt-4", name: "GPT-4" },
        { model: "claude-3", name: "Claude 3" },
      ];

      patcher.patchModelArray(models, false);

      // Should have only 2 custom models
      expect(models.length).toBe(2);
      const modelIds = models.map((m) => m.model);
      expect(modelIds).toContain("deepseek-v4-flash");
      expect(modelIds).toContain("glm-5-qf");
    });

    it("should not add duplicate custom models", () => {
      const models = [
        { model: "deepseek-v4-flash", name: "DeepSeek-Flash" },
      ];

      patcher.patchModelArray(models, false);

      // Should still be 2 (not 3)
      expect(models.length).toBe(2);
    });

    it("should return false for non-array input", () => {
      expect(patcher.patchModelArray(null, false)).toBe(false);
      expect(patcher.patchModelArray({}, false)).toBe(false);
      expect(patcher.patchModelArray("string", false)).toBe(false);
    });

    it("should return false for array with non-model objects", () => {
      expect(patcher.patchModelArray([1, 2, 3], false)).toBe(false);
      expect(patcher.patchModelArray([{ foo: "bar" }], false)).toBe(false);
    });
  });

  describe("patchModelNameArray", () => {
    it("should add custom model names to string array", () => {
      const models = ["gpt-4", "claude-3"];

      patcher.patchModelNameArray(models);

      expect(models).toContain("gpt-4");
      expect(models).toContain("claude-3");
      // codexPlusModelNames() returns model field (slug)
      expect(models).toContain("deepseek-v4-flash");
      expect(models).toContain("glm-5-qf");
    });

    it("should not add duplicates", () => {
      const models = ["gpt-4", "deepseek-v4-flash"];

      patcher.patchModelNameArray(models);

      // Count occurrences of "deepseek-v4-flash"
      const count = models.filter((m) => m === "deepseek-v4-flash").length;
      expect(count).toBe(1);
    });
  });

  describe("patchModelContainer", () => {
    it("should replace built-in models with custom models in value.models", () => {
      const container = {
        models: [{ model: "gpt-4", name: "GPT-4" }],
      };

      patcher.patchModelContainer(container);

      expect(container.models.length).toBe(2);
      expect(container.models.map((m) => m.model)).not.toContain("gpt-4");
    });

    it("should replace built-in models with custom models in value.data", () => {
      const container = {
        data: [{ model: "gpt-4", name: "GPT-4" }],
      };

      patcher.patchModelContainer(container);

      expect(container.data.length).toBe(2);
      expect(container.data.map((m) => m.model)).not.toContain("gpt-4");
    });

    it("should replace built-in models in nested result.data", () => {
      const container = {
        result: {
          data: [{ model: "gpt-4", name: "GPT-4" }],
        },
      };

      patcher.patchModelContainer(container);

      expect(container.result.data.length).toBe(2);
    });

    it("should patch availableModels array (CPP-aligned)", () => {
      const container = {
        availableModels: ["gpt-4"],
      };

      patcher.patchModelContainer(container);

      expect(container.availableModels).toContain("gpt-4");
      // codexPlusModelNames() returns model field (slug)
      expect(container.availableModels).toContain("deepseek-v4-flash");
      expect(container.availableModels).toContain("glm-5-qf");
    });

    it("should patch available_models Set (CPP-aligned)", () => {
      const container = {
        available_models: new Set(["gpt-4"]),
      };

      patcher.patchModelContainer(container);

      expect(container.available_models.has("gpt-4")).toBe(true);
      expect(container.available_models.has("deepseek-v4-flash")).toBe(true);
      expect(container.available_models.has("glm-5-qf")).toBe(true);
    });

    it("should set defaultModel if not present (CPP-aligned)", () => {
      const container = {
        models: [{ model: "gpt-4", name: "GPT-4" }],
      };

      patcher.patchModelContainer(container);

      expect(container.defaultModel).toBeDefined();
      // codexPlusModelNames() returns model field (slug), first is "deepseek-v4-flash"
      expect(container.defaultModel.model).toBe("deepseek-v4-flash");
    });

    it("should remove custom models from hiddenModels", () => {
      const container = {
        models: [{ model: "gpt-4", name: "GPT-4" }],
        hiddenModels: ["deepseek-v4-flash", "glm-5-qf", "some-other"],
      };

      patcher.patchModelContainer(container);

      expect(container.hiddenModels).not.toContain("deepseek-v4-flash");
      expect(container.hiddenModels).not.toContain("glm-5-qf");
      expect(container.hiddenModels).toContain("some-other");
    });
  });

  describe("patchMcpModelResponseData", () => {
    it("should patch mcp-response data", () => {
      const data = {
        type: "mcp-response",
        message: {
          result: {
            data: [{ model: "gpt-4", name: "GPT-4" }],
          },
        },
      };

      patcher.patchMcpModelResponseData(data);

      // Should replace built-in with custom models
      expect(data.message.result.data.length).toBe(2);
      expect(data.message.result.data.map((m) => m.model)).not.toContain("gpt-4");
    });

    it("should return false for non-mcp-response", () => {
      const data = { type: "other" };

      expect(patcher.patchMcpModelResponseData(data)).toBe(false);
    });
  });

  describe("codexPlusModelDescriptor", () => {
    it("should create descriptor with correct properties", () => {
      const descriptor = patcher.codexPlusModelDescriptor("deepseek-v4-flash");

      expect(descriptor.model).toBe("deepseek-v4-flash");
      expect(descriptor.id).toBe("deepseek-v4-flash");
      expect(descriptor.displayName).toBe("DeepSeek-Flash");
      expect(descriptor.hidden).toBe(false);
      expect(descriptor.defaultReasoningEffort).toBe("medium");
      expect(descriptor.supportedReasoningEfforts).toHaveLength(5);
    });

    it("should set isDefault correctly", () => {
      const defaultDesc = patcher.codexPlusModelDescriptor("deepseek-v4-flash");
      const nonDefaultDesc = patcher.codexPlusModelDescriptor("glm-5-qf");

      expect(defaultDesc.isDefault).toBe(true);
      expect(nonDefaultDesc.isDefault).toBe(false);
    });

    it("should read snake_case fields from config (slug, display_name, supported_reasoning_levels)", () => {
      // Test with actual config format
      const snakeCaseCatalog = {
        models: [
          {
            slug: "glm-5-qf",
            display_name: "GLM-5",
            supported_reasoning_levels: [
              { effort: "low", description: "Fast" },
              { effort: "medium", description: "Balanced" },
            ],
          },
        ],
        provider_name: "Test",
      };
      const snakePatcher = createModelPatcher({ catalog: snakeCaseCatalog });

      const descriptor = snakePatcher.codexPlusModelDescriptor("glm-5-qf");
      expect(descriptor.model).toBe("glm-5-qf");
      expect(descriptor.displayName).toBe("GLM-5");
      expect(descriptor.supportedReasoningEfforts).toHaveLength(2);
      expect(descriptor.supportedReasoningEfforts[0]).toEqual({
        reasoningEffort: "low",
        description: "Fast",
      });
    });
  });

  describe("modelReasoningEfforts", () => {
    it("should return array of reasoning effort objects", () => {
      const efforts = patcher.modelReasoningEfforts();

      expect(efforts).toHaveLength(5);
      expect(efforts[0]).toEqual({ reasoningEffort: "minimal", description: "minimal effort" });
    });
  });
});
