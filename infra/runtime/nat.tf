# ---------------------------------------------------------------------------
# NAT instance: lets tasks in the private-app subnets make OUTBOUND HTTPS calls
# (ECR API, Secrets Manager, CloudWatch Logs) while staying unreachable from
# the internet. ~5x cheaper than a managed NAT Gateway.
#
# Trade-off: one instance in one AZ = single point of failure for outbound
# traffic. Production would use one NAT Gateway per AZ.
# ---------------------------------------------------------------------------

# Latest Amazon Linux 2023 (ARM) AMI, published by AWS as a public SSM parameter.
data "aws_ssm_parameter" "al2023_arm64" {
  name = "/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-arm64"
}

resource "aws_instance" "nat" {
  ami                         = data.aws_ssm_parameter.al2023_arm64.value
  instance_type               = var.nat_instance_type
  subnet_id                   = local.f.public_subnet_ids[0]
  vpc_security_group_ids      = [local.sg.nat]
  associate_public_ip_address = true # its public IP is what all outbound traffic appears to come from

  # A NAT forwards traffic that isn't addressed to itself; AWS drops that by default.
  source_dest_check = false

  # IMDSv2 only: blocks SSRF-style theft of instance credentials.
  metadata_options {
    http_tokens   = "required"
    http_endpoint = "enabled"
  }

  root_block_device {
    volume_type = "gp3"
    volume_size = 8
    encrypted   = true
  }

  user_data_replace_on_change = true
  user_data                   = <<-EOF
    #!/bin/bash
    set -euxo pipefail

    # 1. Allow the kernel to forward packets between interfaces.
    echo 'net.ipv4.ip_forward = 1' > /etc/sysctl.d/90-nat.conf
    sysctl --system

    # 2. iptables service so the rules survive a reboot.
    dnf install -y iptables-services
    systemctl enable --now iptables

    # 3. Replace the distro's default rules (they REJECT forwarded traffic).
    IFACE=$(ip route show default | awk '{print $5; exit}')
    iptables -F
    iptables -t nat -F
    iptables -P INPUT ACCEPT   # the security group is the firewall here
    iptables -P FORWARD DROP
    iptables -A FORWARD -s ${local.f.vpc_cidr} -j ACCEPT
    iptables -A FORWARD -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT
    # 4. MASQUERADE = rewrite private source IPs to this instance's IP.
    iptables -t nat -A POSTROUTING -o "$IFACE" -s ${local.f.vpc_cidr} -j MASQUERADE
    iptables-save > /etc/sysconfig/iptables
  EOF

  tags = { Name = "${local.project}-nat" }
}

# The private-app subnets' only way out. Exists only while this layer exists.
resource "aws_route" "private_app_to_nat" {
  route_table_id         = local.f.private_app_route_table_id
  destination_cidr_block = "0.0.0.0/0"
  network_interface_id   = aws_instance.nat.primary_network_interface_id
}
