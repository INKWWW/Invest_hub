import tsParser from "@typescript-eslint/parser";

export default [
  {
    ignores: [".next/**", "node_modules/**", "coverage/**"],
  },
  {
    files: ["**/*.ts", "**/*.tsx"],
    languageOptions: {
      parser: tsParser,
      parserOptions: {
        ecmaVersion: "latest",
        sourceType: "module",
        ecmaFeatures: { jsx: true },
      },
    },
    rules: {
      "no-constant-condition": "error",
      "no-duplicate-imports": "error",
      "no-unreachable": "error",
    },
  },
  {
    files: ["**/*.mjs", "**/*.js"],
    rules: {
      "no-constant-condition": "error",
      "no-duplicate-imports": "error",
      "no-unreachable": "error",
    },
  },
];

