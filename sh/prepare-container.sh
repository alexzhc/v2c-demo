#!/bin/bash -x

vm_name=$1
config=./vm/$2
disk_format=$3

# This step will process root files: extract important information and make necessary changes

# Get ssh and http port, by best effort
ls -lh ./vol
http_port=$(cat ./vol/etc/httpd/conf/httpd.conf | awk '/^Listen/ {print $2}')
ssh_port=$(cat ./vol/etc/ssh/sshd_config | awk '/^Port/ {print $2}')
[ -z "$http_port" ] && http_port=80
[ -z "$ssh_port" ] && ssh_port=22

# Sorting systemd
sed -i 's/^SELINUX=.*/SELINUX=disabled/' ./vol/etc/selinux/config
# mv ./vol/etc/systemd/system/multi-user.target.wants /vol/etc/systemd/system/multi-user.target.wants.bak
# mkdir -vp ./vol/etc/systemd/system/multi-user.target.wants
# mv -v ./vol/etc/systemd/system/multi-user.target.wants.bak/sshd.service ./vol/etc/systemd/system/multi-user.target.wants/
# mv -v ./vol/etc/systemd/system/multi-user.target.wants.bak/mariadb.service ./vol/etc/systemd/system/multi-user.target.wants/

# Replace systemd
# mv -vf ./vol/usr/bin/systemctl ./vol/var/
# install -v ./tool/systemctl ./vol/usr/bin/systemctl
# ls -lh ./vol/usr/bin/systemctl

# Get VM CPU and Memory configuration
if [ ! -f "$config" ]; then
    echo "Cannot find VM config file!"
    exit 1
fi 

if [[ "$disk_format" != "vmdk" ]]; then
    echo "Cannot determine VM config format!"
    exit 1
fi

cpu=$( cat "$config" | yq -p xml .Envelope.VirtualSystem.VirtualHardwareSection.Item[0].VirtualQuantity )
mem=$( cat "$config" | yq -p xml .Envelope.VirtualSystem.VirtualHardwareSection.Item[1].VirtualQuantity)

cat > values.yaml << EOF
sts:
  resources:
    limits:
      cpu: "${cpu}"
      memory: "${mem}Mi"
  ports:
    ssh: ${ssh_port}
    http: ${http_port}
  volumeMounts:
EOF

for i in $(ls -1 ./vol); do
  case "$i" in
    sys)
      continue
    ;;
    proc)
      continue
    ;;
    dev)
      continue
    ;;
    run)
      continue
    ;;
    boot)
      continue
    ;;
    mnt)
      continue
    ;;
    media)
      continue
    ;;
    *)
cat >> values.yaml << EOF
  - name: root
    mountPath: /$i
    subPath: $i
EOF
    ;;
    esac
done

cat values.yaml

kubectl delete cm v2c-${vm_name}-conf
kubectl create cm v2c-${vm_name}-conf --from-file=values.yaml
kubectl get cm v2c-${vm_name}-conf