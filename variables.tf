
variable "region" {
  type        = string
  description = "AWS region to deploy into."
  default     = "us-east-2"
}

variable "name_prefix" {
  type        = string
  description = "Short name prefix for all resources."
  default     = "demo-kafka"
}

variable "vpc_cidr" {
  type        = string
  description = "CIDR for the demo VPC."
  default     = "10.0.0.0/16"
}

variable "kafka_version" {
  type        = string
  description = "MSK Kafka version (must be supported by AWS MSK)."
  default     = "3.7.0"
}

variable "broker_nodes" {
  type        = number
  description = "Number of broker nodes (must be a multiple of 3 for HA across AZs)."
  default     = 3
}

variable "broker_instance_type" {
  type        = string
  description = "MSK broker EC2 instance type."
  default     = "kafka.m5.large"
}

variable "broker_ebs_gb" {
  type        = number
  description = "EBS volume size (GiB) per broker."
  default     = 100
}

variable "enhanced_monitoring" {
  type        = string
  description = <<-EOT
  Enhanced monitoring level for MSK cluster.
  Valid values: "DEFAULT", "PER_BROKER", "PER_TOPIC_PER_PARTITION"
  EOT
  default     = "DEFAULT"
}

variable "ssh_cidr" {
  type        = string
  description = "CIDR allowed to SSH into the client instance (demo-friendly default)."
  default     = "0.0.0.0/0"
}

variable "tags" {
  type = map(string)
  description = "Tags applied to AWS resources."
  default = {
    "Project"   = "Kafka-Terraform-Demo"
    "Owner"     = "Solutions-Engineering"
    "ManagedBy" = "Terraform"
  }
}
