import json

from compute_logic import perform_computation


def response(status_code: int, payload: dict) -> dict:
    return {
        "statusCode": status_code,
        "headers": {
            "content-type": "application/json",
        },
        "body": json.dumps(payload),
    }


def lambda_handler(event, context):
    path = event.get("rawPath", "/")

    if path == "/health":
        return response(
            200,
            {
                "status": "healthy",
                "architecture": "serverless",
            },
        )

    if path == "/compute":
        result = perform_computation()

        return response(
            200,
            {
                "architecture": "serverless",
                **result,
            },
        )

    return response(
        404,
        {
            "error": "not_found",
        },
    )
