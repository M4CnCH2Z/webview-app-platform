import eslintPluginJs from "@eslint/js";
import tseslint from "typescript-eslint";

export default tseslint.config(
  eslintPluginJs.configs.recommended,
  ...tseslint.configs.recommended,
  {
    languageOptions: {
      parserOptions: {
        ecmaVersion: "latest",
        sourceType: "module"
      }
    },
    rules: {
      "no-console": ["warn", { allow: ["warn", "error"] }]
    }
  }
);
