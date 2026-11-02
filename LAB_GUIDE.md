# CCEN 448 Lab 6 Windows guide

This project provides a small dynamic notes website and the infrastructure files for the main lab and both extra-credit options. Read one stage at a time, run it, and collect the evidence before continuing. The AWS account, public GitHub repository and screenshots must be yours. No deployment result is assumed by these instructions.

Your Blackboard screenshot shows a deadline of **2 November 2026 at 11:30 PM UAE time**. Capture the main 20-point requirements before moving to the extra credit. Every AWS console screenshot must show your signed-in username at the top right. Hide key values and secrets.

## What you are building

The browser displays HTML, but Flask runs Python on the server to register users, verify password hashes and enforce ownership of notes. PostgreSQL stores the users and notes. Nginx receives HTTP requests and forwards them to Flask through Gunicorn. Docker Compose runs the application and database containers.

OpenTofu creates the Lightsail instance, static IP and public firewall. Ansible later installs and configures software on the larger deployment. Cloudflare gives a temporary HTTPS URL that reaches the website through your computer and SSH.

The initial deployment runs all software on one Ubuntu server. Port 80 is the website port; port 8000 is only the local app container port. Use port **80** in the lab SSH forward.

## Task 1 Prepare Windows and AWS

Open PowerShell. Install the two local tools:

```powershell
winget install --exact --id=OpenTofu.Tofu
winget install --exact --id=Cloudflare.cloudflared
```

Close and reopen PowerShell so the new PATH takes effect. Check:

```powershell
tofu version
cloudflared --version
ssh -V
```

Take screenshot **1** of `tofu version`. If `winget` is unavailable, use the official OpenTofu installation page and Cloudflare downloads page listed below. OpenSSH Client is normally present on Windows; add it from Windows Optional Features if `ssh` is unavailable.

In AWS Console, open **IAM → Users → Create user**. Name it `khaleifah-tofu-ccen448f26`. Leave console access disabled. Create the user, open its Permissions tab and choose Add permissions → Create inline policy. Use the JSON in `iam-policy.json`, which allows `lightsail:*` on `*`, exactly as requested by the lab. Name the policy `LightsailLabAccess`. Capture screenshot **2** showing the user and policy; open the JSON if needed.

Under the user's Security credentials tab, create an access key for command-line use. Save the secret privately. Set the credentials in the PowerShell window where you will run OpenTofu. Use hidden prompts so literal secrets are not written into your terminal history:

```powershell
$env:AWS_ACCESS_KEY_ID = [System.Net.NetworkCredential]::new('', (Read-Host 'Access key ID' -AsSecureString)).Password
$env:AWS_SECRET_ACCESS_KEY = [System.Net.NetworkCredential]::new('', (Read-Host 'Secret access key' -AsSecureString)).Password
```

Return to the IAM access keys list for screenshot **3**, showing the active status and hiding the access key ID. Do not screenshot the secret-creation screen. Keep the credential-bearing PowerShell window open. Never send these values in chat or put them in a `.tf` file.

In Lightsail, choose a Region, then Account → SSH keys. Create and download a key pair **in that Region**. Capture screenshot **4** with the key name and Region. This guide uses Ireland `eu-west-1` and `eu-west-1a` as examples; you may choose a different supported Region, updating both files accordingly.

Put the PEM in a private local folder. Example path:

```powershell
$KeyPath = "$env:USERPROFILE\.ssh\lab6.pem"
# First move/rename your downloaded PEM to the path above, then restrict it:
icacls $KeyPath /inheritance:r
icacls $KeyPath /grant:r "${env:USERNAME}:(R)"
```

If SSH still reports overly open permissions, inspect `icacls $KeyPath` and remove any remaining explicit grants to other users/groups. Keep the PEM owner as your Windows user. Follow the permission method used in your Exercise 4 if your university machine has different account naming.

## Task 2 Publish the website

Unzip this project to a new folder such as `C:\Users\YOUR_WINDOWS_USER\Downloads\lab6`.

Create a **public** GitHub repository named `lab6-notes`. Upload these items at the repository root, preserving their folders: `website/`, `scripts/`, `compose.yml`, `.gitignore`, `.gitattributes`, and this README. Using Git locally is also fine. Make sure the repository is public and `website/app.py` and `scripts/setup-single.sh` are visible at their expected paths.

Do not upload PEM files, AWS credentials or deployment-generated secrets/state. The files supplied in this archive do not contain your credentials. For screenshot **5**, show this AI-created project in your source editor or its repository page. Keep a record of using AI as required by your course rules.

The requirements are Python 3.12, Flask, Gunicorn, a running PostgreSQL 16 service, and persistent database storage. Docker installs the Python dependencies from `requirements.txt`. User passwords are hashed, forms include CSRF tokens, and each notes query checks the signed-in user's ID. This is a teaching application: use lab-only accounts, not sensitive personal information.

See `REPORT_GUIDE.md` for the answer to deliverable **6**.

## Task 3 Create the single-server deployment

