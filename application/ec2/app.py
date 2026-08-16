from flask import Flask, jsonify

from compute_logic import perform_computation

app = Flask(__name__)


@app.get("/health")
def health():
    return jsonify(
        status="healthy",
        architecture="ec2",
    ), 200


@app.get("/compute")
def compute():
    result = perform_computation()

    return jsonify(
        architecture="ec2",
        **result,
    ), 200


if __name__ == "__main__":
    app.run(
        host="127.0.0.1",
        port=8080,
        debug=False,
    )
