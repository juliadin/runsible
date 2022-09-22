#!/usr/bin/env python3
"""
Collection of modules to handle fact files
"""

import os
import pickle  # nosec B403

try:
    import pylibyaml
except ModuleNotFoundError:
    pass
import yaml


def load_yaml(fact_file):
    """
    Try to load fact file as yaml
    """
    try:
        with open(fact_file, 'r') as fact_fd:
            return yaml.safe_load(fact_fd)
    except yaml.parser.ParserError:
        return None
    except OSError:
        return None


def load_pickle(fact_file):
    """
    Try to load fact file as pickle
    """
    try:
        with open(fact_file, 'rb') as fact_fd:
            return pickle.load(fact_fd)  # nosec B301
    except pickle.PickleError:
        return None
    except OSError:
        return None


def no_matter_what(fact_file):
    """
    Try to load a fact file no matter which format it is in
    """
    parsers = [load_pickle, load_yaml]
    for parser in parsers:
        struct = parser(fact_file)
        if struct is not None:
            break
    if struct is None:
        raise TypeError('No parser was able to read the file')
    return struct


def load_facts(fact_file, cache_dir=None):
    """
    Load a fact file, creating a cache if required
    """
    file_name = os.path.basename(fact_file)
    cache_success = False

    if cache_dir is not None:
        cache_file = os.path.join(cache_dir, file_name)
        if os.path.isfile(cache_file) and os.stat(cache_file).st_mtime >= os.stat(fact_file).st_mtime:
            try:
                with open(cache_file, 'rb') as fp:
                    structure = pickle.load(fp)  # nosec B301
                cache_success = True
            except (OSError, pickle.PickleError):
                os.unlink(cache_file)

    if not cache_success:
        try:
            structure = no_matter_what(fact_file)
            if cache_dir is not None:
                with open(cache_file, 'wb') as fd:
                    pickle.dump(structure, fd)
        except TypeError as e_content:
            print("Could not open file '{}': {}".format(fact_file, e_content))
    return structure
