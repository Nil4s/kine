"""The reference: python jsonschema (Draft 2020-12) over the same files tests/schema_test.gd validated.
argv: the schema, then the files. Prints one JSON line: {file: [[json_path, message], ...]}."""
import json, sys
import jsonschema
s = json.load(open(sys.argv[1], encoding='utf-8'))
v = jsonschema.Draft202012Validator(s)
out = {}
for f in sys.argv[2:]:
    out[f] = [[e.json_path, e.message[:200]] for e in v.iter_errors(json.load(open(f, encoding='utf-8')))]
print(json.dumps(out))
