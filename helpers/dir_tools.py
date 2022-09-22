#!/use/bin/env python3 
"""
Module defining some useful tools for accepting directories in argparse
"""

import os

# taken from https://stackoverflow.com/questions/11415570/directory-path-types-with-argparse
def readable_dir(prospective_dir):
    """
    Test function for argparse to test if a path exists and fail out early
    """
    if not os.path.isdir(prospective_dir):
        raise Exception(
            "readable_dir:{0} is not a valid path".format(prospective_dir))
    if os.access(prospective_dir, os.R_OK):
        return prospective_dir
    raise Exception(
        "readable_dir:{0} is not a readable dir".format(prospective_dir))

def readable_file(prospective_file):
    """
    Test function for argparse to test if a path exists and fail out early
    """
    if not os.path.isdir(prospective_file):
        pass
    else:
        raise Exception(
            "readable_file:{0} is a directory".format(prospective_file))
    if os.access(prospective_file, os.R_OK):
        return prospective_file
    raise Exception(
        "readable_file:{0} is not a readable file".format(prospective_file))


def temp_dir(prospective_dir):
    """
    Test function for argparse to make sure a path exists
    """
    if not os.path.isdir(prospective_dir):
        os.mkdir(prospective_dir)
        return prospective_dir
    if os.access(prospective_dir, os.R_OK):
        return prospective_dir
    raise Exception(
        "readable_dir:{0} is not a readable dir".format(prospective_dir))
