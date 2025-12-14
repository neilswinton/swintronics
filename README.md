# swintronics

## Services Used
There a number of third party services and tools used by this project.  These are the services and their roles.
- Terraform: This is a program used to deploy the server and configure some of its environment.  It is installed on your computer.
- Hetzner Cloud: Hetzner hosts the server itself.  Currently, this is compute, disk, and networking.  Hetzner Storage Boxes are a cost-efficient backup target, but not currently used.
- Infisical: Infisical manages secrets.  This project stores most of its secret data -- things like passwords and API keys -- in Infisical.  This keeps that information where you can't lose it but it is available to Terraform when building out the server.
- Cloudflare: This project uses Cloud
## Deploying a Server
Run terraform twice!

### Infisical

#### Machine Identity
See https://infisical.com/docs/documentation/platform/identities/universal-auth and skip down to the "Guide" section for step-by-step instructions.

1. Create identity with Admin role.

Copy the client ID and secret somewhere safe and add it to your .auto.tfvars file.  I recommend using a password safe.

In the Infisical project, give the machine identity Admin access.  (This may be overkill, we create a new project to hold the server's secrets.)

## Server initialization

Talk about cloud-init.  Refer to troubleshooting at https://cloudinit.readthedocs.io/en/latest/howto/debugging.html

### Manual steps

#### Copy .env files
#### Login to infisical and set env

#### Immich Server
- Setup email notifications.  I used SMTP2Go for free
- Setup external server name so the right URL is used in emails and notifications

### Replace Values
terraform apply  -replace="tailscale_oauth_client.docker_identity"
