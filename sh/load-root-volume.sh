#!/bin/bash -x

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

# Mount
echo Mount "$disk" to "$src_dir"
if [ -d "$src_dir" ]; then
    guestunmount -v --retry=3 "$src_dir" \
    || umount -lf "$src_dir"
else
    mkdir -vp "$src_dir"
fi

# Copy
if guestmount -v --format="$disk_format" -a "$disk" -i --ro "$src_dir"; then
    df -hT "$src_dir"
    ls -lh "$src_dir"
    rsync -avAHXS --stats \
    "${src_dir}/" "${dest_dir}/" \
    --exclude boot \
    --exclude sys \
    --exclude proc \
    --exclude dev \
    --exclude run \
    --exclude usr/lib/firmware \
    --exclude usr/lib/modules \
        --delete \
        --delete-excluded
    sync
    guestunmount -v --retry=3 "$src_dir" \
    || umount -lf "$src_dir"
    echo "Transferred completed:"
    ls -lh "${dest_dir}/"
else
    echo "Failed to mount \"$disk\"!"
    exit 1 
fi 

