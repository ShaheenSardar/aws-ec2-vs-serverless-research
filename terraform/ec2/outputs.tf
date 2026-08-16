output "instance_id" {
  value = aws_instance.app.id
}

output "public_ip" {
  value = aws_instance.app.public_ip
}

output "health_url" {
  value = aws_instance.app.public_ip != null ? "http://${aws_instance.app.public_ip}/health" : null
}

output "compute_url" {
  value = aws_instance.app.public_ip != null ? "http://${aws_instance.app.public_ip}/compute" : null
}
