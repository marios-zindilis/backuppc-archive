backuppc-archive
================

This is a script that maintains archive copies of backups taken with 
[BackupPC](http://backuppc.sourceforge.net/).

It can be used to keep offsite backups to a remote location, for compliance 
to regulations or for disaster recovery.

This code is released under GPLv2, as is BackupPC itself. For more details, 
see the `LICENSE` file distributed with this code.

Usage
-----

The `backuppc-archive` script runs as a service, and accepts standard 
`service backuppc-archive start|stop|status|restart` commands. You can copy the 
script directly in `/etc/init.d/`, enable the service with:

         chkconfig backuppc-archive on

...and start it with:

        service backuppc-archive start

