#!/bin/bash -x

export LIBGUESTFS_BACKEND=direct

if [ -c /dev/kvm ] && lsmod | grep kvm_intel; then 
    export LIBGUESTFS_BACKEND_SETTINGS=force_kvm
else
    export LIBGUESTFS_BACKEND_SETTINGS=force_tcg
fi
printenv LIBGUESTFS_BACKEND_SETTINGS

disk=./vm/$1
disk_format=$2

src_dir=./mnt
dest_dir=./vol

# Copy files
if [ ! -f "$disk" ]; then
    echo "Cannot find root disk \"$disk\"!"
    exit 1
fi

# Check
echo Verify "$disk" consistency
qemu-img check -f "$disk_format" "$disk" || exit 1

# tail -f /dev/null

# Mount
echo Mount "$disk" to "$src_dir"
if [ -d "$src_dir" ]; then
    guestunmount -v --no-retry "$src_dir" \
    || umount -lf "$src_dir"
else
    mkdir -vp "$src_dir"
fi

# Copy
if guestmount -v --format="$disk_format" -a "$disk" -i --ro "$src_dir" -o kernel_cache; then
    df -hT "$src_dir"
    ls -lh "$src_dir"
    rsync -avAHS --stats \
    "${src_dir}/" "${dest_dir}/" \
    --exclude boot \
    --exclude sys \
    --exclude proc \
    --exclude dev \
    --exclude usr/lib/firmware \
    --exclude usr/lib/modules \
    --exclude usr/src \
    --exclude var/snap \
    --exclude var/cache \
    --exclude swap.img \
    --delete \
    --delete-excluded
    # --exclude run \
    sync
    guestunmount -v --retry=3 "$src_dir" \
    || umount -lf "$src_dir"
    echo "Transferred completed:"
    ls -lh "${dest_dir}/"
else
    echo "Failed to mount \"$disk\"!"
    exit 1 
fi 

