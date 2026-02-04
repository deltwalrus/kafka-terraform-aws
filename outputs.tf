
output "msk_cluster_arn" {
  description = "ARN of the MSK cluster"
  value       = aws_msk_cluster.this.arn
}

output "bootstrap_brokers_tls" {
  description = "TLS bootstrap brokers for MSK"
  value       = aws_msk_cluster.this.bootstrap_brokers_tls
}

output "client_instance_public_ip" {
  description = "Public IP for SSH to the client instance"
  value       = aws_instance.client.public_ip
}

output "ssh_private_key_path" {
  description = "Path to the generated SSH private key for the client instance"
  value       = local_file.client_pem.filename
}

output "client_readme_hint" {
  description = "Path hint for the client README on the instance"
  value       = "/home/ec2-user/README-KAFKA.md"
}
