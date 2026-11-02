# Lab 6 extra credit

Complete and screenshot the main lab before changing its firewall. This guide then covers both extra-credit options. The larger deployment uses four separate servers and may incur charges beyond your account's free-tier allowance. Check your actual account and console before applying it.

## Part A Direct HTTPS with an IP certificate

This part uses the original single server. First finish the Task 4 screenshot with only SSH open. Then edit `infra-single/lightsail-website.tf`:

```hcl
public_http  = true
public_https = true
```

From its folder in your original PowerShell, run `tofu plan` and `tofu apply`. Verify public TCP 22, 80 and 443 in Lightsail. TCP 80 is required for this implementation's HTTP-01 certificate validation and renewals; normal HTTP requests will redirect to HTTPS.

SSH to the single server. In the commands below, replace the IP and email with your own values. Read `scripts/enable-ip-https.sh` before running it:

```bash
cd /opt/website
sudo bash scripts/enable-ip-https.sh YOUR_STATIC_IPV4 YOUR_EMAIL
```

The script installs current Certbot using snap and checks that it is at least 5.4. It requests a staging IP certificate with the `shortlived` profile in separate directories, then requests a publicly trusted production certificate. Nginx is configured explicitly with the certificate and private key. The Certbot Nginx installer is not used for this IP workflow.

The script also installs a deploy hook that checks and reloads Nginx after a successful renewal, creates a twice-daily systemd renewal timer, enables secure session cookies and runs a renewal dry run including deploy hooks. If a step fails, read the error before continuing. Port 80 must be reachable from the Internet; the Cloudflare Quick Tunnel is not the validation path.

Open **`https://YOUR_STATIC_IPV4`**, without a custom domain. Sign in again and save a note. Inspect the browser certificate: the subject alternative name must include your IP, the issuer should be Let's Encrypt, and the browser must trust it. A staging certificate does not qualify as a publicly trusted result.

Capture evidence:

```bash
sudo /snap/bin/certbot certificates
sudo /snap/bin/certbot renew --cert-name lab6-ip --dry-run --run-deploy-hooks
sudo systemctl list-timers lab6-certbot-renew.timer --all --no-pager
sudo cat /etc/letsencrypt/renewal-hooks/deploy/20-reload-nginx
sudo openssl x509 -in /etc/letsencrypt/live/lab6-ip/fullchain.pem -noout -issuer -dates -ext subjectAltName
```

Include the trusted HTTPS browser page, certificate details, successful dry run, timer and hook, and the public port 443 firewall rule. Record actual validity dates. Let's Encrypt's IP certificates last six days; the timer checks for renewal every 12 hours with up to 30 minutes of jitter. The deploy hook ensures the running Nginx service loads a renewed certificate. A dry run demonstrates that the renewal process can work; it does not demonstrate that a future scheduled renewal has already occurred.

To demonstrate independence, stop cloudflared and the SSH port-forward processes, then refresh the **direct IP HTTPS URL**. It should still work because traffic goes directly to the Lightsail server. Keep the interactive SSH session if you need it for checks.

With direct HTTPS, the browser connects to the server on public 443 and Nginx terminates TLS using the IP certificate. With the Quick Tunnel, the browser connects to Cloudflare's hostname, Cloudflare terminates browser TLS, and tunnel traffic reaches the server through cloudflared on your PC and an encrypted SSH connection. The PC and both tunnel processes are required for that lab tunnel route. The Cloudflare hostname and direct IP are different browser origins and use separate cookies.

## Part B Two web instances and a shared database

The implementation uses four Ubuntu Lightsail instances: `web1`, `web2`, `db`, and `lb`. `db` runs a single PostgreSQL container with a persistent volume, and `lb` runs an Nginx load balancer. A self-hosted PostgreSQL service on a dedicated instance is the shared database service; this design does not use a Lightsail managed database or managed load balancer.

All four servers are in one Region and availability zone for a compact lab setup. Backend traffic uses private IPs. Public firewalls allow only SSH; the browser reaches the load balancer through the same local SSH and Cloudflare arrangement. Both web instances share one database URL and one Flask signing key. A session signed on web1 is therefore accepted on web2, and both read the same user records.

This demonstrates application-server redundancy. It does not provide database replication, load-balancer redundancy, availability-zone resilience or zero downtime for every in-flight request. State those limits in the report.

