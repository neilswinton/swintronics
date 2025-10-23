# swintronics

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
