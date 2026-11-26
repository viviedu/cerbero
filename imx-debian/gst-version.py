#!/usr/bin/env python3
# Print the GStreamer version the cerbero recipes build (class GStreamer in recipes/custom.py), so i.MX and Android share it.
import ast
import sys

tree = ast.parse(open(sys.argv[1]).read())
versions = [ast.literal_eval(node.value)
            for cls in ast.walk(tree) if isinstance(cls, ast.ClassDef) and cls.name == 'GStreamer'
            for node in cls.body if isinstance(node, ast.Assign)
            and any(getattr(target, 'id', '') == 'version' for target in node.targets)]
if len(versions) != 1:
    sys.exit('%s: expected one version in class GStreamer' % sys.argv[1])
print(versions[0])