### Preserve evidence and remove the single-server deployment

Save all main-lab and Part A screenshots first. Stop the two local tunnel processes. To avoid keeping five instances running at once, destroy the single deployment from `infra-single` with `tofu destroy` before creating HA. This also deletes its notes and its server-side certificate. The separate HA deployment starts with a new database; create a new test account for its failover demonstration.

### Prepare WSL Ubuntu for Ansible

From an Administrator PowerShell, if WSL is not already installed:

```powershell
wsl --install -d Ubuntu
```

Restart Windows if requested, launch Ubuntu and finish creating its local user. In **WSL Ubuntu**:

```bash
sudo apt-get update
sudo apt-get install -y ansible-core python3 openssh-client
ansible --version
mkdir -p ~/.ssh
chmod 700 ~/.ssh
# Replace YOUR_WINDOWS_USER and the source filename with your actual values:
cp /mnt/c/Users/YOUR_WINDOWS_USER/.ssh/lab6.pem ~/.ssh/lab6.pem
chmod 600 ~/.ssh/lab6.pem
```

The PEM copied into WSL is the same Lightsail key; you are not creating another AWS key. Keep it under WSL's home directory because permissions on `/mnt/c` may not behave like normal Linux permissions. Ansible runs in WSL; OpenTofu continues running in Windows PowerShell, where the AWS credentials already exist. No AWS credentials are needed inside WSL for this workflow.

### Configure and provision HA

In Windows, copy `infra-ha/terraform.tfvars.example` to `infra-ha/terraform.tfvars`. Set the same verified Region, AZ, bundle and Lightsail key pair. Edit `ansible/settings.yml` with your public GitHub URL. If available, set `repository_version` to a commit hash so the deployment uses exactly that code revision.

In the original PowerShell:

```powershell
cd "$env:USERPROFILE\Downloads\lab6\infra-ha"
tofu init
tofu validate
tofu plan
tofu apply
tofu output -json nodes
```

Read the plan: it creates **four instances, four static IPs, four attachments and four public-port rule resources**. Check your Region's instance and static-IP quotas. If you have unrelated existing resources, do not delete them to make room; use a supported Region or request a quota change if needed.

Before Ansible's first connection, open each instance's browser SSH console and check its Ed25519 SSH host fingerprint. Then, from WSL, SSH to each public IP with `ssh -i ~/.ssh/lab6.pem ubuntu@PUBLIC_IP` and verify the displayed fingerprint before accepting it. Exit each session. This populates WSL's known-hosts file. Windows and WSL keep separate known-hosts files.

### Run the combined deployment workflow

Now the included PowerShell script can run the entire provisioning-and-configuration workflow. It reruns the OpenTofu plan/apply, exports the **actual** IP outputs, builds an Ansible inventory, generates private shared secrets once, checks playbook syntax and configures all four nodes:

```powershell
cd "$env:USERPROFILE\Downloads\lab6"
# Only if your current PowerShell policy blocks the local script:
Set-ExecutionPolicy -Scope Process Bypass
.\scripts\deploy-ha.ps1
```

On the first run after the initial apply, OpenTofu should report no infrastructure changes. The apply confirmation is kept so you can review future changes. Windows 11/current WSL supports `wsl --cd` with a Windows directory; if your WSL version lacks it, update WSL or run the manual commands below from Ubuntu.

The playbook installs Docker, starts the private-IP PostgreSQL service, restricts its database authentication rules to the two web private IPs, clones and builds the web code, initializes tables, then configures both reverse proxies and the load balancer. Secrets are generated once, stored locally in ignored `ansible/secrets.yml`, and written to remote Compose files with mode 600. Do not regenerate them while reusing the database volume: PostgreSQL does not reset an existing role password from a changed container environment variable.

If the wrapper is not usable on your Windows setup, export outputs in PowerShell:

