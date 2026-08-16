# Runable GCP Terraform

This directory contains reusable GCP modules and three independent Terraform roots:

| Root | Purpose |
| --- | --- |
| `environments/bootstrap-state` | Creates a private, uniformly accessed, versioned GCS state bucket. |
| `environments/single-host` | Creates one public runtime host with coordinator, proxy, and two logical workers. |
| `environments/two-region` | Creates a public gateway/control VM and one private nested-KVM worker in each of two regions. |

All VMs use Debian 12, whose distribution kernel is Linux 6.1. Runtime hosts default to Intel-backed `n2-standard-8`, standard non-Spot provisioning, explicit migrate/restart scheduling, nested virtualization, and a separate 250 GiB persistent artifact disk. No startup script downloads application source.

## Prerequisites

- Terraform 1.9 or newer.
- A GCP project with billing enabled.
- Application Default Credentials, normally from `gcloud auth application-default login`.
- Permission to enable project services and create Compute Engine, networking, address, firewall, router, NAT, and Storage resources.
- IAP and OS Login IAM grants for administrators. Firewall access alone does not grant SSH authorization.

Prefer dedicated gateway and worker service accounts with only application-specific IAM roles. The modules default to logging and monitoring OAuth scopes; IAM roles remain the authorization boundary.

## Bootstrap State

The bootstrap root intentionally uses local state because it creates the remote state bucket itself.

```shell
cd infra/gcp/environments/bootstrap-state
cp terraform.tfvars.example terraform.tfvars
terraform init
terraform plan
terraform apply
```

Use the resulting bucket to initialize each deployment root. The roots contain partial `gcs` backend configuration:

```shell
cd infra/gcp/environments/single-host
terraform init \
  -backend-config="bucket=YOUR_STATE_BUCKET" \
  -backend-config="prefix=runable/single-host"
```

Use a distinct prefix for `two-region`, such as `runable/two-region`. State object versioning is enabled, public access prevention is enforced, uniform bucket-level access is enabled, and `force_destroy` is disabled.

## Single Host

Copy `environments/single-host/terraform.tfvars.example` to a local tfvars file and set the project, service account, region, and client CIDRs. The topology includes:

- A custom VPC and one regional subnet.
- One nested-KVM runtime VM with a static external IPv4 address.
- One persistent artifact disk mounted at `/var/lib/runable`.
- Instance metadata advertising coordinator/proxy roles and exactly two logical worker configurations.
- Public API/proxy ingress only on `public_service_ports` and only from `allowed_client_cidrs`.
- SSH ingress only from Google's IAP TCP forwarding range, with OS Login enabled and project SSH keys blocked.

`allowed_client_cidrs` defaults to an empty list, so API/proxy ingress is closed until an explicit CIDR is configured.

## Two Region

Copy `environments/two-region/terraform.tfvars.example` to a local tfvars file and choose two distinct regions. The topology includes:

- A custom VPC with global dynamic routing and one subnet in each region.
- Cloud NAT in each region for private worker egress.
- A gateway/control VM in region A with the only static external IPv4 address.
- Private worker A in region A and private worker B in region B, each with nested virtualization and its own persistent artifact disk.
- Tag-scoped private ingress from workers to gateway agent ports, gateway to worker admin ports, and worker to worker peer ports.
- IAP-only SSH ingress to all three VMs. Workers do not receive external IP addresses.
- Public gateway API/proxy ingress only from `allowed_client_cidrs`.

The VPC's global routing mode and worker peer firewall rule permit private cross-region communication over the configured `worker_peer_ports`. Set all service port variables to match the deployed manifests; the defaults are placeholders for a conventional deployment and do not install or configure the application.

### Required Runtime Compatibility Check

Before scheduling workloads or restoring/migrating a Firecracker snapshot, deployment tooling **must compare a runtime CPU/KVM compatibility manifest across the source and destination workers**. At minimum, check architecture, CPU vendor/model/features, kernel/KVM capabilities, Firecracker version, guest kernel, and snapshot format/version. The startup script writes basic host facts to `/var/lib/runable/host-capabilities.json`, but that file alone is not a complete compatibility manifest.

Terraform's `min_cpu_platform` only asks Compute Engine for a minimum CPU generation. It is **not proof of snapshot compatibility**, does not guarantee identical exposed CPU feature sets between regions or hosts, and must not replace the runtime CPU/KVM manifest check.

## Startup Preparation

The nested host startup template:

- Creates the configured runtime user, group, mount point, and application directories.
- Formats an uninitialized artifact disk as ext4, mounts it by UUID, and persists it in `/etc/fstab`.
- Installs basic host prerequisites from Debian repositories.
- Configures `kvm` group permissions and a udev rule for `/dev/kvm`.
- Loads KVM modules, fails startup if `/dev/kvm` is unavailable, and records basic host capability facts.

It does not clone repositories, download binaries, install Firecracker, or start Runable services. Deploy scripts should consume Terraform outputs and perform those steps separately.

## Useful Outputs

Both deployment roots return instance names, zones, internal addresses, the public endpoint address, network IDs, disk IDs, and ready-to-run IAP SSH command strings. Use `terraform output -json` from deployment automation rather than parsing human-readable output.

## Validation

Credential-free static validation can be run with:

```shell
terraform fmt -recursive infra/gcp
terraform -chdir=infra/gcp/environments/bootstrap-state init -backend=false
terraform -chdir=infra/gcp/environments/bootstrap-state validate
terraform -chdir=infra/gcp/environments/single-host init -backend=false
terraform -chdir=infra/gcp/environments/single-host validate
terraform -chdir=infra/gcp/environments/two-region init -backend=false
terraform -chdir=infra/gcp/environments/two-region validate
```
