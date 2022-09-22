#!/usr/bin/env python3
"""
Ansible fact survey tool. see interactive help for more info
"""

# pylint: disable=locally-disabled, multiple-statements, fixme, line-too-long

import sys
import os
import fnmatch
import argparse
import csv
import json

from dir_tools import readable_dir, temp_dir
from matter_of_fact import load_facts


def deep_get(dict_data, key_path, sep='/', order=False, lookup_value=None, stack=[]):
    """
    Recursive generator for items that match the pattern components
    """
    keylist = key_path.split(sep)
    if len(keylist) < 2:
        filtered = fnmatch.filter(dict_data.keys(), keylist[0])
        if filtered:
            for match in filtered:
                try:
                    my_stack = [x for x in stack]
                    my_stack.append(match)
                    res = dict_data.get(match)

                    if res is None:
                        if not args.suppress_none:
                            yield 'none'
                    else:
                        if lookup_value:
                            if not fnmatch.fnmatch(str(res), lookup_value):
                                continue
                        if order:
                            res = "JSON__{}".format(
                                json.dumps([res, sep.join(my_stack)]))
                            yield res
                        else:
                            yield str(res)
                except AttributeError:
                    if not args.suppress_none:
                        yield 'none'
        else:
            if not args.suppress_none:
                yield 'none'
    else:
        filtered = fnmatch.filter(dict_data.keys(), keylist[0])
        if filtered:
            for match in filtered:
                inner_data = dict_data.get(match)
                inner_keys = sep.join(keylist[1:])
                try:
                    my_stack = stack.copy()
                    my_stack.append(match)
                    for generator in deep_get(inner_data, inner_keys, sep, order, lookup_value, my_stack):
                        yield generator
                except AttributeError:
                    if not args.suppress_none:
                        yield 'none'
        else:
            if not args.suppress_none:
                yield 'none'


def store(data_store, data_key, stored_value):
    """
    Store items in a dict of lists if they are not already there
    """
    if data_key in data_store:
        if stored_value not in data_store[data_key]:
            data_store[data_key].append(stored_value)
    else:
        data_store[data_key] = [stored_value]


ap = argparse.ArgumentParser(
    "Fact survey tool", formatter_class=argparse.ArgumentDefaultsHelpFormatter)
ap.add_argument("-f", "--facts", required=False, type=readable_dir,
                default='./fact_cache', help="Path to facts_cache")
ap.add_argument('-x', '--separator', required=False, type=str,
                default='/', help="change the separator")
ap.add_argument('-s', '--summarize', required=False,
                action="store_true", default=False, help="only count hits")
ap.add_argument('-t', '--terse', required=False, action="store_true",
                default=False, help="print all matching systems in ine line")
ap.add_argument('-n', '--suppress-none', required=False, action="store_true", default=False,
                help="suppress 'none' hits that may come from the key missing or conversion failing")
ap.add_argument('-o', '--order-by-key', required=False, action="store_true", default=False,
                help="When sorting results, add key to result. Useful when using wildcards.")
ap.add_argument("-v", "--value", required=False, type=str,
                help="filter values. Wildcards allowed.")
ap.add_argument("-k", "--key", required=True, type=str,
                help="search path. use the separator to separate recursion in dicts. wildcards are allowed each level.")
ap.add_argument("-C", "--cache-dir", required=False, type=temp_dir,
                default='.pickle_facts', help="path for caching facts as pickle files.")
ap.add_argument("-c", "--csv", required=False, action='store_true',
                default=False, help="produce CSV output")
args = ap.parse_args()

collect = {}
for root, dirs, files in os.walk(args.facts):
    for file in files:
        full_file = os.path.join(root, file)
        try:
            structure = load_facts(full_file, cache_dir=args.cache_dir)
        except TypeError:
            print("No parser could open file '{}'".format(full_file))
            sys.exit(1)
        except OSError as e_content:
            print("Could not open file '{}': {}".format(full_file, e_content))
            sys.exit(2)

        needles = deep_get(structure, args.key, args.separator,
                           args.order_by_key, args.value)
        for needle in needles:
            store(collect, needle, file)

    break

data = sorted(collect.items(), key=lambda x: len(x[1]))

if args.csv:
    out = csv.writer(sys.stdout)
    if args.summarize:
        out.writerow(['value', 'matches'])
        for key, values in data:
            out.writerow([key, len(values)])
    else:
        out.writerow(['path', 'value', 'match'])
        for key, values in data:
            if args.order_by_key:
                ATTR_PATH = ''
                if key[0:6] == "JSON__":
                    key, ATTR_PATH = json.loads(key[6:])
            else:
                ATTR_PATH = args.key
            for value in values:
                out.writerow([ATTR_PATH, key, value])
else:
    for key, values in data:
        ATTR_PATH = None
        if key[0:6] == "JSON__":
            key, ATTR_PATH = json.loads(key[6:])
        if args.summarize:
            if ATTR_PATH is not None:
                print("{} == {}: {}".format(ATTR_PATH, key, len(values)))
            else:
                print("{}: {}".format(key, len(values)))
        else:
            if ATTR_PATH is not None:
                print("{} == {}:".format(ATTR_PATH, key))
            else:
                print("{}:".format(key))
            if args.terse:
                print("  {}".format(", ".join(values)))
            else:
                for value in sorted(values):
                    print("  {}".format(value))
            print('')

sys.exit(0)
