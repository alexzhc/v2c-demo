#!/bin/bash -x

vm_name=$1
config=/vm/$2
disk_format=$3

# Do something such as: disable firewalld and selinux, etc.
echo "Make sure ROOT files is ready"
ls -lh /vol

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
EOF

cat values.yaml

kubectl delete cm v2c-${vm_name}-conf
kubectl create cm v2c-${vm_name}-conf --from-file=values.yaml
kubectl get cm v2c-${vm_name}-conf