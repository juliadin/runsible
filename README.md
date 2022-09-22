# runsible
an ansible playbook runner yet to be documented

    runsible.sh - ansible-playbook launch wrapper - Version 1.8.2
    2022-09-22 by Julia Brunenberg

    Usage: ./runsible.sh ... 

        -L <name>
                Lock all operations after this flag using the given name. Jobs using 
                the same name will immediately fail to run. Use this e.g. to lock cron jobs
                against each other.
                Playbooks, up and download are always locked when this option is used - no matter where.
                Can be used multiple times to lock certain aspects of the platform.
                Works only for locking jobs locally.
        -l 
                before running a playbook, acquire a lock for running it
                playbooks wait 60 seconds for the lock and exit with 253
                if the lock can not be acquired. Existence of a lock file does not 
                necessarily mean the playbook is locked.
        -p <playbook> [-p <playbook>] ... 
                run named ansible playbooks - option can be repeated
                calls playbooks in the order mentioned in the arguments 
        -t <hostspec>/<rolespec> [-t <hostspec>/<rolespec>] ...
                run roles nanes in rolespec (role1,role2,role3) on hosts
                mentioned in hostspec (eg. vpngw*,http*,specific.host.name)
        -r <rolename>
                create directory structure for new role
        -u
                Upload current state of repository to git
        -m  <message>
                Use <message> as commit message
        -d
                Pull from git server before run
        -v
                run Ansible with '-v' - can be repeated
        -c
                cron mode - only output if something went wrong - use before -L or -l
        -C
                Run ansible in Check mode (all other aspects of this script ignore this option)
        -D
                Run ansible in Diff mode and output small changes
        -I
                Clean fact cache and remove hosts no longer in inventory
        -e
                Enter virtualenv and start a shell
        -i <inventory-file>
                Read ansible inventory from this file
        -f
                Set number of forks for Ansible
        -F
                Check fact cache for errors
        -U
                Update all pip modules in the created venv
        -P
                Package mode. Create archive of wrapper in current directory

        -h
                this message.

        Tab completion for -p and -t is available by
          ln -s '/home/jmr/src/runsible/runsible.sh' '/etc/bash_completion.d/runsible_complete_bash'