Open `infra-single/lightsail-website.tf` in your editor. Set the public GitHub clone URL and your Lightsail key pair name. Confirm the Region, availability zone, blueprint and bundle against your Lightsail console. The Ubuntu 24.04 and `micro_3_0` 1 GB IPv4 bundle IDs are examples; select the smallest suitable IPv4 plan that is eligible in **your account**. This stack needs enough RAM for Docker, PostgreSQL and Flask; start with 1 GB and monitor it. Do not choose an IPv6-only bundle.

Keep `public_http = true` and `public_https = false` for now. The file is based on the provided template and adds an HTTPS switch for the extra credit. `tofu plan` must show the resources you intend to create.

In your credential-bearing PowerShell window, change to the actual folder:

```powershell
cd "$env:USERPROFILE\Downloads\lab6\infra-single"
tofu fmt
tofu init
tofu validate
tofu plan
tofu apply
```

Read the plan, then type `yes` at the apply prompt. Capture the plan and successful apply output for screenshot group **7**. An instance can be created before its startup script has finished; apply success alone does not prove the website is ready.

Get the static IP and connect. Replace `$KeyPath` with your actual key path if this is a new terminal:

```powershell
$ServerIp = tofu output -raw static_ipv4
$KeyPath = "$env:USERPROFILE\.ssh\lab6.pem"
ssh -i "$KeyPath" "ubuntu@$ServerIp"
```

Confirm the SSH host fingerprint through a trusted method, such as the Lightsail console's browser SSH session running `ssh-keygen -lf /etc/ssh/ssh_host_ed25519_key.pub`, before accepting an unfamiliar host. Inside the Ubuntu SSH session:

```bash
date
echo "$SSH_CONNECTION"
sudo cloud-init status --wait
```

Capture screenshot **8**. The SSH connection output contains client IP/port followed by server IP/port. Check that cloud-init completed successfully. If it failed, inspect `sudo tail -n 80 /var/log/cloud-init-output.log`.

Now configure the application and database:

```bash
cd /opt/website
bash scripts/setup-single.sh
sudo docker compose ps
sudo docker compose exec -T db psql -U labnotes -d labnotes -c '\dt'
```

The setup script creates random credentials in a private `.env`, builds the app, starts PostgreSQL, initializes its tables, starts Gunicorn, and configures Nginx. Preserve `.env` on reruns. PostgreSQL has no public port mapping. Capture screenshot **9** showing the running DB or its SQL client and tables.

Open `http://YOUR_STATIC_IP` in your Windows browser. Create a lab account, log in and save a distinctive note such as `Khalifa Lab 6 evidence — saved before failover`. Refresh, sign out and sign back in; confirm the note persists. Capture screenshot **10** showing authentication and the saved note page.

In the Lightsail console capture the instance details and Networking page for screenshot group **7**. Show Ubuntu blueprint, chosen bundle, static IPv4 and public TCP 22/80 rules. A larger browser window or several clear screenshots may be needed. Check the username is visible in each console image.

See `REPORT_GUIDE.md` for deliverable **11**.

For an optional functional check, run `python3 scripts/smoke-test.py http://127.0.0.1` from the server's `/opt/website` folder. It creates two disposable accounts and checks login, stored notes, user isolation, HTML escaping, CSRF rejection and persistence after signing in again. After secure cookies are enabled, run this client against the HTTPS URL instead.

## Task 4 Add the Cloudflare HTTPS path

Leave your AWS credentials in the OpenTofu terminal. Open a **second PowerShell** window for the port forward. Set your actual values in this new window:

```powershell
$KeyPath = "$env:USERPROFILE\.ssh\lab6.pem"
$ServerIp = "YOUR_STATIC_IP"
ssh -i "$KeyPath" -N -o ExitOnForwardFailure=yes -o ServerAliveInterval=30 -L 127.0.0.1:8080:localhost:80 "ubuntu@$ServerIp"
```

This window normally looks idle. Keep it running. The listener is bound to your local loopback interface, not exposed to your LAN. Open `http://localhost:8080` on Windows to verify the forward.

Open a **third PowerShell** window:

```powershell
cloudflared tunnel --url http://localhost:8080
```

Keep it running. Open the generated `https://....trycloudflare.com` URL. Register or sign in, add a note and refresh. The URL is a different browser origin from the raw IP, so signing in again is normal. Capture screenshots **12** (both command windows and generated URL) and **13** (authentication and database features at that HTTPS URL).

Back in `infra-single/lightsail-website.tf`, set:

```hcl
public_http  = false
public_https = false
```

Run `tofu plan` and `tofu apply` from the credential-bearing terminal. The expected change is the public port rules, not instance replacement. Read the plan before approving it. In Lightsail Networking verify **only TCP 22** remains. Your raw-IP HTTP URL should stop responding, while the Cloudflare HTTPS URL still works. Capture screenshot **14**, including both the firewall and working HTTPS app. Keep both tunnel processes running during this check.

