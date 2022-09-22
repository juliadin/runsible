#!/bin/bash
VERSION='1.8.2'
AUTHOR='Julia Brunenberg'
RELEASE_DATE='2022-09-22'
PRODUCT='runsible.sh - ansible-playbook launch wrapper'

RUNSIBLE_FACT_CACHE="${MYPATH}/.pickle_facts"

RUNSIBLE_RELEASE_FILES=(
    "runsible.sh"
    "runsible.example.yml"
    "requirements.txt"
    "galaxy-requirements.yml"
    "helpers/check_fact.py"
    "helpers/relative_paths.sh"
    "helpers/fact_survey.py"
    "helpers/matter_of_fact.py"
    "helpers/conf_to_env.py"
    "helpers/dir_tools.py"
    "helpers/check_requirements.py"
    "playbooks/__TEST.yml"
)

RUNSIBLE_TAR_FILES=( 
    "${RUNSIBLE_RELEASE_FILES[@]}"
    ".gitignore"
)