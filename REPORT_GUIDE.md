# Lab 6 report and evidence guide

Write the final report from your actual deployment. This guide supplies an outline and explanations; it is not a completed experiment report. Replace examples with your chosen settings and observed results. Include only extra-credit stages you actually completed and tested.

## Cover page

Include your full name, student ID, Khalifa University, CCEN 448 Cloud Infrastructure and Services, Lab Exercise 6, instructor, lab section and submission date. The required submission is a PDF. Keep screenshots sharp and readable, and include short captions explaining what each proves.

## Evidence checklist

| Deliverable | Required evidence |
|---|---|
| 1 | PowerShell `tofu version`. |
| 2 | IAM username and inline Lightsail policy, with AWS console username visible. |
| 3 | Access key list showing active status; mask the key ID and do not show its secret. |
| 4 | Lightsail SSH key pair and Region. |
| 5 | AI website creation, source editor or selected public repository. |
| 6 | Explain dynamic execution requirements and compare with S3 static hosting. |
| 7 | OpenTofu plan and completed apply; Lightsail blueprint, bundle, static IP, firewall. |
| 8 | SSH session showing `date`, `$SSH_CONNECTION` and completed cloud-init. |
| 9 | Running PostgreSQL service or SQL client connected to the DB. |
| 10 | Initial raw-IP authentication page and a page displaying saved database records. |
| 11 | Explain what OpenTofu automated and what the app setup still required. |
| 12 | SSH forward command and cloudflared command/output with generated URL. |
| 13 | Authentication and persisted records at the Cloudflare HTTPS URL. |
| 14 | Networking page with only SSH open and the website still working via HTTPS tunnel. |
| 15 | Explain the complete network route and the effect of NAT. |
| Cleanup | Successful destroy and confirmation that manually created lab resources were removed. |

Every AWS console screenshot must show your signed-in username at the top right. Crop only if that requirement remains satisfied. Mask credentials rather than masking the username. Use additional screenshots where one view cannot show every requested detail clearly.

## Deliverable 6 Understanding the execution requirements

Use these points to explain your own deployment:

The website requires a continuously running server-side application and a database service. Flask routes implement registration, password verification and authorization, while Gunicorn runs the Python application workers. PostgreSQL accepts SQL connections and stores users and notes on persistent storage. Docker Compose starts and connects these services. Nginx receives browser requests and forwards them to the application.

In the single-instance deployment, Nginx, the application container and the PostgreSQL container all run on the Lightsail Ubuntu instance. PostgreSQL data is stored in a Docker named volume backed by that instance's disk. That volume survives container replacement, but it is deleted when the underlying instance is destroyed unless separately backed up.

S3 static website hosting serves stored files such as HTML, CSS, JavaScript and images. It does not run this Flask application, verify passwords through server-side Python or host a PostgreSQL process. A static S3 frontend could call an external backend and database, but those services would run outside S3 static website hosting. This lab therefore needs compute resources and a running database in addition to static page assets.

## Deliverable 11 Understanding OpenTofu's role

The supplied template provisions cloud infrastructure: the instance, static IPv4 address, IP attachment and public port rules. Its `user_data` also installs specified operating-system packages and clones the public website repository to `/opt/website` when the instance first boots. In this implementation the package list contains Docker, Docker Compose and Nginx.

OpenTofu does not infer an application's installation procedure from its source code. The single-server setup still needs application secrets, a container image, a running PostgreSQL service, initialized tables, a persistent volume and an Nginx reverse proxy. `scripts/setup-single.sh` performs those application-specific steps when invoked over SSH after cloud-init completes. Explain which commands you actually ran and which parts were already handled by user data.

In the larger extra-credit deployment, OpenTofu still creates the cloud resources, while Ansible automates the software installation and configuration across the four servers. This extends the automation; it does not mean the original template automatically knew how to deploy the application. Editing user data after a machine is running is also not a general application-update mechanism; inspect the provider's plan before assuming it will rerun setup.

## Deliverable 15 Understanding the network route and NAT

After public HTTP is removed, the inbound request follows this path:

1. The visitor opens the temporary HTTPS hostname and connects to Cloudflare.
2. Cloudflare sends the request over the tunnel maintained by `cloudflared` on your Windows PC.
3. `cloudflared` forwards the request to the local listener at `127.0.0.1:8080`.
4. The SSH client carries it through the encrypted SSH connection to the Lightsail server on public TCP 22.
5. The SSH server connects to `localhost:80` on that server. Nginx forwards the request to Flask, which queries PostgreSQL if needed.
6. The response returns along the reverse route.

The SSH command creates a local forward (`-L`), rather than a publicly exposed listener or a remote forward. Lightsail's public port 80 can be closed because the web connection originates inside the server after it traverses SSH. Closing the public firewall rule does not stop the local web service.

Your PC can be behind NAT without a reachable public IPv4 address. Both cloudflared's Cloudflare connection and the SSH client connection are initiated outbound from your PC, and NAT tracks the established connections. No router port forwarding to your PC is required. The PC must still have working outbound network access and remain running, with both processes alive. NAT does not automatically bypass networks that block SSH or Cloudflare tunnel traffic.

Browser-to-Cloudflare traffic uses HTTPS, cloudflared uses an encrypted tunnel to Cloudflare, and the PC-to-Lightsail hop uses SSH encryption. In this lab the short local HTTP legs connect cloudflared to the SSH listener and the SSH endpoint to Nginx. Do not describe this as one uninterrupted browser TLS session ending at Flask.

For the HA stage, step 5 reaches Nginx on the load balancer. It selects a web server over the private network, and that server queries the shared private PostgreSQL service.

## Extra credit A discussion

Record the actual static IP, certificate issuer, IP subject alternative name, validity interval, firewall rules, renewal dry-run output, systemd timer and reload hook. Explain why HTTP port 80 stays open for this HTTP-01 renewal method even though users access HTTPS on port 443.

Compare the direct browser → Lightsail:443 route with the browser → Cloudflare → your PC → SSH → Lightsail route. Demonstrate the direct URL still works after stopping the tunnel processes. Explain the short certificate lifetime and distinguish a successful dry run from an observed scheduled renewal.

## Extra credit B discussion

Describe the roles of web1, web2, db and lb, and identify what runs on each. Explain round robin, passive failure detection, common database storage and shared signing keys. Include the actual requests showing both instance identities, the note saved before failure, web1 stopped, the same note read on web2, and a successful new write/login while web1 remains stopped.

Record any observed transition errors or delays. Do not claim exactly alternating browser requests, fully uninterrupted in-flight writes, or complete infrastructure high availability. The database, load balancer, local PC and tunnel route remain failure points. Both web instances are in the same availability zone in this compact implementation.

## Submission packaging

Export the completed report as PDF. Include relevant `.tf` files and the website/Ansible source, with a short README explaining the supporting files. Check that no credentials, PEMs, `.env`, `secrets.yml`, raw state or plan files are included. Use actual screenshots and outputs; do not replace missing experiments with mocked evidence.
