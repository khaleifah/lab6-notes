# lab6-notes

A small dynamic notes website for CCEN 448 Lab Exercise 6. Users can register,
sign in, and create or delete their own notes. Flask handles authentication
and authorization; PostgreSQL stores the users and notes. Each response
identifies its web instance for the load-balancing and failover experiment.

## Execution requirements

- Ubuntu 24.04 LTS for the supplied deployment scripts.
- Docker Engine and Docker Compose v2.
- Nginx, Git, curl and OpenSSL on the server.
- Python 3.12, Flask, Gunicorn and psycopg inside the web container.
- PostgreSQL 16 in a separate database container, with a persistent volume.

## Single-server setup

The OpenTofu configuration in `infra-single/lightsail-website.tf` creates a
Lightsail Ubuntu instance, static IPv4 address and public firewall rules.
Its launch script installs the OS packages and clones this repository into
`/opt/website`. It uses Ireland (`eu-west-1`), availability zone `eu-west-1a`
and regional SSH key `khaleifah-lab6-key`. The example 1 GB IPv4 bundle must be
checked against current availability and your account's free-tier eligibility.

After applying the configuration, connect as `ubuntu` and run:

```bash
sudo cloud-init status --wait
cd /opt/website
bash scripts/setup-single.sh
sudo docker compose ps
```

The setup script generates local secrets, initializes the database schema,
starts the web container and configures Nginx. It preserves existing `.env`
credentials and database records on reruns. Nginx listens on port 80; the web
container is published only at `127.0.0.1:8000`. PostgreSQL is not published to
the host's public interface.

Use a disposable lab-only account for the required initial HTTP demonstration.
To verify the running site, run:

```bash
python3 scripts/smoke-test.py http://127.0.0.1
```

The functional check creates two disposable accounts and verifies login,
record persistence, user isolation, CSRF checks and HTML escaping. Use the
HTTPS URL instead once secure cookies are enabled.

## Lab and extra-credit guides

- [Windows lab walkthrough](LAB_GUIDE.md)
- [IP HTTPS and two-server extra credit](EXTRA_CREDIT.md)
- [Report requirements and explanations](REPORT_GUIDE.md)
- [Checks and runtime limitations](VALIDATION.txt)

The extra credit includes an IP-address certificate with automatic renewal,
and a separate four-instance deployment: two web servers, a shared PostgreSQL
server and an Nginx load balancer. OpenTofu creates those resources; Ansible
configures them. Both web nodes share the same database and session signing
key. The single database and load balancer remain failure points.

## Credentials and cleanup

Use environment variables for AWS credentials. Application secrets are
generated at deployment and excluded from version control. Do not commit
private keys, credential exports, `.env`, `secrets.yml`, state, plans or report
screenshots. This teaching app has no signup rate limiting and is intended
for temporary lab use with non-sensitive data.

After saving evidence, stop the local tunnel processes, run `tofu destroy`
from every deployed infrastructure folder, and delete the manually created
IAM access key, policy, user and Lightsail key pair.
