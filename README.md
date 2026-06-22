# AWS Golden AMI with Packer, Docker, Nginx, and Terraform

![AWS](https://img.shields.io/badge/AWS-EC2-orange)
![Terraform](https://img.shields.io/badge/Terraform-IaC-purple)
![Packer](https://img.shields.io/badge/Packer-Golden_AMI-blue)
![Docker](https://img.shields.io/badge/Docker-Nginx-blue)

This repository provides a production-ready workflow to build a Golden AMI with Packer, deploy it with Terraform, and run Nginx inside Docker on EC2 instances. The AMI is based on Ubuntu 22.04 LTS and includes a pre-created Docker container and systemd services so instances are immediately serving traffic after launch.

## Architecture

Packer
→ Custom AMI
→ Terraform
→ EC2 Instance
→ Docker
→ Nginx Container
→ Dynamic Metadata Page

## Features

- Ubuntu 22.04 LTS
- Docker Engine (docker-ce, containerd)
- Nginx served from a Docker container
- Systemd service management (nginx-docker.service)
- Dynamic index.html generation at boot (generate-index.service)
- IMDSv2 metadata support (token-based metadata retrieval)
- Terraform deployment examples (launch-instances-FIXED.tf)
- CloudWatch alarm hooks (Terraform integration)
- Encrypted gp3 root volume
- Security group automation and parameterization

## Project Outcome

✅ Successfully built a custom AWS Golden AMI using Packer
✅ Installed and configured Docker automatically
✅ Created and managed an Nginx container through systemd
✅ Implemented dynamic metadata page generation at boot
✅ Deployed infrastructure using Terraform
✅ Configured CloudWatch monitoring and alarms
✅ Validated end-to-end deployment on AWS EC2

## What's Included

### 1. **Docker Installation**
- Installs Docker Engine, CLI, and containerd
- Enables Docker to start automatically on system boot
- Adds `ubuntu` user to the `docker` group

### 2. **Nginx in Docker**
- Sets up a Docker-based Nginx service
- Pre-creates `/opt/nginx/html/` directory for serving static content
- Deploys a default `index.html` page

### 3. **Auto-Start Mechanisms**

#### Systemd Service (`nginx-docker.service`)
- Created at AMI build time
- **Location**: `/etc/systemd/system/nginx-docker.service`
- **Features**:
  - Runs Nginx as a Docker container
  - Automatically restarts on failure (RestartSec=5)
  - Starts after Docker service is ready
  - Listens on port 80
  - Mounts `/opt/nginx/html/` as read-only volume

#### Cloud-Init Support
- **File**: `cloud-init-nginx.yaml`
- Used when launching EC2 instances as user data
- Ensures Nginx is started on instance boot
- Logs startup information to `/var/log/nginx-startup.log`

## Building the AMI

```bash
# Initialize Packer (first time only)
packer init aws-docker-FIXED.pkr.hcl

# Validate template
packer validate aws-docker-FIXED.pkr.hcl

# Build the AMI
packer build -var='aws_region=us-east-1' -var='instance_type=t3.small' aws-docker-FIXED.pkr.hcl

# Build with custom variables
packer build \
  -var="aws_region=us-west-2" \
  -var="instance_type=t3.small" \
  aws-docker-FIXED.pkr.hcl
```

## Terraform Deployment

Use the provided Terraform configuration to launch instances from the Golden AMI (launch-instances-FIXED.tf):

```bash
terraform init
terraform plan
terraform apply

# When finished
terraform destroy
```



## Launching EC2 Instances

### Option 1: Using Systemd (Built-in)
Nginx automatically starts via systemd service:
```bash
aws ec2 run-instances \
  --image-id ami-xxxxxxxxx \
  --instance-type t3.micro \
  --region us-east-1
```

### Option 2: Using Cloud-Init (User Data)
For additional configuration on instance launch:
```bash
aws ec2 run-instances \
  --image-id ami-xxxxxxxxx \
  --instance-type t3.micro \
  --user-data file://cloud-init-nginx.yaml \
  --region us-east-1
```

## Verification

After launching an instance:

```bash
# SSH into the instance
ssh -i your-key.pem ubuntu@instance-public-ip

# Check services
sudo systemctl status nginx-docker.service
sudo systemctl status generate-index.service

# Check the Docker container
sudo docker ps

# Verify generated index page
sudo cat /opt/nginx/html/index.html | head -50

# Test HTTP locally
curl -i localhost
# or from outside the instance
curl http://instance-public-ip
```

Basic troubleshooting commands:

```bash
sudo journalctl -u nginx-docker.service -n 100 --no-pager
sudo journalctl -u generate-index.service -n 100 --no-pager
sudo docker logs nginx-server
```

## File Structure

```
.
├── aws-docker-FIXED.pkr.hcl    # Final Packer template (production-ready)
├── launch-instances-FIXED.tf   # Terraform example to launch EC2 instances
├── cloud-init-nginx.yaml       # Cloud-init user data script (optional)
├── README.md                   # This file
└── scripts/                    # helper scripts (generate-index.sh, etc.)
```

## Customization

### Change Nginx Configuration
Edit the systemd service in the Packer config (line ~103). The production template starts a pre-created container, so the unit uses `docker start`:
```hcl
ExecStart=/usr/bin/docker start -a nginx-server
```
To use a custom image, update the AMI build steps to `docker pull` and `docker create` with your image name (so the AMI contains the created container), or modify the unit to `docker run` if you prefer the instance to pull/run the image at boot (not recommended for air-gapped or immutable AMIs).

### Serve Custom Content
Add your HTML files to `/opt/nginx/html/` on the EC2 instance:
```bash
scp -r ./my-website/* ubuntu@instance-ip:/opt/nginx/html/
```

### Use a Custom Docker Image
Modify the `ExecStart` command in the Packer config to use your custom image:
```hcl
ExecStart=/usr/bin/docker run --rm --name nginx-server -p 80:80 my-registry/my-nginx:latest
```

## Troubleshooting

**Nginx not running?**
```bash
sudo systemctl status nginx-docker.service
sudo journalctl -u nginx-docker.service -n 50
docker logs nginx-server
```

**Port 80 not accessible?**
- Ensure security group allows inbound traffic on port 80
- Check if Nginx container is listening: `docker port nginx-server`

**Docker daemon issues?**
```bash
sudo systemctl restart docker
sudo systemctl status docker
```

## Notes

- The AMI is tagged with `Name: docker-nginx-ami` for easy identification
- Startup logs are available at `/var/log/nginx-startup.log`
- The Nginx container runs with `--rm` flag, so stopped containers are automatically cleaned up
- The service uses `Restart=always` for high availability

---

**Built with Packer** | Ubuntu 22.04 LTS | Docker | Nginx

## Lessons Learned

### IMDSv2
Retrieving instance metadata requires token-based calls when IMDSv2 is enforced. The generate-index script is written to request metadata using short timeouts and to handle failures gracefully when metadata is not available.

### Root Volume Sizing
Terraform root volume sizes must be at least as large as the AMI snapshot. Under-provisioning the root volume can cause EC2 launch failures.

### Terraform Provider Tags
Setting provider-level `default_tags` with dynamic values (for example `timestamp()`) caused inconsistent plan diffs during development. Prefer resource-level tags for predictable plans.

## Issues Encountered and Resolved

### Packer Shell Compatibility

Provisioning initially failed because some shell features were not supported by the execution environment. The default shell was `/bin/sh` (dash), which does not support Bash-specific features like `pipefail`. Scripts were updated to explicitly use `/bin/bash` via the `execute_command` attribute in shell provisioners.

```hcl
provisioner "shell" {
  execute_command = "bash -c '{{ .Vars }} {{ .Path }}'"
  inline = [
    "set -euo pipefail",
    # ... commands
  ]
}
```

### IMDSv2 Metadata Retrieval

Instance metadata calls initially returned empty values because Terraform enforced IMDSv2. Token-based metadata requests were implemented in the generate-index script with proper timeouts and fallback handling.

```bash
TOKEN=$(curl -s -X PUT \
"http://169.254.169.254/latest/api/token" \
-H "X-aws-ec2-metadata-token-ttl-seconds: 21600")

INSTANCE_ID=$(curl -s \
-H "X-aws-ec2-metadata-token: $TOKEN" \
http://169.254.169.254/latest/meta-data/instance-id)

AVAILABILITY_ZONE=$(curl -s \
-H "X-aws-ec2-metadata-token: $TOKEN" \
http://169.254.169.254/latest/meta-data/placement/availability-zone)
```

### Terraform Provider Tagging Issue

Provider-level `default_tags` combined with `timestamp()` caused inconsistent final plan errors during `terraform apply`. The provider configuration was simplified and resource-level tags were retained to eliminate plan drift.

### Root Volume Sizing

Terraform attempted to launch an EC2 instance with a root volume smaller than the AMI snapshot size, causing launch failures. The root volume was increased to at least 30GB to meet AWS requirements and accommodate Docker images.

## Future Enhancements

- Application Load Balancer (ALB) in front of instances
- ACM-managed HTTPS certificates
- Route53 DNS and health checks
- Auto Scaling Groups with lifecycle hooks and warm pools
- GitHub Actions for automated AMI builds and releases
- Host Docker images in ECR instead of baking large images into AMIs
- SNS or third-party alerting for CloudWatch alarms

## Author

**Paul Foseh**

DevOps & Cloud Engineer  | Infrastructure as Code | Automation | CI/CD | Kubernetes & Platform Engineering

---

**Status:** Production-ready Golden AMI setup (Ubuntu 22.04, Docker, Nginx, dynamic metadata page)
