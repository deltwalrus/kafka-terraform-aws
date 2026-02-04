
# Kafka on AWS MSK via Terraform (Demo)

## Prereqs
- Terraform >= 1.5
- AWS credentials with permissions for VPC, EC2, MSK, CloudWatch Logs, IAM key pairs.
- Internet egress for the client instance to fetch Kafka CLI.

## Deploy
```bash
terraform init
terraform plan -out tfplan
terraform apply tfplan
```

## Connect
```bash
chmod 600 ./demo-kafka-client-key.pem
ssh -i ./demo-kafka-client-key.pem ec2-user@$(terraform output -raw client_instance_public_ip)
cat ~/README-KAFKA.md
```

## Scale brokers (example)
Edit `variables.tf` → `broker_nodes = 6`
```bash
terraform plan
terraform apply
```

## Drift detection
Tweak a Security Group in AWS Console → then:
```bash
terraform plan
terraform apply
```

## Destroy
```bash
terraform destroy
```
