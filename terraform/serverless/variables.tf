variable "aws_region" {
  type    = string
  default = "ap-south-1"
}

variable "lambda_memory_mb" {
  type    = number
  default = 1024
}

variable "lambda_timeout_seconds" {
  type    = number
  default = 30
}
