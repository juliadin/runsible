#!/usr/bin/env python3

import inspect
import os
import sys
import datetime
import time

import yaml

one_up = os.path.abspath(os.path.join(os.path.dirname(
    (inspect.currentframe().f_code.co_filename)), '..'))

confignames = ['runsible.yml']
searchpaths = ['./', one_up]

replace_map = {
    '__RUNSIBLE_HOME': one_up,
    '__DATE': datetime.datetime.now().isoformat(),
    '__TIMESTAMP': time.time()
}


def filenames(paths, names):
    for path in paths:
        for file in names:
            yield os.path.abspath(os.path.join(path, file))


def get_config():
    checked = []
    for file in filenames(searchpaths, confignames):
        if file not in checked:
            checked.append(file)
        else:
            continue
        if os.path.isfile(file):
            with open(file, 'r') as pointer:
                struct = yaml.safe_load(pointer)
                struct['__origin__'] = file
                replace_map['__CONFIG'] = file
                return struct
    raise IOError('Config file not found in {}'.format(', '.join(checked)))


if __name__ == '__main__':
    try:
        cfg = get_config()
        print('# config read from {}'.format(cfg['__origin__']))
        if 'environment' in cfg:
            print('# environment:')
            for key, value in cfg['environment'].items():
                for pattern, replacement in replace_map.items():
                    if pattern in str(value):
                        value = value.replace(pattern, replacement)
                print("export {}='{}'".format(key, value))
    except IOError as e_content:
        print("Error: {}".format(e_content))
        sys.exit(1)
