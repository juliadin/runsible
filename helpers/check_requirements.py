#!/usr/bin/env python3
import sys
from pkg_resources import DistributionNotFound, VersionConflict, parse_requirements, require
from argparse import ArgumentParser
from dir_tools import readable_file


ap = ArgumentParser("offline requirement checker")

ap.add_argument( '-r', '--requirements', type=readable_file,
    help="path to requirements.txt", required=True)

args = ap.parse_args()

dependencies = []

with open(args.requirements, 'r') as fd:
    requirements = parse_requirements(fd)
    for requirement in requirements:
        dependencies.append( str(requirement) )
# here, if a dependency is not met, a DistributionNotFound or VersionConflict
# exception is thrown. 
try:
    require(dependencies)
except DistributionNotFound as e:
    print( "Requirement not satisfied: {}".format(e))
    sys.exit(1)
except VersionConflict as e:
    print( "Conflicting version error: {}".format(e))
    sys.exit(1)
except Exception as e:
    print( "Unknown error: {}".format(e))
    sys.exit(2)