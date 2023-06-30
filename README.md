# V2C Demo
Demonstrate migrating "ESXi VM" to "K8S stateful container"  

```console
$ kubectl get po
NAME                             READY   STATUS      RESTARTS   AGE
1-get-vm-files-lamp-xwk4p        0/1     Completed   0          13m
2-load-root-volume-lamp-p2p7w    0/1     Completed   0          12m
3-prepare-container-lamp-bpfxr   0/1     Completed   0          5m7s
4-start-container-lamp-x96m4     0/1     Completed   0          5m
lamp-0                           1/1     Running     0          5m
```

```console
$ kubectl get job
NAME                       COMPLETIONS   DURATION   AGE
1-get-vm-files-lamp        1/1           72s        13m
2-load-root-volume-lamp    1/1           6m53s      12m
3-prepare-container-lamp   1/1           3s         5m43s
4-start-container-lamp     1/1           16s        5m36s
```

```console
$ kubectl exec -it sts/lamp -- ps -auxw
USER       PID %CPU %MEM    VSZ   RSS TTY      STAT START   TIME COMMAND
root         1  0.1  0.0  43340  3516 ?        Ss   02:38   0:00 /sbin/init
root        20  0.0  0.0  39060  3172 ?        Ss   02:38   0:00 /usr/lib/systemd/systemd-journald
root        40  0.0  0.0 168144  5036 ?        Ss   02:38   0:00 /usr/bin/VGAuthService -s
root        41  0.1  0.0 201356  4720 ?        Ssl  02:38   0:00 /usr/bin/vmtoolsd
root        43  0.0  0.0  21696  1316 ?        Ss   02:38   0:00 /usr/sbin/irqbalance --foreground
dbus        47  0.0  0.0  58120  2104 ?        Ss   02:38   0:00 /usr/bin/dbus-daemon --system --address=systemd: --nofork --nopidfi
root        65  0.0  0.0 126384  1600 ?        Ss   02:38   0:00 /usr/sbin/crond -n
root       183  0.0  0.1 408308 13476 ?        Ss   02:38   0:00 /usr/sbin/httpd -DFOREGROUND
root       187  0.0  0.0 218528  4316 ?        Ssl  02:38   0:00 /usr/sbin/rsyslogd -n
root       192  0.0  0.0 112900  4312 ?        Ss   02:38   0:00 /usr/sbin/sshd -D
mysql      268  0.0  0.0 113412  1592 ?        Ss   02:38   0:00 /bin/sh /usr/bin/mysqld_safe --basedir=/usr
apache     344  0.0  0.0 408308  6692 ?        S    02:38   0:00 /usr/sbin/httpd -DFOREGROUND
apache     345  0.0  0.0 408308  6692 ?        S    02:38   0:00 /usr/sbin/httpd -DFOREGROUND
apache     346  0.0  0.0 408308  6692 ?        S    02:38   0:00 /usr/sbin/httpd -DFOREGROUND
apache     347  0.0  0.0 408308  6692 ?        S    02:38   0:00 /usr/sbin/httpd -DFOREGROUND
apache     349  0.0  0.0 408308  6692 ?        S    02:38   0:00 /usr/sbin/httpd -DFOREGROUND
mysql      461  0.1  1.0 970944 81116 ?        Sl   02:38   0:00 /usr/libexec/mysqld --basedir=/usr --datadir=/var/lib/mysql --plugi
root       528  0.0  0.0  89708  2120 ?        Ss   02:38   0:00 /usr/libexec/postfix/master -w
postfix    529  0.0  0.0  89812  4060 ?        S    02:38   0:00 pickup -l -t unix -u
postfix    530  0.0  0.0  89880  4084 ?        S    02:38   0:00 qmgr -l -t unix -u
```
