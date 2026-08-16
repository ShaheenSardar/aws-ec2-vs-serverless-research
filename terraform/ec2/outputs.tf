output "instance_id" {
  value = aws_instance.app.id
}

output "public_ip" {
  value = aws_instance.app.public_ip
}

output "health_url" {
  value = "http://${aws_instance.app.public_ip}/health"
}

output "compute_url" {
  value = "http://${aws_instance.app.public_ip}/compute"
}
