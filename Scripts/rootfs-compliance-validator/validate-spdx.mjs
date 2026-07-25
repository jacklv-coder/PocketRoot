import { readFile } from "node:fs/promises";
import process from "node:process";
import Ajv from "ajv";

const [schemaPath, documentPath] = process.argv.slice(2);

if (!schemaPath || !documentPath) {
  console.error("usage: node validate-spdx.mjs SCHEMA DOCUMENT");
  process.exit(2);
}

const [schema, document] = await Promise.all(
  [schemaPath, documentPath].map(async (path) =>
    JSON.parse(await readFile(path, "utf8")),
  ),
);

const ajv = new Ajv({ allErrors: true, strict: false });
const validate = ajv.compile(schema);

if (!validate(document)) {
  console.error(ajv.errorsText(validate.errors, { separator: "\n" }));
  process.exit(1);
}

console.log(`${documentPath} is valid`);
