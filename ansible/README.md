# Ansible Provisioning & Deployment for `fragment` on Proxmox VE

This directory contains automated **Ansible playbooks** to provision an unprivileged LXC container (CT `108`) running **Ubuntu 24.04** on a Proxmox VE host (`192.168.1.19`) and deploy the **`fragment`** Elixir/Phoenix pastebin application with SQLite3 and Nginx.

---

## Target Architecture

- **Proxmox Host:** `192.168.1.19` (SSH user: `root`)
- **Container 108 (`fragment-app`):** `192.168.1.26/24`
  - **Base OS:** Ubuntu 24.04 LTS (Noble Numbat)
  - **Runtime:** Erlang/OTP 26 + Elixir 1.17+
  - **Database:** SQLite3 (`/var/lib/fragment/fragment.db`)
  - **Application Service:** `fragment.service` (systemd managing `/opt/fragment/bin/fragment start`)
  - **Reverse Proxy:** Nginx (Port 80 -> `127.0.0.1:4000` with LiveView WebSocket support)

---

## Directory Structure

```
ansible/
├── ansible.cfg              # Ansible configuration & SSH parameters
├── inventory.ini            # Target hosts (Proxmox host, LXC 108 IP)
├── group_vars/
│   └── all.yml              # Variable definitions (Container specs, IP, paths, secrets)
├── templates/               # Jinja2 templates (configs & systemd units)
│   ├── fragment.env.j2
│   ├── fragment.service.j2
│   └── nginx_fragment.conf.j2
├── playbook.yml             # Full automated provisioning & deployment playbook
├── deploy_lxc108.yml        # Quick application build & deployment to CT 108
├── deploy_lxc101.yml        # Backward-compatible alias deploying to CT 108
└── db_migrate.yml           # Standalone database migration runner
```

---

## Execution Guide

### Prerequisites

Ensure `ansible` and `sshpass` are installed on your local machine:

```bash
# macOS (Homebrew)
brew install ansible sshpass
```

### Full Provisioning & Deployment (from scratch)

Execute `playbook.yml` against the Proxmox host to download the Ubuntu 24.04 template, create CT 108, install Erlang/Elixir, compile assets, build the OTP release, and configure Nginx:

```bash
cd ansible
ansible-playbook -i inventory.ini playbook.yml --extra-vars "ansible_ssh_pass=dexter33143"
```

### Fast Code Redeployment to CT 108

To sync codebase updates, run `mix precommit`, compile assets, rebuild the release, and restart `fragment.service`:

```bash
ansible-playbook -i inventory.ini deploy_lxc108.yml --extra-vars "ansible_ssh_pass=dexter33143"
```

*(You can also run `ansible-playbook -i inventory.ini deploy_lxc101.yml ...` or `playbook.yml --tags redeploy`)*

### Overriding Secrets

To customize the secret key base:

```bash
ansible-playbook -i inventory.ini playbook.yml \
  --extra-vars "ansible_ssh_pass=dexter33143 secret_key_base=$(mix phx.gen.secret)"
```

---

## Verification

After playbook execution, verify the running application:

```bash
# Test HTTP response from application container
curl -I http://192.168.1.26

# Check Fragment systemd service status via Proxmox pct
sshpass -p 'dexter33143' ssh root@192.168.1.19 "pct exec 108 -- systemctl status fragment"

# Inspect SQLite database inside CT 108
sshpass -p 'dexter33143' ssh root@192.168.1.19 "pct exec 108 -- ls -la /var/lib/fragment"
```
