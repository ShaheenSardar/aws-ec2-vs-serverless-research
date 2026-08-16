output "lambda_function_name" {
  value = aws_lambda_function.app.function_name
}

output "api_id" {
  value = aws_apigatewayv2_api.research.id
}

output "api_endpoint" {
  value = aws_apigatewayv2_api.research.api_endpoint
}

output "health_url" {
  value = "${aws_apigatewayv2_api.research.api_endpoint}/health"
}

output "compute_url" {
  value = "${aws_apigatewayv2_api.research.api_endpoint}/compute"
}