```powershell
cd "$env:USERPROFILE\Downloads\lab6\infra-ha"
$NodesJson = tofu output -json nodes
[IO.File]::WriteAllText((Join-Path (Resolve-Path ..\ansible).Path 'nodes.json'), ($NodesJson -join "`n"), [Text.UTF8Encoding]::new($false))
```

Then in WSL, from the project's `ansible` directory (for example `/mnt/c/Users/YOUR_WINDOWS_USER/Downloads/lab6/ansible`):

```bash
python3 make-inventory.py --nodes-file nodes.json --key ~/.ssh/lab6.pem
# Run only if secrets.yml does not exist:
python3 make-secrets.py
ansible-playbook -i inventory.json site.yml --syntax-check
ansible-playbook -i inventory.json site.yml
```

If a play fails, fix the cause and rerun using the same secrets. Save the OpenTofu outputs and Ansible recap showing `failed=0`. Builds and service reloads are deliberately rerun; the guide does not claim that every playbook task is change-free on a second run.

### Serve HA through Cloudflare

Find `lb`'s public static IP from `tofu output -json nodes`. On Windows, start an SSH forward to **the load balancer**:

```powershell
ssh -i "$env:USERPROFILE\.ssh\lab6.pem" -N -o ExitOnForwardFailure=yes -o ServerAliveInterval=30 -L 127.0.0.1:8080:localhost:80 ubuntu@LB_PUBLIC_IP
```

In another PowerShell window:

```powershell
cloudflared tunnel --url http://localhost:8080
```

Use the generated HTTPS URL. The HA app has secure cookies enabled; use the HTTPS URL for browser authentication. `http://localhost:8080/api/instance` remains useful for a command-line load-balancer check without a login.

### Prove load balancing and failover

1. At the Cloudflare HTTPS URL, create a new account, sign in, and save a note with a distinctive marker such as `HA persistence check 2026-11-02`. Record the note ID and text before the failure.
2. Refresh the page several times. The `Server web1` / `Server web2` badge identifies the responding instance. Other requests such as favicon or health checks can affect round-robin order, so a strict alternating browser sequence is not required.
3. In another PowerShell window show repeated requests:

```powershell
1..10 | ForEach-Object { curl.exe -s http://localhost:8080/api/instance; Write-Host }
```

4. From WSL, in the `ansible` folder, stop the **actual web1 Lightsail instance** from its operating system. Do not target `db` or `lb`:

```bash
ansible web1 -i inventory.json -b -m ansible.builtin.command -a 'shutdown -h +1'
```

This schedules an OS shutdown after one minute, allowing Ansible to return normally. Wait for the Lightsail console to show web1 as stopped. A stopped instance still incurs storage/bundle charges; this is a failure demonstration, not cleanup.

5. Repeat the ten requests. Nginx should route working requests to web2 after a connection failure detects web1's absence. Detection is passive, not an active health-check subscription. If a non-idempotent request was already sent when the failure occurred, the browser may need to retry it; do not claim lossless failover for every in-flight write.
6. Refresh the same authenticated browser session. Capture the badge showing `web2` and the **same earlier note**. Add a second note after web1 stops, sign out, sign back in, and confirm both notes remain. Show the stopped web1 instance in the Lightsail console, with your username visible. This proves both authentication and database access survive that web-server failure.
7. Restart web1 from the Lightsail console. Docker and Nginx are enabled to restart at boot; verify it becomes healthy and eventually appears again in responses.

The load balancer uses round robin with a shared upstream zone, `max_fails=1`, `fail_timeout=10s`, a 2-second connect timeout, and at most two upstream attempts. It retries connection/time-out and selected gateway errors. It does not opt into replaying already-sent non-idempotent requests. Both web nodes access the same PostgreSQL tables, and both validate cookies with the same signing key. No sticky sessions are required for this application.

Capture: four instance roles and private/public IPs; OpenTofu apply; successful Ansible recap; database running and its tables; responses from both web instances; saved notes before failure; web1 stopped; web2 showing the earlier records and a new write; and the working Cloudflare HTTPS URL. Do not show `secrets.yml` or remote Compose files containing passwords in screenshots.

For a DB screenshot, open an SSH session to the DB instance and run:

```bash
sudo docker compose -f /opt/lab6/compose.yml ps
sudo docker compose -f /opt/lab6/compose.yml exec -T db psql -U labnotes -d labnotes -c 'SELECT id,username FROM users; SELECT id,user_id,body FROM notes ORDER BY id;'
```

## Finish with cleanup

Stop the SSH forward and cloudflared, then run `tofu destroy` from `infra-ha`. Check `infra-single` too if you retained it. Delete manually created keys and IAM resources as described in README. Do not submit your raw state, secrets, access keys or PEM. Submit the report PDF with relevant sanitized code and supporting files.
