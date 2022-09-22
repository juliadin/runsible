#!/usr/bin/env python3
"""
import a yaml file and return - if it loads, 1 if it doesnt.
"""


import argparse
import sys
from matter_of_fact import load_facts
from dir_tools import temp_dir

ap = argparse.ArgumentParser("Checker for fact yaml files")
ap.add_argument("-f", "--file", required=True, type=str)
ap.add_argument("-q", "--quiet", required=False,
                action="store_true", default=False)
ap.add_argument("-c", "--cache-dir", required=False, type=temp_dir)

args = ap.parse_args()

try:
    load_facts(args.file)
except TypeError:
    if not args.quiet:
        print("No parser could load the file: {}".format(args.file))
        sys.exit(1)
except OSError as e_content:
    if not args.quiet:
        print("Could not open file '{}': {}".format(args.file, e_content))
        sys.exit(2)

if not args.quiet:
    print("File '{}' parsed correctly.".format(args.file))
    if args.cache_dir:
        if not args.quiet:
            print("Updating cache for file {} in {}".format(
                args.file, args.cache_dir))
        load_facts(args.file, cache_dir=args.cache_dir)

sys.exit(0)