The app uses relative URLs and same-origin HTML forms, so it does not require a fixed Quick Tunnel hostname or cross-origin API exceptions. The single deployment keeps `COOKIE_SECURE=false` while demonstrating initial HTTP and tunnel access; the cookie is still sent over HTTPS by the browser when using the tunnel. The direct HTTPS script and the HA deployment enable secure cookies. Each public hostname has its own browser cookie, so sign in again after switching origins.

See `REPORT_GUIDE.md` for deliverable **15** and the NAT explanation.

## Complete the extra credit next

Follow `EXTRA_CREDIT.md` **after** screenshot 14. It covers direct IP HTTPS with renewal, followed by two web instances, a shared PostgreSQL service, Nginx load balancing and Ansible configuration. The larger deployment uses a separate OpenTofu state folder. It demonstrates web-server failover; its single database and single load balancer are still failure points.

## Task 5 Delete all resources

Save screenshots, the final sanitized configurations and report first. Do not delete your local state files before destroying the resources they manage. Stopping an instance is not cleanup.

Stop cloudflared and the SSH forwarding window with Ctrl+C. Exit any interactive SSH sessions. In the original credential-bearing PowerShell:

```powershell
cd "$env:USERPROFILE\Downloads\lab6\infra-single"
tofu destroy
# Also do this if you launched the larger extra-credit deployment:
cd ..\infra-ha
tofu destroy
```

Read each destruction plan and confirm the intended lab resources. If you already destroyed the single-server deployment before starting HA, it should have nothing remaining. Confirm the Lightsail console has no lab instances or allocated static IPs. Check for snapshots, disks or other resources you created manually; delete those too. The certificate setup lives on the destroyed server and adds no separate Lightsail resource.

Delete the Lightsail key pair in the correct Region. In IAM, delete the access key, inline policy, then `khaleifah-tofu-ccen448f26`. Finally clear credentials and close the terminal:

```powershell
Remove-Item Env:AWS_ACCESS_KEY_ID -ErrorAction SilentlyContinue
Remove-Item Env:AWS_SECRET_ACCESS_KEY -ErrorAction SilentlyContinue
```

Take a cleanup evidence screenshot for the report. Remove any unused private key copies from your computer after all cleanup is complete.

## Troubleshooting

| Symptom | Check |
|---|---|
| `tofu` or `cloudflared` not found | Reopen PowerShell after installing; run `Get-Command tofu` or `Get-Command cloudflared`. |
| AWS credential error | Set both variables in the same PowerShell session used by OpenTofu. The lab IAM user has Lightsail permissions, not general AWS administration. |
| Instance never finishes setup | Read cloud-init output; verify the public GitHub URL, apt package installation and Region/key/bundle values. |
| Repository path not found | The repository must contain `website/`, `scripts/` and `compose.yml` at its root, not inside another `lab6/` folder. |
| `bash` shows `\r` errors | Save shell scripts with LF line endings. `.gitattributes` enforces LF when using Git. |
| Browser timeout | Check the correct static IP, public 80 rule for Task 3, `sudo systemctl status nginx`, and `curl http://127.0.0.1/health`. |
| Nginx 502 | Run `sudo docker compose ps` and `sudo docker compose logs --tail=60 web db` in `/opt/website`. Avoid screenshots containing secrets. |
| Docker build killed on 1 GB | Check `free -h` and `sudo journalctl -k`; a bigger bundle may be needed, subject to account eligibility and cost. |
| Tunnel cannot reach localhost | Confirm the SSH forward remains running and Windows can open `http://localhost:8080`. If port 8080 is busy, choose 8081 in both commands. |
| Quick Tunnel does not start | Check for an existing `.cloudflared/config.yml` and temporarily move it aside; inspect tunnel logs and network restrictions. |
| `cloudflared` QUIC blocked | Retry `cloudflared tunnel --protocol http2 --url http://localhost:8080`. Outbound network access must still be allowed. |
| Recreated instance gives SSH host-key warning | Verify that the static IP now belongs to the new instance and verify its fingerprint before removing the old known-host entry. |

## Official references

- OpenTofu introduction and install: https://opentofu.org/docs/intro/ and https://opentofu.org/docs/intro/install/
- AWS Lightsail resource: https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/lightsail_instance
- Lightsail billing and account eligibility: https://docs.aws.amazon.com/lightsail/latest/userguide/amazon-lightsail-frequently-asked-questions-faq-billing-and-account-management.html
- Cloudflare Quick Tunnels: https://developers.cloudflare.com/tunnel/get-started/quick-tunnels/
- Cloudflare downloads: https://developers.cloudflare.com/tunnel/downloads/
- Let’s Encrypt IP certificates: https://letsencrypt.org/2026/03/11/shorter-certs-certbot
- Ansible Windows control-node guidance: https://docs.ansible.com/projects/ansible/latest/os_guide/intro_windows.html
- Nginx upstream retries: https://nginx.org/en/docs/http/ngx_http_proxy_module.html#proxy_next_upstream
- Flask proxy settings: https://flask.palletsprojects.com/en/stable/deploying/proxy_fix/
