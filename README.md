# Packer Docker + Nginx AMI

This Packer configuration builds an Ubuntu AMI with Docker and Nginx pre-installed and automatically configured to start on boot.

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
packer init aws-docker.pkr.hcl

# Build the AMI
packer build aws-docker.pkr.hcl

# Build with custom variables
packer build \
  -var="aws_region=us-west-2" \
  -var="instance_type=t3.small" \
  aws-docker.pkr.hcl
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

# Check if Nginx Docker container is running
docker ps | grep nginx-server

# Check systemd service status
systemctl status nginx-docker.service

# Test Nginx connectivity
curl localhost
# or from outside the instance
curl http://instance-public-ip
```

## File Structure

```
.
├── aws-docker.pkr.hcl       # Main Packer HCL configuration
├── cloud-init-nginx.yaml    # Cloud-init user data script
├── dockerfile               # Original Dockerfile (optional reference)
└── README.md               # This file
```

## Customization

### Change Nginx Configuration
Edit the systemd service in the Packer config (line ~103):
```hcl
ExecStart=/usr/bin/docker run --rm --name nginx-server -p 80:80 -v /opt/nginx/html:/usr/share/nginx/html:ro nginx:latest
```

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
