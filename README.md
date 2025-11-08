# ubuntu-landscape

This repository provides an **all-in-one Dockerized Ubuntu Landscape Server** based on the official `landscape-server-quickstart` package.

Instead of following the [original](https://documentation.ubuntu.com/landscape/how-to-guides/landscape-installation-and-set-up/quickstart-installation/) VM/LXD-based guide, this setup:

- Runs **PostgreSQL, RabbitMQ, Apache, and Landscape** inside a single container.
- Uses an entrypoint to:
  - start required services,
  - run `landscape-quickstart` exactly once,
  - patch Apache to use your chosen FQDN,
  - then run Apache in the foreground for proper container behavior.
- Persists configuration and data via Docker named volumes.

## Usage

1. Clone the repo.
2. Create a `.env` (see `.env.example`) and set:
   - `HOSTNAME`, `DOMAIN`
   - `EMAIL`, `SMTP_*`
   - other required values.
3. Provide TLS certs for the FQDN:
   - mount them over:
     - `/etc/ssl/certs/landscape_server.pem`
     - `/etc/ssl/private/landscape_server.key`
   - or use the existing self-signed ones for testing.
4. Start the stack:

   ```bash
   docker compose up --build
   ```

On first start, the container runs `landscape-quickstart` and initializes Landscape.
Subsequent restarts reuse the persisted configuration and skip re-initialization.

## Ingress / Traefik

The internal Apache instance **terminates TLS itself** and is not easily run in HTTP-only mode.
Because of this, the recommended pattern is:

- Run Apache on port `443` **inside** the container with the proper certificate.
- Use **Traefik with TLS passthrough**:
  - configure a TCP router with `HostSNI(\`${HOSTNAME}.${DOMAIN}\`)` on the `websecure` entrypoint,
  - route directly to the container’s port `443`,
  - do **not** terminate TLS in Traefik for this host.

Optionally, use Traefik on port `80` to redirect `http → https` for the same FQDN.

This keeps Landscape’s HTTPS-centric configuration intact while integrating cleanly into a Traefik-based ingress setup.
