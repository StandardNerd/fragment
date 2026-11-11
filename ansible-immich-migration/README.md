# Ansible Playbook: Immich Storage Migration to USB SSD

This Ansible automation captures the complete migration of Immich storage to an external USB SSD on Proxmox VE for unprivileged LXC container `107`.

## Directory Contents

* `ansible.cfg` - Ansible configuration settings
* `inventory.ini` - Localhost Proxmox VE connection configuration
* `playbook.yml` - Master migration playbook covering all phases
* `README.md` - Documentation and execution guide

---

## Migration Architecture & Key Parameters

| Variable | Default Value | Description |
| :--- | :--- | :--- |
| `vmid` | `107` | Proxmox LXC Container ID |
| `unprivileged_uid_offset` | `100000` | Proxmox unprivileged UID/GID mapping offset |
| `ssd_device` | `/dev/sda1` | External USB SSD block device partition |
| `ssd_uuid` | `86d0455a-1cd1-4555-836a-653a113d8fca` | Persistent UUID for `/etc/fstab` |
| `ssd_fs_type` | `ext4` | Filesystem type for the SSD |
| `ssd_mount_host` | `/mnt/immich-ssd` | Mount point path on the Proxmox host |
| `ssd_mount_container` | `/mnt/immich-ssd` | Mount point path inside LXC 107 |
| `immich_new_photos_dir` | `/mnt/immich-ssd/photos` | Live upload directory on the SSD |
| `immich_backup_dir` | `/mnt/immich-ssd/backup/photos` | Standalone verified media backup on the SSD |
| `host_backup_dir` | `/root/immich_pre_migration_backup` | Host storage directory for DB dump & configs |
| `cleanup_old_files` | `false` | Safety toggle for deleting old files from internal disk |
| `delete_snapshot` | `false` | Safety toggle for deleting pre-migration snapshot |

---

## Key Safety Safeguards Included

1. **Under-Mount Protection (`chattr +i`):**
   When `/mnt/immich-ssd` is unmounted, its mode is `0000` and it has the immutable attribute set. If the drive is ever unplugged or fails to mount, neither host nor container processes can silently write to the host root disk.
2. **Unprivileged UID/GID Preservation:**
   Host mount ownership is set to `100000:100000` (`0755`) so that container root (`0:0`) can manage files without using insecure `777` permissions.
3. **Multi-Tier Backups:**
   * PostgreSQL database dump + `.env` + `docker-compose.yml` on the host root disk.
   * Standalone pre-migration media copy on the SSD (`/mnt/immich-ssd/backup/photos/`).
   * Original media untouched until explicit cleanup.
4. **Boot Persistence (`immich.service`):**
   Deploys a systemd unit inside the container that requires `/mnt/immich-ssd` before starting Docker containers.

---

## Execution Instructions

### 1. Syntax Check
```bash
ansible-playbook --syntax-check playbook.yml
```

### 2. Run Pre-flight Inspection & Backups Only
```bash
ansible-playbook playbook.yml --tags "inspect,backup"
```

### 3. Run Validation Only
```bash
ansible-playbook playbook.yml --tags "validate"
```

### 4. Full Execution (with Cleanup)
```bash
ansible-playbook playbook.yml -e "cleanup_old_files=true delete_snapshot=true"
```
