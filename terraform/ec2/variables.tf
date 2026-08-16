variable "aws_region" {
  type        = string
  description = "AWS Region used for the EC2 experimental architecture."
  default     = "ap-south-1"
}

variable "instance_type" {
  type        = string
  description = "Fixed EC2 instance type used during the formal comparison."
  default     = "t3.small"
}

variable "ami_id" {
  type        = string
  description = "Ubuntu 24.04 LTS x86_64 AMI ID for ap-south-1."
}
