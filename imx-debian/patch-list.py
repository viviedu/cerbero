#!/usr/bin/env python3
# Print the Vivi patches the i.MX build applies, in order: each recipe's patches list, the imx/ files after base.
import ast
import glob
import os
import sys

recipes = sys.argv[1]
for module in ('base', 'good', 'bad'):
    name = 'gst-plugins-%s-1.0' % module
    tree = ast.parse(open(os.path.join(recipes, name + '.recipe')).read())
    # the class attribute "patches = [...]"; patches a recipe adds in code for one platform are not read
    lists = [ast.literal_eval(node.value)
             for cls in ast.walk(tree) if isinstance(cls, ast.ClassDef)
             for node in cls.body if isinstance(node, ast.Assign)
             and any(getattr(target, 'id', '') == 'patches' for target in node.targets)]
    if len(lists) != 1 or not lists[0]:
        sys.exit('%s.recipe: expected one non-empty patches list' % name)
    patches = list(lists[0])
    if module == 'base':
        imx = sorted(glob.glob(os.path.join(recipes, name, 'imx', '*.patch')))
        if not imx:
            sys.exit('no i.MX patches under %s/imx' % name)
        patches += [os.path.relpath(path, recipes) for path in imx]
    print('\n'.join(patches))
