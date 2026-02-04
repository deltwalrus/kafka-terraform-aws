
###########################################################
# Data + Locals
###########################################################

data "aws_availability_zones" "available" {
  state = "available"
}

locals {
  azs      = slice(data.aws_availability_zones.available.names, 0, 3)
  name     = var.name_prefix
  tags     = var.tags
  vpc_name = "${var.name_prefix}-vpc"
}

###########################################################
# VPC + Subnets (modules)
###########################################################

module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "~> 5.0"

  name = local.vpc_name
  cidr = var.vpc_cidr

  azs              = local.azs
  public_subnets   = [for i, az in local.azs : cidrsubnet(var.vpc_cidr, 4, i)]                 # /20s
  private_subnets  = [for i, az in local.azs : cidrsubnet(var.vpc_cidr, 4, i + 8)]             # /20s (offset)

  enable_nat_gateway     = true
  single_nat_gateway     = true
  enable_dns_hostnames   = true
  enable_dns_support     = true
  map_public_ip_on_launch = true

  tags = merge(local.tags, {
    "Name" = local.vpc_name
  })
}

###########################################################
# Security Groups
###########################################################

# Client SG (for EC2 test instance)
resource "aws_security_group" "client" {
  name        = "${local.name}-client-sg"
  description = "Client SG for Kafka test instance"
  vpc_id      = module.vpc.vpc_id

  ingress {
    description = "SSH"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [var.ssh_cidr]
  }

  egress {
    description = "All egress"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(local.tags, { "Name" = "${local.name}-client-sg" })
}

# MSK SG (brokers)
resource "aws_security_group" "msk" {
  name        = "${local.name}-msk-sg"
  description = "Security group for MSK brokers"
  vpc_id      = module.vpc.vpc_id

  # TLS broker port (MSK uses 9094 for TLS)
  ingress {
    description     = "Kafka TLS from client SG"
    from_port       = 9094
    to_port         = 9094
    protocol        = "tcp"
    security_groups = [aws_security_group.client.id]
  }

  egress {
    description = "All egress"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(local.tags, { "Name" = "${local.name}-msk-sg" })
}

###########################################################
# CloudWatch Logs for Brokers
###########################################################

resource "aws_cloudwatch_log_group" "msk" {
  name              = "/aws/msk/${local.name}"
  retention_in_days = 7

  tags = merge(local.tags, { "Name" = "${local.name}-logs" })
}

###########################################################
# MSK Configuration
###########################################################

resource "aws_msk_configuration" "this" {
  name           = "${local.name}-config"
  kafka_versions = [var.kafka_version]
  description    = "Demo Kafka server properties"

  server_properties = <<-PROPS
    auto.create.topics.enable = true
    delete.topic.enable       = true
    num.partitions            = 3
    default.replication.factor= 3
    min.insync.replicas       = 2
    log.retention.hours       = 168
  PROPS

  tags = merge(local.tags, { "Name" = "${local.name}-config" })
}

###########################################################
# MSK Cluster (Provisioned)
###########################################################

resource "aws_msk_cluster" "this" {
  cluster_name           = "${local.name}-msk"
  kafka_version          = var.kafka_version
  number_of_broker_nodes = var.broker_nodes

  broker_node_group_info {
    instance_type   = var.broker_instance_type
    security_groups = [aws_security_group.msk.id]
    client_subnets  = module.vpc.private_subnets

    storage_info {
      ebs_storage_info {
        volume_size = var.broker_ebs_gb
      }
    }
  }

  configuration_info {
    arn      = aws_msk_configuration.this.arn
    revision = aws_msk_configuration.this.latest_revision
  }

  client_authentication {
    # Demo-friendly: allow unauthenticated (no SASL/IAM/SCRAM), TLS in transit.
    unauthenticated = true
  }

  encryption_info {
    encryption_in_transit {
      client_broker = "TLS"
      in_cluster    = true
    }
  }

  logging_info {
    broker_logs {
      cloudwatch_logs {
        enabled   = true
        log_group = aws_cloudwatch_log_group.msk.name
      }
    }
  }

  enhanced_monitoring = var.enhanced_monitoring

  tags = merge(local.tags, { "Name" = "${local.name}-msk" })
}

###########################################################
# Client EC2: Key pair
###########################################################

resource "tls_private_key" "client" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

resource "aws_key_pair" "client" {
  key_name   = "${local.name}-client-key"
  public_key = tls_private_key.client.public_key_openssh
}

# Save the private key locally for SSH
resource "local_file" "client_pem" {
  filename        = "${path.module}/${local.name}-client-key.pem"
  content         = tls_private_key.client.private_key_pem
  file_permission = "0600"
}

###########################################################
# Client EC2: AMI + Instance
###########################################################

# Amazon Linux 2023 (x86_64) latest
data "aws_ami" "al2023" {
  owners      = ["137112412989"] # Amazon
  most_recent = true

  filter {
    name   = "name"
    values = ["al2023-ami-*-x86_64"]
  }
}

locals {
  user_data = <<-BASH
    #!/bin/bash
    set -euo pipefail

    # Basic deps
    dnf update -y
    dnf install -y tar gzip java-17-amazon-corretto curl jq

    # Install Kafka CLI
    cd /opt
    KVER="3.7.0"
    curl -L -o "kafka.tgz" "https://downloads.apache.org/kafka/${KVER}/kafka_2.13-${KVER}.tgz"
    tar -xzf kafka.tgz
    ln -s "kafka_2.13-${KVER}" kafka
    chown -R ec2-user:ec2-user /opt/kafka_2.13-${KVER}

    # Prepare demo config for TLS (no client auth)
    mkdir -p /home/ec2-user/kafka-demo
    cat >/home/ec2-user/kafka-demo/client.properties <<'EOF'
    security.protocol=SSL
    EOF
    chown -R ec2-user:ec2-user /home/ec2-user/kafka-demo

    # Write a helper README with ready-to-run commands
    cat >/home/ec2-user/README-KAFKA.md <<'EOF'
    # Kafka MSK Demo

    Export bootstrap TLS brokers:
      export BOOT="{{bootstrap}}"

    Create a topic:
      /opt/kafka/bin/kafka-topics.sh --bootstrap-server $BOOT --create --topic demo-topic --partitions 3 --replication-factor 3 --command-config /home/ec2-user/kafka-demo/client.properties

    List topics:
      /opt/kafka/bin/kafka-topics.sh --bootstrap-server $BOOT --list --command-config /home/ec2-user/kafka-demo/client.properties

    Start a console consumer:
      /opt/kafka/bin/kafka-console-consumer.sh --bootstrap-server $BOOT --topic demo-topic --from-beginning --consumer.config /home/ec2-user/kafka-demo/client.properties

    Send test messages (new terminal):
      /opt/kafka/bin/kafka-console-producer.sh --bootstrap-server $BOOT --topic demo-topic --producer.config /home/ec2-user/kafka-demo/client.properties
      # type a few lines, then Ctrl+C
    EOF

    # Replace placeholder with real bootstrap brokers (Terraform will template this)
    sed -i "s|{{bootstrap}}|${BOOTSTRAP_TLS}|g" /home/ec2-user/README-KAFKA.md
    chown ec2-user:ec2-user /home/ec2-user/README-KAFKA.md
  BASH
}

# We template in the bootstrap brokers after creation via instance user_data_replace_on_change
resource "aws_instance" "client" {
  ami                         = data.aws_ami.al2023.id
  instance_type               = "t3.small"
  subnet_id                   = module.vpc.public_subnets[0]
  vpc_security_group_ids      = [aws_security_group.client.id]
  key_name                    = aws_key_pair.client.key_name
  associate_public_ip_address = true

  user_data = replace(local.user_data, "${BOOTSTRAP_TLS}", aws_msk_cluster.this.bootstrap_brokers_tls)

  tags = merge(local.tags, { "Name" = "${local.name}-client" })
}
