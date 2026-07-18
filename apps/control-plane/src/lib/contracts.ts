import Ajv2020, { type ValidateFunction } from "ajv/dist/2020.js";
import addFormats from "ajv-formats";
import { readFileSync } from "node:fs";
import { resolve } from "node:path";

const ajv = new Ajv2020({ allErrors: true, strict: true });
addFormats(ajv);
const validators = new Map<string, ValidateFunction>();

function validatorFor(name: string): ValidateFunction {
  const existing = validators.get(name);
  if (existing) return existing;

  const schemaPath = resolve(process.cwd(), "contracts", "v0", `${name}.schema.json`);
  const schema = JSON.parse(readFileSync(schemaPath, "utf8")) as object;
  const validator = ajv.compile(schema);
  validators.set(name, validator);
  return validator;
}

export function parseContract<T>(name: string, value: unknown): T {
  const validator = validatorFor(name);
  if (!validator(value)) {
    throw new Error(`invalid ${name} contract: ${ajv.errorsText(validator.errors)}`);
  }
  return value as T;
}
